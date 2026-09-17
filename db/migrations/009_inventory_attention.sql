CREATE OR REPLACE VIEW inventory_attention AS
WITH velocity AS (
  SELECT *
  FROM product_sales_velocity
  WHERE window_days = 30
), velocity90 AS (
  SELECT product_id, units_sold AS units_sold_90d, revenue AS revenue_90d, last_sale_at AS last_sale_at_90d
  FROM product_sales_velocity
  WHERE window_days = 90
), valuation AS (
  SELECT product_id, fifo_stock_cost, wac_stock_cost
  FROM inventory_valuation
)
SELECT
  p.id AS product_id,
  p.name,
  p.category,
  p.current_stock,
  p.minimum_stock,
  COALESCE(v.units_sold, 0)::numeric AS units_sold_30d,
  COALESCE(v90.units_sold_90d, 0)::numeric AS units_sold_90d,
  COALESCE(v.revenue, 0)::numeric AS revenue_30d,
  COALESCE(v90.revenue_90d, 0)::numeric AS revenue_90d,
  v.units_per_day,
  v.stock_cover_days,
  v.average_stock_units,
  COALESCE(val.fifo_stock_cost, 0)::numeric AS fifo_stock_cost,
  COALESCE(val.wac_stock_cost, 0)::numeric AS wac_stock_cost,
  v.last_sale_at,
  v90.last_sale_at_90d,
  CASE
    WHEN p.current_stock <= p.minimum_stock THEN 'LOW_STOCK'
    WHEN p.current_stock > 0 AND COALESCE(v.units_sold, 0) = 0 THEN 'NO_SALES_30D'
    WHEN p.current_stock > 0 AND COALESCE(v90.units_sold_90d, 0) = 0 THEN 'DEAD_STOCK_90D'
    WHEN v.stock_cover_days IS NOT NULL AND v.stock_cover_days > 90 THEN 'SLOW_STOCK'
    ELSE 'NORMAL'
  END AS attention_status
FROM products p
LEFT JOIN velocity v ON v.product_id = p.id
LEFT JOIN velocity90 v90 ON v90.product_id = p.id
LEFT JOIN valuation val ON val.product_id = p.id;

CREATE OR REPLACE VIEW debtor_concentration AS
WITH totals AS (
  SELECT COALESCE(SUM(outstanding_balance), 0)::numeric AS total_outstanding
  FROM credit_balances
), grouped AS (
  SELECT
    d.id AS debtor_id,
    d.name,
    COALESCE(SUM(cb.outstanding_balance), 0)::numeric AS outstanding_balance,
    COUNT(cb.credit_sale_id) FILTER (WHERE cb.outstanding_balance > 0) AS open_credit_sales
  FROM debtors d
  LEFT JOIN credit_balances cb ON cb.debtor_id = d.id
  GROUP BY d.id, d.name
)
SELECT
  g.debtor_id,
  g.name,
  g.outstanding_balance,
  g.open_credit_sales,
  CASE WHEN t.total_outstanding = 0 THEN 0 ELSE g.outstanding_balance / t.total_outstanding END AS outstanding_share
FROM grouped g
CROSS JOIN totals t
WHERE g.outstanding_balance > 0
ORDER BY g.outstanding_balance DESC, g.debtor_id;

CREATE OR REPLACE VIEW store_debt_concentration AS
SELECT
  COALESCE(SUM(outstanding_balance), 0)::numeric AS outstanding_debt,
  COUNT(*) AS debtors_with_balance,
  COALESCE(MAX(outstanding_share), 0)::numeric AS largest_debtor_share,
  COALESCE(SUM(outstanding_balance) FILTER (WHERE outstanding_share >= 0.25), 0)::numeric AS debt_held_by_25pct_plus_debtors
FROM debtor_concentration;
