-- Harden FIFO allocation by deriving consumption from cumulative outflow.
-- This avoids interval-fragment accumulation across repeated outflows and keeps
-- the layer calculation deterministic even when stock returns to zero and is
-- subsequently replenished.

CREATE OR REPLACE VIEW inventory_sale_costs AS
WITH fifo_layers AS (
  SELECT m.id AS movement_id, m.product_id, m.quantity::numeric AS quantity,
    COALESCE(m.unit_cost, 0)::numeric AS unit_cost,
    COALESCE(SUM(m.quantity) OVER (
      PARTITION BY m.product_id
      ORDER BY m.created_at, m.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::numeric AS layer_start
  FROM inventory_movements m
  WHERE m.quantity > 0
), outflows AS (
  SELECT m.id AS movement_id, m.product_id, m.type,
    SUM(-m.quantity) OVER (
      PARTITION BY m.product_id
      ORDER BY m.created_at, m.id
      ROWS UNBOUNDED PRECEDING
    )::numeric AS out_end
  FROM inventory_movements m
  WHERE m.quantity < 0
), allocations AS (
  SELECT o.movement_id, o.product_id, o.type, l.unit_cost,
    GREATEST(0::numeric, LEAST(l.quantity, o.out_end - l.layer_start)) AS allocated_quantity
  FROM outflows o
  JOIN fifo_layers l
    ON l.product_id = o.product_id
   AND l.layer_start < o.out_end
)
SELECT w.movement_id, w.product_id, w.type,
  COALESCE(SUM(a.allocated_quantity * a.unit_cost), 0)::numeric AS fifo_cost,
  COALESCE(w.sale_cost, 0)::numeric AS wac_cost
FROM inventory_valuation_wac_events w
LEFT JOIN allocations a ON a.movement_id = w.movement_id
WHERE w.type = 'SALE'
GROUP BY w.movement_id, w.product_id, w.type, w.sale_cost;

CREATE OR REPLACE VIEW inventory_valuation AS
WITH fifo_layers AS (
  SELECT m.id AS movement_id, m.product_id, m.quantity::numeric AS quantity,
    COALESCE(m.unit_cost, 0)::numeric AS unit_cost,
    COALESCE(SUM(m.quantity) OVER (
      PARTITION BY m.product_id
      ORDER BY m.created_at, m.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::numeric AS layer_start
  FROM inventory_movements m
  WHERE m.quantity > 0
), total_outflow AS (
  SELECT product_id, COALESCE(SUM(-quantity), 0)::numeric AS outflow
  FROM inventory_movements
  WHERE quantity < 0
  GROUP BY product_id
), remaining AS (
  SELECT l.product_id, l.movement_id,
    GREATEST(0::numeric, l.quantity - GREATEST(0::numeric,
      LEAST(l.quantity, COALESCE(o.outflow, 0) - l.layer_start))) AS remaining_quantity,
    l.unit_cost
  FROM fifo_layers l
  LEFT JOIN total_outflow o ON o.product_id = l.product_id
), fifo AS (
  SELECT product_id, COALESCE(SUM(remaining_quantity * unit_cost), 0)::numeric AS stock_cost
  FROM remaining
  GROUP BY product_id
), wac AS (
  SELECT DISTINCT ON (product_id) product_id,
    GREATEST(qty_after, 0)::numeric AS stock_quantity,
    GREATEST(qty_after, 0) * avg_after AS stock_cost
  FROM inventory_valuation_wac_events
  ORDER BY product_id, seq DESC
)
SELECT p.id AS product_id, p.name, p.current_stock,
  COALESCE(w.stock_quantity, 0)::numeric AS ledger_quantity,
  COALESCE(w.stock_cost, 0)::numeric AS wac_stock_cost,
  COALESCE(f.stock_cost, 0)::numeric AS fifo_stock_cost
FROM products p
LEFT JOIN wac w ON w.product_id = p.id
LEFT JOIN fifo f ON f.product_id = p.id;
