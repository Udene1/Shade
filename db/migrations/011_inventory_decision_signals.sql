CREATE OR REPLACE VIEW inventory_decision_signals AS
SELECT
  a.product_id,
  a.name,
  a.category,
  a.current_stock,
  a.minimum_stock,
  a.units_sold_30d,
  a.units_sold_90d,
  v.units_per_day,
  v.stock_cover_days,
  v.inventory_turnover_units,
  v.revenue AS revenue_30d,
  v.fifo_gross_profit AS fifo_gross_profit_30d,
  v.wac_gross_profit AS wac_gross_profit_30d,
  CASE WHEN v.revenue = 0 THEN NULL ELSE v.fifo_gross_profit / v.revenue END AS fifo_gross_margin_30d,
  CASE WHEN v.revenue = 0 THEN NULL ELSE v.wac_gross_profit / v.revenue END AS wac_gross_margin_30d,
  cp.fifo_capital_in_stock,
  cp.wac_capital_in_stock,
  cp.fifo_gross_profit_per_current_stock_cost_30d,
  cp.wac_gross_profit_per_current_stock_cost_30d,
  cp.fifo_gross_profit_per_current_stock_cost_90d,
  cp.wac_gross_profit_per_current_stock_cost_90d,
  a.attention_status,
  CASE
    WHEN a.current_stock <= a.minimum_stock AND a.units_sold_30d > 0 THEN 'REPLENISHMENT_PRESSURE'
    WHEN v.stock_cover_days IS NOT NULL AND v.stock_cover_days <= 14 AND a.units_sold_30d > 0 THEN 'REPLENISHMENT_PRESSURE'
    WHEN a.current_stock > 0 AND a.units_sold_90d = 0 THEN 'CAPITAL_TIED_NO_DEMAND'
    WHEN a.current_stock > 0 AND a.units_sold_30d = 0 THEN 'CAPITAL_TIED_LOW_RECENT_DEMAND'
    WHEN v.stock_cover_days IS NOT NULL AND v.stock_cover_days > 90 THEN 'SLOW_CAPITAL'
    ELSE 'MEASURED_NORMAL'
  END AS decision_signal,
  CASE
    WHEN a.units_sold_90d = 0 THEN 'NO_90D_SALES'
    WHEN a.units_sold_30d = 0 THEN 'NO_30D_SALES'
    WHEN v.stock_cover_days IS NOT NULL AND v.stock_cover_days <= 14 THEN 'FAST_RELATIVE_TO_STOCK'
    ELSE 'RECENT_DEMAND'
  END AS demand_state,
  CASE
    WHEN a.current_stock = 0 THEN 'NO_CURRENT_CAPITAL'
    WHEN cp.fifo_gross_profit_per_current_stock_cost_30d IS NULL THEN 'UNMEASURED'
    WHEN cp.fifo_gross_profit_per_current_stock_cost_30d = 0 THEN 'NO_30D_GROSS_PROFIT'
    WHEN cp.fifo_gross_profit_per_current_stock_cost_30d > 1 THEN 'HIGH_30D_PRODUCTIVITY'
    ELSE 'MEASURED_30D_PRODUCTIVITY'
  END AS fifo_capital_state,
  CASE
    WHEN a.current_stock = 0 THEN 'NO_CURRENT_CAPITAL'
    WHEN cp.wac_gross_profit_per_current_stock_cost_30d IS NULL THEN 'UNMEASURED'
    WHEN cp.wac_gross_profit_per_current_stock_cost_30d = 0 THEN 'NO_30D_GROSS_PROFIT'
    WHEN cp.wac_gross_profit_per_current_stock_cost_30d > 1 THEN 'HIGH_30D_PRODUCTIVITY'
    ELSE 'MEASURED_30D_PRODUCTIVITY'
  END AS wac_capital_state,
  CASE
    WHEN a.current_stock <= a.minimum_stock AND a.units_sold_30d > 0 THEN 'Stock is at or below the configured minimum while the product has sold in the last 30 days.'
    WHEN v.stock_cover_days IS NOT NULL AND v.stock_cover_days <= 14 AND a.units_sold_30d > 0 THEN 'At the observed 30-day sales velocity, current stock covers 14 days or less.'
    WHEN a.current_stock > 0 AND a.units_sold_90d = 0 THEN 'Current stock has recorded no sales in the last 90 days.'
    WHEN a.current_stock > 0 AND a.units_sold_30d = 0 THEN 'Current stock has recorded no sales in the last 30 days.'
    WHEN v.stock_cover_days IS NOT NULL AND v.stock_cover_days > 90 THEN 'At the observed 30-day sales velocity, current stock covers more than 90 days.'
    ELSE 'Observed sales, stock and capital measures do not trigger a specific inventory signal.'
  END AS evidence
FROM inventory_attention a
JOIN product_sales_velocity v
  ON v.product_id = a.product_id
 AND v.window_days = 30
JOIN product_capital_productivity cp
  ON cp.product_id = a.product_id;

CREATE INDEX IF NOT EXISTS idx_inventory_movements_product_occurred_id
  ON inventory_movements(product_id, occurred_at, id);
