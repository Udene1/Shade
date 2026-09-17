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
  CASE WHEN sold.quantity = 0 THEN NULL ELSE (sold.quantity * sold.unit_price - costs.fifo_cogs) / (sold.quantity * sold.unit_price) END AS fifo_gross_margin,
  CASE WHEN sold.quantity = 0 THEN NULL ELSE (sold.quantity * sold.unit_price - costs.wac_cogs) / (sold.quantity * sold.unit_price) END AS wac_gross_margin,
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
  sr.last_sale_at
FROM products p
LEFT JOIN sales_rollup sr ON sr.product_id = p.id
LEFT JOIN valuation v ON v.product_id = p.id;

/*
 * Operational turnover is deliberately expressed in units here. It answers:
 * "How many times did the typical unit of stock move during this window?"
 * It does not pretend that a quantity ratio is a monetary inventory-turnover
 * ratio; value turnover requires a time-series of valued inventory.
 */
CREATE OR REPLACE VIEW product_sales_velocity AS
WITH windows AS (
  SELECT 30::integer AS window_days
  UNION ALL SELECT 90::integer
), products_windows AS (
  SELECT p.id AS product_id, p.name, p.category, p.minimum_stock, p.current_stock, w.window_days
  FROM products p CROSS JOIN windows w
), sales_window AS (
  SELECT
    s.product_id,
    w.window_days,
    COALESCE(SUM(s.quantity), 0)::numeric AS units_sold,
    COALESCE(SUM(s.quantity * s.unit_price), 0)::numeric AS revenue,
    COALESCE(SUM(a.fifo_cogs), 0)::numeric AS fifo_cogs,
    COALESCE(SUM(a.wac_cogs), 0)::numeric AS wac_cogs,
    MAX(s.sold_at) AS last_sale_at
  FROM sales s
  JOIN windows w ON s.sold_at >= CURRENT_TIMESTAMP - make_interval(days => w.window_days)
  LEFT JOIN sales_analytics a ON a.sale_id = s.id
  GROUP BY s.product_id, w.window_days
), daily_dates AS (
  SELECT generate_series(
    CURRENT_DATE - 89,
    CURRENT_DATE,
    INTERVAL '1 day'
  )::date AS day
), daily_stock AS (
  SELECT
    p.id AS product_id,
    d.day,
    GREATEST(0, p.current_stock - COALESCE(SUM(m.quantity) FILTER (WHERE m.occurred_at::date > d.day), 0))::numeric AS stock_units
  FROM products p
  CROSS JOIN daily_dates d
  LEFT JOIN inventory_movements m
    ON m.product_id = p.id
   AND m.occurred_at::date > d.day
  GROUP BY p.id, d.day, p.current_stock
), average_stock AS (
  SELECT product_id,
    AVG(stock_units) FILTER (WHERE day >= CURRENT_DATE - 29)::numeric AS avg_stock_30d,
    AVG(stock_units)::numeric AS avg_stock_90d
  FROM daily_stock
  GROUP BY product_id
)
SELECT
  pw.product_id,
  pw.name,
  pw.category,
  pw.minimum_stock,
  pw.current_stock,
  pw.window_days,
  COALESCE(sw.units_sold, 0)::numeric AS units_sold,
  COALESCE(sw.revenue, 0)::numeric AS revenue,
  COALESCE(sw.fifo_cogs, 0)::numeric AS fifo_cogs,
  COALESCE(sw.wac_cogs, 0)::numeric AS wac_cogs,
  COALESCE(sw.revenue - sw.fifo_cogs, 0)::numeric AS fifo_gross_profit,
  COALESCE(sw.revenue - sw.wac_cogs, 0)::numeric AS wac_gross_profit,
  CASE WHEN COALESCE(sw.revenue, 0) = 0 THEN 0 ELSE (sw.revenue - sw.fifo_cogs) / sw.revenue END AS fifo_gross_margin,
  CASE WHEN COALESCE(sw.revenue, 0) = 0 THEN 0 ELSE (sw.revenue - sw.wac_cogs) / sw.revenue END AS wac_gross_margin,
  CASE WHEN pw.window_days = 30 THEN av.avg_stock_30d ELSE av.avg_stock_90d END AS average_stock_units,
  CASE WHEN COALESCE(CASE WHEN pw.window_days = 30 THEN av.avg_stock_30d ELSE av.avg_stock_90d END, 0) = 0
    THEN NULL
    ELSE COALESCE(sw.units_sold, 0) / CASE WHEN pw.window_days = 30 THEN av.avg_stock_30d ELSE av.avg_stock_90d END
  END AS inventory_turnover_units,
  CASE WHEN pw.window_days = 0 THEN 0 ELSE COALESCE(sw.units_sold, 0) / pw.window_days END AS units_per_day,
  CASE WHEN COALESCE(sw.units_sold, 0) = 0 THEN NULL ELSE pw.current_stock / (sw.units_sold / pw.window_days) END AS stock_cover_days,
  sw.last_sale_at
FROM products_windows pw
LEFT JOIN sales_window sw ON sw.product_id = pw.product_id AND sw.window_days = pw.window_days
LEFT JOIN average_stock av ON av.product_id = pw.product_id;

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
