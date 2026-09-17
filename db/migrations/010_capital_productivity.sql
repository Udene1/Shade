CREATE OR REPLACE VIEW product_capital_productivity AS
WITH velocity AS (
  SELECT
    product_id,
    MAX(units_sold) FILTER (WHERE window_days = 30) AS units_sold_30d,
    MAX(revenue) FILTER (WHERE window_days = 30) AS revenue_30d,
    MAX(fifo_cogs) FILTER (WHERE window_days = 30) AS fifo_cogs_30d,
    MAX(wac_cogs) FILTER (WHERE window_days = 30) AS wac_cogs_30d,
    MAX(fifo_gross_profit) FILTER (WHERE window_days = 30) AS fifo_gross_profit_30d,
    MAX(wac_gross_profit) FILTER (WHERE window_days = 30) AS wac_gross_profit_30d,
    MAX(units_sold) FILTER (WHERE window_days = 90) AS units_sold_90d,
    MAX(revenue) FILTER (WHERE window_days = 90) AS revenue_90d,
    MAX(fifo_cogs) FILTER (WHERE window_days = 90) AS fifo_cogs_90d,
    MAX(wac_cogs) FILTER (WHERE window_days = 90) AS wac_cogs_90d,
    MAX(fifo_gross_profit) FILTER (WHERE window_days = 90) AS fifo_gross_profit_90d,
    MAX(wac_gross_profit) FILTER (WHERE window_days = 90) AS wac_gross_profit_90d
  FROM product_sales_velocity
  GROUP BY product_id
), valuation AS (
  SELECT product_id, fifo_stock_cost, wac_stock_cost
  FROM inventory_valuation
)
SELECT
  p.id AS product_id,
  p.name,
  p.category,
  p.current_stock,
  COALESCE(v.fifo_stock_cost, 0)::numeric AS fifo_capital_in_stock,
  COALESCE(v.wac_stock_cost, 0)::numeric AS wac_capital_in_stock,
  COALESCE(s.units_sold_30d, 0)::numeric AS units_sold_30d,
  COALESCE(s.revenue_30d, 0)::numeric AS revenue_30d,
  COALESCE(s.fifo_gross_profit_30d, 0)::numeric AS fifo_gross_profit_30d,
  COALESCE(s.wac_gross_profit_30d, 0)::numeric AS wac_gross_profit_30d,
  COALESCE(s.units_sold_90d, 0)::numeric AS units_sold_90d,
  COALESCE(s.revenue_90d, 0)::numeric AS revenue_90d,
  COALESCE(s.fifo_gross_profit_90d, 0)::numeric AS fifo_gross_profit_90d,
  COALESCE(s.wac_gross_profit_90d, 0)::numeric AS wac_gross_profit_90d,
  CASE WHEN COALESCE(v.fifo_stock_cost, 0) = 0 THEN NULL
    ELSE COALESCE(s.fifo_gross_profit_30d, 0) / v.fifo_stock_cost END AS fifo_gross_profit_per_current_stock_cost_30d,
  CASE WHEN COALESCE(v.wac_stock_cost, 0) = 0 THEN NULL
    ELSE COALESCE(s.wac_gross_profit_30d, 0) / v.wac_stock_cost END AS wac_gross_profit_per_current_stock_cost_30d,
  CASE WHEN COALESCE(v.fifo_stock_cost, 0) = 0 THEN NULL
    ELSE COALESCE(s.fifo_gross_profit_90d, 0) / v.fifo_stock_cost END AS fifo_gross_profit_per_current_stock_cost_90d,
  CASE WHEN COALESCE(v.wac_stock_cost, 0) = 0 THEN NULL
    ELSE COALESCE(s.wac_gross_profit_90d, 0) / v.wac_stock_cost END AS wac_gross_profit_per_current_stock_cost_90d
FROM products p
LEFT JOIN velocity s ON s.product_id = p.id
LEFT JOIN valuation v ON v.product_id = p.id;

CREATE OR REPLACE VIEW store_capital_productivity AS
SELECT
  COALESCE(SUM(fifo_gross_profit_30d), 0)::numeric AS fifo_gross_profit_30d,
  COALESCE(SUM(wac_gross_profit_30d), 0)::numeric AS wac_gross_profit_30d,
  COALESCE(SUM(fifo_gross_profit_90d), 0)::numeric AS fifo_gross_profit_90d,
  COALESCE(SUM(wac_gross_profit_90d), 0)::numeric AS wac_gross_profit_90d,
  COALESCE(SUM(fifo_capital_in_stock), 0)::numeric AS fifo_capital_in_stock,
  COALESCE(SUM(wac_capital_in_stock), 0)::numeric AS wac_capital_in_stock,
  CASE WHEN COALESCE(SUM(fifo_capital_in_stock), 0) = 0 THEN NULL
    ELSE SUM(fifo_gross_profit_30d) / SUM(fifo_capital_in_stock) END AS fifo_gross_profit_per_current_stock_cost_30d,
  CASE WHEN COALESCE(SUM(wac_capital_in_stock), 0) = 0 THEN NULL
    ELSE SUM(wac_gross_profit_30d) / SUM(wac_capital_in_stock) END AS wac_gross_profit_per_current_stock_cost_30d,
  CASE WHEN COALESCE(SUM(fifo_capital_in_stock), 0) = 0 THEN NULL
    ELSE SUM(fifo_gross_profit_90d) / SUM(fifo_capital_in_stock) END AS fifo_gross_profit_per_current_stock_cost_90d,
  CASE WHEN COALESCE(SUM(wac_capital_in_stock), 0) = 0 THEN NULL
    ELSE SUM(wac_gross_profit_90d) / SUM(wac_capital_in_stock) END AS wac_gross_profit_per_current_stock_cost_90d
FROM product_capital_productivity;
