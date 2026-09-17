BEGIN;

TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products RESTART IDENTITY CASCADE;

INSERT INTO products (name, selling_price, current_stock) VALUES ('Analytics Test', 300, 0);
INSERT INTO purchases (product_id, quantity, unit_cost, purchased_at)
SELECT id, 10, 100, '2026-03-01T09:00:00Z' FROM products WHERE name = 'Analytics Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'PURCHASE', 10, pu.id, 100, pu.purchased_at FROM products p JOIN purchases pu ON pu.product_id = p.id WHERE p.name = 'Analytics Test';
UPDATE products SET current_stock = 10 WHERE name = 'Analytics Test';

INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, 4, 300, 100, '2026-03-02T09:00:00Z' FROM products WHERE name = 'Analytics Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'SALE', -4, s.id, 100, s.sold_at FROM products p JOIN sales s ON s.product_id = p.id WHERE p.name = 'Analytics Test';
UPDATE products SET current_stock = 6 WHERE name = 'Analytics Test';

DO $$
DECLARE r numeric; c numeric; gp numeric; gm numeric; stock numeric;
BEGIN
  SELECT revenue, wac_cogs, wac_gross_profit, wac_gross_margin, current_stock INTO r, c, gp, gm, stock FROM product_analytics WHERE name = 'Analytics Test';
  IF r <> 1200 THEN RAISE EXCEPTION 'revenue expected 1200, got %', r; END IF;
  IF c <> 400 THEN RAISE EXCEPTION 'WAC COGS expected 400, got %', c; END IF;
  IF gp <> 800 THEN RAISE EXCEPTION 'WAC gross profit expected 800, got %', gp; END IF;
  IF gm <> 2.0/3.0 THEN RAISE EXCEPTION 'WAC margin mismatch, got %', gm; END IF;
  IF stock <> 6 THEN RAISE EXCEPTION 'stock expected 6, got %', stock; END IF;
END $$;

INSERT INTO debtors (name) VALUES ('Analytics Debtor');
INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, 2, 300, 100, '2026-03-03T09:00:00Z' FROM products WHERE name = 'Analytics Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'SALE', -2, s.id, 100, s.sold_at FROM products p JOIN sales s ON s.product_id = p.id WHERE p.name = 'Analytics Test' ORDER BY s.id DESC LIMIT 1;
INSERT INTO credit_sales (sale_id, debtor_id, amount_due)
SELECT s.id, d.id, 600 FROM sales s CROSS JOIN debtors d WHERE s.id = (SELECT MAX(id) FROM sales) AND d.name = 'Analytics Debtor';
UPDATE products SET current_stock = 4 WHERE name = 'Analytics Test';

INSERT INTO credit_payments (credit_sale_id, amount) SELECT id, 200 FROM credit_sales WHERE amount_due = 600;

DO $$
DECLARE outstanding numeric; paid numeric;
BEGIN
  SELECT total_paid, outstanding_balance INTO paid, outstanding FROM debtor_analytics WHERE name = 'Analytics Debtor';
  IF paid <> 200 THEN RAISE EXCEPTION 'debtor paid expected 200, got %', paid; END IF;
  IF outstanding <> 400 THEN RAISE EXCEPTION 'debtor outstanding expected 400, got %', outstanding; END IF;
END $$;

-- A fresh product exercises the rolling windows rather than the historical fixture above.
INSERT INTO products (name, selling_price, current_stock) VALUES ('Velocity Test', 500, 11);
INSERT INTO purchases (product_id, quantity, unit_cost, purchased_at)
SELECT id, 20, 100, CURRENT_TIMESTAMP - INTERVAL '60 days' FROM products WHERE name = 'Velocity Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'PURCHASE', 20, pu.id, 100, pu.purchased_at FROM products p JOIN purchases pu ON pu.product_id = p.id WHERE p.name = 'Velocity Test';

INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, 3, 500, 100, CURRENT_TIMESTAMP - INTERVAL '40 days' FROM products WHERE name = 'Velocity Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'SALE', -3, s.id, 100, s.sold_at FROM products p JOIN sales s ON s.product_id = p.id WHERE p.name = 'Velocity Test' ORDER BY s.id DESC LIMIT 1;

INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, 4, 500, 100, CURRENT_TIMESTAMP - INTERVAL '10 days' FROM products WHERE name = 'Velocity Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'SALE', -4, s.id, 100, s.sold_at FROM products p JOIN sales s ON s.product_id = p.id WHERE p.name = 'Velocity Test' ORDER BY s.id DESC LIMIT 1;

INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, 2, 500, 100, CURRENT_TIMESTAMP FROM products WHERE name = 'Velocity Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'SALE', -2, s.id, 100, s.sold_at FROM products p JOIN sales s ON s.product_id = p.id WHERE p.name = 'Velocity Test' ORDER BY s.id DESC LIMIT 1;

DO $$
DECLARE u30 numeric; u90 numeric; avg30 numeric; turn30 numeric; daily30 numeric; cover30 numeric;
BEGIN
  SELECT units_sold, average_stock_units, inventory_turnover_units, units_per_day, stock_cover_days
  INTO u30, avg30, turn30, daily30, cover30
  FROM product_sales_velocity
  WHERE name = 'Velocity Test' AND window_days = 30;

  IF u30 <> 6 THEN RAISE EXCEPTION '30d units sold expected 6, got %', u30; END IF;
  IF round(avg30, 1) <> 14.3 THEN RAISE EXCEPTION '30d average stock expected 14.3, got %', avg30; END IF;
  IF round(turn30, 4) <> round(6 / 14.3, 4) THEN RAISE EXCEPTION '30d turnover mismatch, got %', turn30; END IF;
  IF round(daily30, 4) <> 0.2 THEN RAISE EXCEPTION '30d units/day expected 0.2, got %', daily30; END IF;
  IF round(cover30, 1) <> 55.0 THEN RAISE EXCEPTION '30d stock cover expected 55.0 days, got %', cover30; END IF;

  SELECT units_sold INTO u90 FROM product_sales_velocity WHERE name = 'Velocity Test' AND window_days = 90;
  IF u90 <> 9 THEN RAISE EXCEPTION '90d units sold expected 9, got %', u90; END IF;
END $$;

ROLLBACK;
