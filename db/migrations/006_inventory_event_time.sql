ALTER TABLE inventory_movements
  ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMPTZ;

UPDATE inventory_movements m
SET occurred_at = CASE
  WHEN m.type = 'PURCHASE' THEN COALESCE((SELECT p.purchased_at FROM purchases p WHERE p.id = m.reference_id), m.created_at)
  WHEN m.type = 'SALE' THEN COALESCE((SELECT s.sold_at FROM sales s WHERE s.id = m.reference_id), m.created_at)
  ELSE m.created_at
END
WHERE m.occurred_at IS NULL;

ALTER TABLE inventory_movements
  ALTER COLUMN occurred_at DROP DEFAULT,
  ALTER COLUMN occurred_at SET NOT NULL;

CREATE OR REPLACE FUNCTION shade_fill_inventory_movement_times()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.type = 'PURCHASE' THEN
    SELECT purchased_at INTO NEW.occurred_at FROM purchases WHERE id = NEW.reference_id;
  ELSIF NEW.type = 'SALE' THEN
    SELECT sold_at INTO NEW.occurred_at FROM sales WHERE id = NEW.reference_id;
  ELSE
    NEW.occurred_at := COALESCE(NEW.occurred_at, NEW.created_at);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fill_inventory_movement_times ON inventory_movements;
CREATE TRIGGER trg_fill_inventory_movement_times
BEFORE INSERT ON inventory_movements
FOR EACH ROW EXECUTE FUNCTION shade_fill_inventory_movement_times();

CREATE INDEX IF NOT EXISTS idx_inventory_movements_product_occurred_id
  ON inventory_movements(product_id, occurred_at, id);

CREATE OR REPLACE VIEW inventory_valuation_wac_events AS
WITH RECURSIVE events AS (
  SELECT m.id AS movement_id, m.product_id, m.type, m.quantity AS delta,
    ABS(m.quantity) AS quantity, COALESCE(m.unit_cost, 0)::numeric AS unit_cost,
    ROW_NUMBER() OVER (PARTITION BY m.product_id ORDER BY m.occurred_at, m.id) AS seq
  FROM inventory_movements m
), wac AS (
  SELECT e.product_id, e.seq, e.movement_id, e.type, e.delta, e.quantity, e.unit_cost,
    0::numeric AS qty_before, 0::numeric AS avg_before, e.delta::numeric AS qty_after,
    CASE WHEN e.type = 'PURCHASE' OR (e.type = 'ADJUSTMENT' AND e.delta > 0) THEN e.unit_cost ELSE 0::numeric END AS avg_after,
    0::numeric AS sale_cost
  FROM events e WHERE e.seq = 1
  UNION ALL
  SELECT e.product_id, e.seq, e.movement_id, e.type, e.delta, e.quantity, e.unit_cost,
    w.qty_after, w.avg_after, q.qty_after,
    CASE WHEN e.type = 'PURCHASE' OR (e.type = 'ADJUSTMENT' AND e.delta > 0)
      THEN ((w.qty_after * w.avg_after) + (e.quantity * e.unit_cost)) / NULLIF(q.qty_after, 0)
      ELSE w.avg_after END,
    CASE WHEN e.type = 'SALE' THEN e.quantity * w.avg_after ELSE 0::numeric END
  FROM wac w JOIN events e ON e.product_id = w.product_id AND e.seq = w.seq + 1
  CROSS JOIN LATERAL (SELECT w.qty_after + e.delta::numeric AS qty_after) q
)
SELECT * FROM wac;

CREATE OR REPLACE VIEW inventory_sale_costs AS
WITH events AS (
  SELECT m.id AS movement_id, m.product_id, m.type, m.quantity::numeric AS quantity,
    COALESCE(m.unit_cost, 0)::numeric AS unit_cost,
    ROW_NUMBER() OVER (PARTITION BY m.product_id ORDER BY m.occurred_at, m.id) AS seq,
    COALESCE(SUM(GREATEST(m.quantity, 0)) OVER (
      PARTITION BY m.product_id ORDER BY m.occurred_at, m.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::numeric AS positive_before,
    COALESCE(SUM(GREATEST(-m.quantity, 0)) OVER (
      PARTITION BY m.product_id ORDER BY m.occurred_at, m.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::numeric AS outflow_before,
    COALESCE(SUM(GREATEST(-m.quantity, 0)) OVER (
      PARTITION BY m.product_id ORDER BY m.occurred_at, m.id
      ROWS UNBOUNDED PRECEDING
    ), 0)::numeric AS outflow_after
  FROM inventory_movements m
), layers AS (
  SELECT movement_id, product_id, quantity, unit_cost,
    positive_before AS layer_start,
    positive_before + quantity AS layer_end
  FROM events WHERE quantity > 0
), outflows AS (
  SELECT movement_id, product_id, type, outflow_before AS out_start, outflow_after AS out_end
  FROM events WHERE quantity < 0
), allocations AS (
  SELECT o.movement_id, l.unit_cost,
    GREATEST(0::numeric, LEAST(l.layer_end, o.out_end) - GREATEST(l.layer_start, o.out_start)) AS allocated_quantity
  FROM outflows o JOIN layers l ON l.product_id = o.product_id
    AND l.layer_start < o.out_end AND l.layer_end > o.out_start
)
SELECT w.movement_id, w.product_id, w.type,
  COALESCE(SUM(a.allocated_quantity * a.unit_cost), 0)::numeric AS fifo_cost,
  COALESCE(w.sale_cost, 0)::numeric AS wac_cost
FROM inventory_valuation_wac_events w
LEFT JOIN allocations a ON a.movement_id = w.movement_id
WHERE w.type = 'SALE'
GROUP BY w.movement_id, w.product_id, w.type, w.sale_cost;

CREATE OR REPLACE VIEW inventory_valuation AS
WITH events AS (
  SELECT m.id AS movement_id, m.product_id, m.quantity::numeric AS quantity,
    COALESCE(m.unit_cost, 0)::numeric AS unit_cost,
    COALESCE(SUM(GREATEST(m.quantity, 0)) OVER (
      PARTITION BY m.product_id ORDER BY m.occurred_at, m.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::numeric AS layer_start
  FROM inventory_movements m
), layers AS (
  SELECT movement_id, product_id, quantity, unit_cost, layer_start, layer_start + quantity AS layer_end
  FROM events WHERE quantity > 0
), total_outflow AS (
  SELECT product_id, COALESCE(SUM(GREATEST(-quantity, 0)), 0)::numeric AS outflow
  FROM inventory_movements GROUP BY product_id
), remaining AS (
  SELECT l.product_id, l.movement_id,
    GREATEST(0::numeric, l.quantity - GREATEST(0::numeric,
      LEAST(l.quantity, COALESCE(o.outflow, 0) - l.layer_start))) AS remaining_quantity,
    l.unit_cost
  FROM layers l LEFT JOIN total_outflow o ON o.product_id = l.product_id
), fifo AS (
  SELECT product_id, COALESCE(SUM(remaining_quantity * unit_cost), 0)::numeric AS stock_cost
  FROM remaining GROUP BY product_id
), wac AS (
  SELECT DISTINCT ON (product_id) product_id, GREATEST(qty_after, 0)::numeric AS stock_quantity,
    GREATEST(qty_after, 0) * avg_after AS stock_cost
  FROM inventory_valuation_wac_events ORDER BY product_id, seq DESC
)
SELECT p.id AS product_id, p.name, p.current_stock,
  COALESCE(w.stock_quantity, 0)::numeric AS ledger_quantity,
  COALESCE(w.stock_cost, 0)::numeric AS wac_stock_cost,
  COALESCE(f.stock_cost, 0)::numeric AS fifo_stock_cost
FROM products p LEFT JOIN wac w ON w.product_id = p.id LEFT JOIN fifo f ON f.product_id = p.id;
