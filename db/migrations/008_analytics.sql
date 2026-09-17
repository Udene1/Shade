CREATE OR REPLACE VIEW sales_analytics AS
WITH sold AS (
  SELECT
    s.id AS sale_id,
    s.product_id,
    s.quantity::numeric AS quantity,
    s.unit_price::numeric AS unit_price,
    s.unit_cost::numeric AS recorded_unit_cost,
    s.sold_at
  FROM sales s
), costs AS (
  SELECT
    sold.sale_id,
    COALESCE(isc.fifo_cost, sold.quantity * sold.recorded_unit_cost) AS fifo_cogs,
    COALESCE(isc.wac_cost, sold.quantity * sold.recorded_unit_cost) AS wac_cogs
  FROM sold
  LEFT JOIN inventory_sale_costs isc ON isc.movement_id = (
    SELECT im.id FROM inventory_movements im
    WHERE im.type = 'SALE' AND im.reference_id = sold.sale_id
    ORDER BY im.id LIMIT 1
  )
)
SELECT
  sold.sale_id,
  sold.product_id,
  sold.quantity,
  sold.quantity * sold.unit_price AS revenue,
  costs.fifo_cogs,
  costs.wac_cogs,
  sold.quantity * sold.unit_price - costs.fifo_cogs AS fifo_gross_profit,
  sold.quantity * sold.unit_price - costs.wac_cogs AS wac_gross_profit,
  sold.sold_at
FROM sold
JOIN costs ON costs.sale_id = sold.sale_id;

CREATE OR REPLACE VIEW product_analytics AS
WITH sales_rollup AS (
  SELECT
    product_id,
    SUM(quantity) AS units_sold,
    SUM(revenue) AS revenue,
    SUM(fifo_cogs) AS fifo_cogs,
    SUM(wac_cogs) AS wac_cogs,
    MAX(sold_at) AS last_sale_at
  FROM sales_analytics
  GROUP BY product_id
), valuation AS (
  SELECT product_id, current_stock, wac_stock_cost, fifo_stock_cost
  FROM inventory_valuation
)
SELECT
  p.id AS product_id,
  p.name,
  p.category,
  p.minimum_stock,
  COALESCE(sr.units_sold, 0)::numeric AS units_sold,
  COALESCE(sr.revenue, 0)::numeric AS revenue,
  COALESCE(sr.fifo_cogs, 0)::numeric AS fifo_cogs,
  COALESCE(sr.wac_cogs, 0)::numeric AS wac_cogs,
  COALESCE(sr.revenue - sr.fifo_cogs, 0)::numeric AS fifo_gross_profit,
  COALESCE(sr.revenue - sr.wac_cogs, 0)::numeric AS wac_gross_profit,
  CASE WHEN COALESCE(sr.revenue, 0) = 0 THEN 0 ELSE (sr.revenue - sr.fifo_cogs) / sr.revenue END AS fifo_gross_margin,
  CASE WHEN COALESCE(sr.revenue, 0) = 0 THEN 0 ELSE (sr.revenue - sr.wac_cogs) / sr.revenue END AS wac_gross_margin,
  COALESCE(v.current_stock, p.current_stock)::numeric AS current_stock,
  COALESCE(v.fifo_stock_cost, 0)::numeric AS fifo_stock_cost,
  COALESCE(v.wac_stock_cost, 0)::numeric AS wac_stock_cost,
  sr.last_sale_at,
  CASE WHEN COALESCE(v.current_stock, p.current_stock) = 0 THEN NULL ELSE COALESCE(sr.units_sold, 0) / v.current_stock END AS simple_units_per_stock_turn
FROM products p
LEFT JOIN sales_rollup sr ON sr.product_id = p.id
LEFT JOIN valuation v ON v.product_id = p.id;

CREATE OR REPLACE VIEW debtor_analytics AS
SELECT
  d.id AS debtor_id,
  d.name,
  d.phone,
  COUNT(cb.credit_sale_id) AS credit_sales_count,
  COALESCE(SUM(cb.amount_due), 0)::numeric AS total_credit,
  COALESCE(SUM(cb.amount_paid), 0)::numeric AS total_paid,
  COALESCE(SUM(cb.outstanding_balance), 0)::numeric AS outstanding_balance,
  COUNT(*) FILTER (WHERE cb.status = 'SETTLED') AS settled_sales,
  COUNT(*) FILTER (WHERE cb.status <> 'SETTLED') AS open_sales
FROM debtors d
LEFT JOIN credit_balances cb ON cb.debtor_id = d.id
GROUP BY d.id, d.name, d.phone;

CREATE OR REPLACE VIEW store_analytics AS
SELECT
  COALESCE(SUM(pa.units_sold), 0)::numeric AS units_sold,
  COALESCE(SUM(pa.revenue), 0)::numeric AS revenue,
  COALESCE(SUM(pa.fifo_cogs), 0)::numeric AS fifo_cogs,
  COALESCE(SUM(pa.wac_cogs), 0)::numeric AS wac_cogs,
  COALESCE(SUM(pa.fifo_gross_profit), 0)::numeric AS fifo_gross_profit,
  COALESCE(SUM(pa.wac_gross_profit), 0)::numeric AS wac_gross_profit,
  CASE WHEN COALESCE(SUM(pa.revenue), 0) = 0 THEN 0 ELSE SUM(pa.fifo_gross_profit) / SUM(pa.revenue) END AS fifo_gross_margin,
  CASE WHEN COALESCE(SUM(pa.revenue), 0) = 0 THEN 0 ELSE SUM(pa.wac_gross_profit) / SUM(pa.revenue) END AS wac_gross_margin,
  COALESCE(SUM(pa.fifo_stock_cost), 0)::numeric AS fifo_capital_in_stock,
  COALESCE(SUM(pa.wac_stock_cost), 0)::numeric AS wac_capital_in_stock,
  COALESCE((SELECT SUM(outstanding_balance) FROM credit_balances), 0)::numeric AS outstanding_debt
FROM product_analytics pa;
