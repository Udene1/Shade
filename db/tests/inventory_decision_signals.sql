TRUNCATE credit_payments, credit_sales, credit_sales, sales, inventory_movements, purchases, debtors, products RESTART IDENTITY CASCADE;

INSERT INTO products (name, category, selling_price, current_stock, minimum_stock)
VALUES
  ('Pressure Product', 'Test', 100, 3, 3),
  ('Idle Product', 'Test', 100, 10, 1),
  ('Slow Product', 'Test', 100, 20, 1);

INSERT INTO purchases (product_id, quantity, unit_cost, supplier, purchased_at)
SELECT id, CASE name WHEN 'Pressure Product' THEN 10 ELSE 20 END, 50, 'Signal Supplier', NOW() - INTERVAL '60 days'
FROM products;

INSERT INTO inventory_movements (product_id, type, quantity, reference_id, occurred_at, unit_cost)
SELECT id, 'PURCHASE', CASE name WHEN 'Pressure Product' THEN 10 ELSE 20 END, NULL, NOW() - INTERVAL '60 days', 50
FROM products;

INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, CASE name WHEN 'Pressure Product' THEN 7 ELSE 0 END, 100, 50, NOW() - INTERVAL '5 days'
FROM products WHERE name IN ('Pressure Product', 'Idle Product');

INSERT INTO inventory_movements (product_id, type, quantity, reference_id, occurred_at, unit_cost)
SELECT p.id, 'SALE', -7, s.id, s.sold_at, 50
FROM sales s JOIN products p ON p.id = s.product_id
WHERE p.name = 'Pressure Product';

UPDATE products SET current_stock = CASE name WHEN 'Pressure Product' THEN 3 ELSE 20 END;

DO $$
DECLARE
  pressure_signal text;
  idle_signal text;
  slow_signal text;
BEGIN
  SELECT decision_signal INTO pressure_signal FROM inventory_decision_signals WHERE name = 'Pressure Product';
  SELECT decision_signal INTO idle_signal FROM inventory_decision_signals WHERE name = 'Idle Product';
  SELECT decision_signal INTO slow_signal FROM inventory_decision_signals WHERE name = 'Slow Product';

  IF pressure_signal <> 'REPLENISHMENT_PRESSURE' THEN
    RAISE EXCEPTION 'expected replenishment pressure, got %', pressure_signal;
  END IF;
  IF idle_signal <> 'CAPITAL_TIED_LOW_RECENT_DEMAND' THEN
    RAISE EXCEPTION 'expected low recent demand, got %', idle_signal;
  END IF;
  IF slow_signal <> 'CAPITAL_TIED_NO_DEMAND' THEN
    RAISE EXCEPTION 'expected no demand, got %', slow_signal;
  END IF;
END $$;
