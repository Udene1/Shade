BEGIN;

TRUNCATE credit_payments, credit_sales, sales, inventory_movements, purchases, debtors, products RESTART IDENTITY CASCADE;

INSERT INTO products (name, category, selling_price, current_stock, minimum_stock)
VALUES
  ('Pressure Product', 'Test', 100, 3, 3),
  ('Idle Product', 'Test', 100, 10, 1),
  ('Slow Product', 'Test', 20, 20, 1);

INSERT INTO purchases (product_id, quantity, unit_cost, supplier, purchased_at)
SELECT id, CASE name WHEN 'Pressure Product' THEN 10 ELSE 20 END, 50, 'Signal Supplier', NOW() - INTERVAL '60 days'
FROM products;

INSERT INTO inventory_movements (product_id, type, quantity, reference_id, occurred_at, unit_cost)
SELECT p.id, 'PURCHASE', pu.quantity, pu.id, pu.purchased_at, pu.unit_cost
FROM products p JOIN purchases pu ON pu.product_id = p.id;

INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, CASE name WHEN 'Pressure Product' THEN 7 ELSE 0 END, selling_price, 50, NOW() - INTERVAL '5 days'
FROM products WHERE name IN ('Pressure Product', 'Idle Product');

INSERT INTO inventory_movements (product_id, type, quantity, reference_id, occurred_at, unit_cost)
SELECT p.id, 'SALE', -7, s.id, s.sold_at, 50
FROM sales s JOIN products p ON p.id = s.product_id
WHERE p.name = 'Pressure Product';

UPDATE products SET current_stock = CASE name WHEN 'Pressure Product' THEN 3 ELSE 20 END;

DO $$
DECLARE
  pressure_signal text;
  pressure_demand text;
  pressure_fifo_capital text;
  pressure_wac_capital text;
  idle_signal text;
  idle_demand text;
  slow_signal text;
  slow_demand text;
  pressure_margin numeric;
BEGIN
  SELECT decision_signal, demand_state, fifo_capital_state, wac_capital_state, wac_gross_margin_30d
    INTO pressure_signal, pressure_demand, pressure_fifo_capital, pressure_wac_capital, pressure_margin
  FROM inventory_decision_signals WHERE name = 'Pressure Product';
  SELECT decision_signal, demand_state INTO idle_signal, idle_demand
  FROM inventory_decision_signals WHERE name = 'Idle Product';
  SELECT decision_signal, demand_state INTO slow_signal, slow_demand
  FROM inventory_decision_signals WHERE name = 'Slow Product';

  IF pressure_signal <> 'REPLENISHMENT_PRESSURE' THEN
    RAISE EXCEPTION 'expected replenishment pressure, got %', pressure_signal;
  END IF;
  IF pressure_demand <> 'FAST_RELATIVE_TO_STOCK' THEN
    RAISE EXCEPTION 'expected fast relative to stock demand, got %', pressure_demand;
  END IF;
  IF pressure_fifo_capital <> 'HIGH_30D_PRODUCTIVITY' OR pressure_wac_capital <> 'HIGH_30D_PRODUCTIVITY' THEN
    RAISE EXCEPTION 'expected both valuation capital states to be high, got FIFO %, WAC %', pressure_fifo_capital, pressure_wac_capital;
  END IF;
  IF pressure_margin IS NULL OR pressure_margin <= 0 THEN
    RAISE EXCEPTION 'expected positive WAC gross margin, got %', pressure_margin;
  END IF;
  IF idle_signal <> 'CAPITAL_TIED_LOW_RECENT_DEMAND' THEN
    RAISE EXCEPTION 'expected low recent demand, got %', idle_signal;
  END IF;
  IF idle_demand <> 'NO_30D_SALES' THEN
    RAISE EXCEPTION 'expected no 30d sales, got %', idle_demand;
  END IF;
  IF slow_signal <> 'CAPITAL_TIED_NO_DEMAND' THEN
    RAISE EXCEPTION 'expected no demand, got %', slow_signal;
  END IF;
  IF slow_demand <> 'NO_90D_SALES' THEN
    RAISE EXCEPTION 'expected no 90d sales, got %', slow_demand;
  END IF;
END $$;

ROLLBACK;
