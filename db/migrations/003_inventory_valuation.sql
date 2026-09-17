ALTER TABLE inventory_movements
  ADD COLUMN IF NOT EXISTS unit_cost NUMERIC(14,2) CHECK (unit_cost >= 0);

UPDATE inventory_movements m
SET unit_cost = p.unit_cost
FROM purchases p
WHERE m.type = 'PURCHASE'
  AND m.reference_id = p.id
  AND m.unit_cost IS NULL;

UPDATE inventory_movements m
SET unit_cost = s.unit_cost
FROM sales s
WHERE m.type = 'SALE'
  AND m.reference_id = s.id
  AND m.unit_cost IS NULL;

CREATE TABLE IF NOT EXISTS inventory_valuation_settings (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  method TEXT NOT NULL CHECK (method IN ('WAC', 'FIFO')) DEFAULT 'WAC',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO inventory_valuation_settings (id, method)
VALUES (1, 'WAC')
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE VIEW inventory_valuation_wac_events AS
WITH RECURSIVE events AS (
  SELECT
    m.id AS movement_id,
    m.product_id,
    m.type,
    m.quantity AS delta,
    ABS(m.quantity) AS quantity,
    COALESCE(m.unit_cost, 0)::numeric AS unit_cost,
    ROW_NUMBER() OVER (PARTITION BY m.product_id ORDER BY m.created_at, m.id) AS seq
  FROM inventory_movements m
),
wac AS (
  SELECT
    e.product_id, e.seq, e.movement_id, e.type, e.delta, e.quantity, e.unit_cost,
    0::numeric AS qty_before,
    0::numeric AS avg_before,
    e.delta::numeric AS qty_after,
    CASE
      WHEN e.type = 'PURCHASE' OR (e.type = 'ADJUSTMENT' AND e.delta > 0)
        THEN e.unit_cost
      ELSE 0::numeric
    END AS avg_after,
    CASE WHEN e.type = 'SALE' THEN e.quantity * 0::numeric ELSE 0::numeric END AS sale_cost
  FROM events e
  WHERE e.seq = 1

  UNION ALL

  SELECT
    e.product_id, e.seq, e.movement_id, e.type, e.delta, e.quantity, e.unit_cost,
    w.qty_after,
    w.avg_after,
    q.qty_after,
    CASE
      WHEN e.type = 'PURCHASE' OR (e.type = 'ADJUSTMENT' AND e.delta > 0)
        THEN ((w.qty_after * w.avg_after) + (e.quantity * e.unit_cost)) / NULLIF(q.qty_after, 0)
      ELSE w.avg_after
    END,
    CASE WHEN e.type = 'SALE' THEN e.quantity * w.avg_after ELSE 0::numeric END
  FROM wac w
  JOIN events e
    ON e.product_id = w.product_id
   AND e.seq = w.seq + 1
  CROSS JOIN LATERAL (
    SELECT w.qty_after + e.delta::numeric AS qty_after
  ) q
)
SELECT * FROM wac;

CREATE OR REPLACE VIEW inventory_sale_costs AS
WITH fifo_layers AS (
  SELECT
    m.id AS movement_id,
    m.product_id,
    m.created_at,
    m.quantity::numeric AS quantity,
    m.unit_cost::numeric AS unit_cost,
    COALESCE(SUM(m.quantity) OVER (
      PARTITION BY m.product_id
      ORDER BY m.created_at, m.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::numeric AS layer_start,
    SUM(m.quantity) OVER (
      PARTITION BY m.product_id
      ORDER BY m.created_at, m.id
      ROWS UNBOUNDED PRECEDING
    )::numeric AS layer_end
  FROM inventory_movements m
  WHERE m.quantity > 0
),
outflows AS (
  SELECT
    m.id AS movement_id,
    m.product_id,
    m.created_at,
    m.type,
    (-m.quantity)::numeric AS quantity,
    COALESCE(SUM(-m.quantity) OVER (
      PARTITION BY m.product_id
      ORDER BY m.created_at, m.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::numeric AS out_start,
    SUM(-m.quantity) OVER (
      PARTITION BY m.product_id
      ORDER BY m.created_at, m.id
      ROWS UNBOUNDED PRECEDING
    )::numeric AS out_end
  FROM inventory_movements m
  WHERE m.quantity < 0
),
fifo_allocations AS (
  SELECT
    o.movement_id,
    o.product_id,
    o.type,
    l.movement_id AS layer_movement_id,
    GREATEST(
      0::numeric,
      LEAST(l.layer_end, o.out_end) - GREATEST(l.layer_start, o.out_start)
    ) AS allocated_quantity,
    l.unit_cost
  FROM outflows o
  JOIN fifo_layers l
    ON l.product_id = o.product_id
   AND l.layer_start < o.out_end
   AND l.layer_end > o.out_start
)
SELECT
  w.movement_id,
  w.product_id,
  w.type,
  COALESCE(SUM(a.allocated_quantity * a.unit_cost), 0)::numeric AS fifo_cost,
  COALESCE(w.sale_cost, 0)::numeric AS wac_cost
FROM inventory_valuation_wac_events w
LEFT JOIN fifo_allocations a ON a.movement_id = w.movement_id
WHERE w.type = 'SALE'
GROUP BY w.movement_id, w.product_id, w.type, w.sale_cost;

CREATE OR REPLACE VIEW inventory_valuation AS
WITH fifo_layers AS (
  SELECT
    m.id AS movement_id,
    m.product_id,
    m.quantity::numeric AS quantity,
    m.unit_cost::numeric AS unit_cost,
    COALESCE(SUM(m.quantity) OVER (
      PARTITION BY m.product_id
      ORDER BY m.created_at, m.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::numeric AS layer_start,
    SUM(m.quantity) OVER (
      PARTITION BY m.product_id
      ORDER BY m.created_at, m.id
      ROWS UNBOUNDED PRECEDING
    )::numeric AS layer_end
  FROM inventory_movements m
  WHERE m.quantity > 0
),
outflows AS (
  SELECT
    m.product_id,
    (-m.quantity)::numeric AS quantity,
    COALESCE(SUM(-m.quantity) OVER (
      PARTITION BY m.product_id
      ORDER BY m.created_at, m.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::numeric AS out_start,
    SUM(-m.quantity) OVER (
      PARTITION BY m.product_id
      ORDER BY m.created_at, m.id
      ROWS UNBOUNDED PRECEDING
    )::numeric AS out_end
  FROM inventory_movements m
  WHERE m.quantity < 0
),
fifo_remaining AS (
  SELECT
    l.product_id,
    l.movement_id,
    l.quantity - COALESCE(SUM(
      GREATEST(0::numeric, LEAST(l.layer_end, o.out_end) - GREATEST(l.layer_start, o.out_start))
    ), 0) AS remaining_quantity,
    l.unit_cost
  FROM fifo_layers l
  LEFT JOIN outflows o
    ON o.product_id = l.product_id
   AND l.layer_start < o.out_end
   AND l.layer_end > o.out_start
  GROUP BY l.product_id, l.movement_id, l.quantity, l.unit_cost, l.layer_start, l.layer_end
),
fifo AS (
  SELECT product_id, COALESCE(SUM(remaining_quantity * unit_cost), 0)::numeric AS stock_cost
  FROM fifo_remaining
  GROUP BY product_id
),
wac AS (
  SELECT DISTINCT ON (product_id)
    product_id,
    GREATEST(qty_after, 0)::numeric AS stock_quantity,
    GREATEST(qty_after, 0) * avg_after AS stock_cost
  FROM inventory_valuation_wac_events
  ORDER BY product_id, seq DESC
)
SELECT
  p.id AS product_id,
  p.name,
  p.current_stock,
  COALESCE(w.stock_quantity, 0)::numeric AS ledger_quantity,
  COALESCE(w.stock_cost, 0)::numeric AS wac_stock_cost,
  COALESCE(f.stock_cost, 0)::numeric AS fifo_stock_cost
FROM products p
LEFT JOIN wac w ON w.product_id = p.id
LEFT JOIN fifo f ON f.product_id = p.id;

CREATE OR REPLACE VIEW inventory_valuation_selected AS
SELECT
  v.*,
  s.method,
  CASE WHEN s.method = 'FIFO' THEN v.fifo_stock_cost ELSE v.wac_stock_cost END AS selected_stock_cost
FROM inventory_valuation v
CROSS JOIN inventory_valuation_settings s
WHERE s.id = 1;
