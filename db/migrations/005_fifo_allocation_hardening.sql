-- Harden FIFO allocation by assigning every movement a deterministic sequence.
-- Positive layers and negative outflow intervals are derived from that same
-- sequence, so replenishment after zero stock cannot be consumed by earlier sales.

CREATE OR REPLACE VIEW inventory_sale_costs AS
WITH events AS (
  SELECT m.id AS movement_id, m.product_id, m.type, m.quantity::numeric AS quantity,
    COALESCE(m.unit_cost, 0)::numeric AS unit_cost,
    ROW_NUMBER() OVER (PARTITION BY m.product_id ORDER BY m.created_at, m.id) AS seq,
    COALESCE(SUM(GREATEST(m.quantity, 0)) OVER (
      PARTITION BY m.product_id ORDER BY m.created_at, m.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::numeric AS positive_before,
    COALESCE(SUM(GREATEST(-m.quantity, 0)) OVER (
      PARTITION BY m.product_id ORDER BY m.created_at, m.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::numeric AS outflow_before,
    COALESCE(SUM(GREATEST(-m.quantity, 0)) OVER (
      PARTITION BY m.product_id ORDER BY m.created_at, m.id
      ROWS UNBOUNDED PRECEDING
    ), 0)::numeric AS outflow_after
  FROM inventory_movements m
), layers AS (
  SELECT movement_id, product_id, quantity, unit_cost,
    positive_before AS layer_start,
    positive_before + quantity AS layer_end
  FROM events
  WHERE quantity > 0
), outflows AS (
  SELECT movement_id, product_id, type, outflow_before AS out_start, outflow_after AS out_end
  FROM events
  WHERE quantity < 0
), allocations AS (
  SELECT o.movement_id, l.unit_cost,
    GREATEST(0::numeric,
      LEAST(l.layer_end, o.out_end) - GREATEST(l.layer_start, o.out_start)
    ) AS allocated_quantity
  FROM outflows o
  JOIN layers l ON l.product_id = o.product_id
    AND l.layer_start < o.out_end
    AND l.layer_end > o.out_start
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
    COALESCE(m.unit_cost, 0)::numeric AS unit_cost, m.created_at,
    COALESCE(SUM(GREATEST(m.quantity, 0)) OVER (
      PARTITION BY m.product_id ORDER BY m.created_at, m.id
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0)::numeric AS layer_start
  FROM inventory_movements m
), layers AS (
  SELECT movement_id, product_id, quantity, unit_cost, layer_start,
    layer_start + quantity AS layer_end
  FROM events
  WHERE quantity > 0
), total_outflow AS (
  SELECT product_id, COALESCE(SUM(GREATEST(-quantity, 0)), 0)::numeric AS outflow
  FROM inventory_movements
  GROUP BY product_id
), remaining AS (
  SELECT l.product_id, l.movement_id,
    GREATEST(0::numeric, l.quantity - GREATEST(0::numeric,
      LEAST(l.quantity, COALESCE(o.outflow, 0) - l.layer_start))) AS remaining_quantity,
    l.unit_cost
  FROM layers l
  LEFT JOIN total_outflow o ON o.product_id = l.product_id
), fifo AS (
  SELECT product_id,
    COALESCE(SUM(remaining_quantity * unit_cost), 0)::numeric AS stock_cost
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
