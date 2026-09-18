BEGIN;
TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products, operation_requests, day_closings RESTART IDENTITY CASCADE;
INSERT INTO products (name, selling_price, minimum_stock) VALUES ('Kiosk Test', 100, 2);
INSERT INTO purchases (product_id, quantity, unit_cost) SELECT id, 10, 60 FROM products WHERE name = 'Kiosk Test';
UPDATE products SET current_stock = 10 WHERE name = 'Kiosk Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, occurred_at, unit_cost)
SELECT p.id, 'PURCHASE', pu.quantity, pu.id, pu.purchased_at, pu.unit_cost FROM products p JOIN purchases pu ON pu.product_id = p.id;
INSERT INTO operation_requests (id, operation_type, completed_at, result) VALUES ('00000000-0000-0000-0000-000000000001','SALE',NOW(),'{"ok":true,"message":"Sale recorded"}');
INSERT INTO sales (product_id, quantity, unit_price, unit_cost) SELECT id, 2, 100, 60 FROM products WHERE name = 'Kiosk Test';
UPDATE products SET current_stock = current_stock - 2 WHERE name = 'Kiosk Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, occurred_at, unit_cost)
SELECT p.id, 'SALE', -s.quantity, s.id, s.sold_at, s.unit_cost FROM products p JOIN sales s ON s.product_id = p.id ORDER BY s.id DESC LIMIT 1;
INSERT INTO debtors (name, phone) VALUES ('Credit Customer', '08000000000');
INSERT INTO operation_requests (id, operation_type, completed_at, result) VALUES ('00000000-0000-0000-0000-000000000003','CREDIT_SALE',NOW(),'{"ok":true,"message":"Credit sale recorded"}');
INSERT INTO sales (product_id, quantity, unit_price, unit_cost) SELECT id, 1, 100, 60 FROM products WHERE name = 'Kiosk Test';
INSERT INTO credit_sales (sale_id, debtor_id, amount_due) SELECT s.id, d.id, s.quantity * s.unit_price FROM sales s CROSS JOIN debtors d ORDER BY s.id DESC LIMIT 1;
UPDATE products SET current_stock = current_stock - 1 WHERE name = 'Kiosk Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, occurred_at, unit_cost)
SELECT p.id, 'SALE', -s.quantity, s.id, s.sold_at, s.unit_cost FROM products p JOIN sales s ON s.product_id = p.id ORDER BY s.id DESC LIMIT 1;
DO $$ BEGIN
  IF (SELECT current_stock FROM products WHERE name='Kiosk Test') <> 7 THEN RAISE EXCEPTION 'stock mismatch'; END IF;
  IF (SELECT COUNT(*) FROM transaction_history WHERE product_name='Kiosk Test') <> 3 THEN RAISE EXCEPTION 'transaction history mismatch'; END IF;
  IF (SELECT COUNT(*) FROM transaction_history WHERE transaction_type='CREDIT_SALE') <> 1 THEN RAISE EXCEPTION 'credit sale missing from history'; END IF;
  IF (SELECT SUM(amount_due) FROM credit_sales) <> 100 THEN RAISE EXCEPTION 'credit balance mismatch'; END IF;
  IF (SELECT COUNT(*) FROM inventory_sale_costs) <> 2 THEN RAISE EXCEPTION 'sale valuation records missing'; END IF;
  IF EXISTS (SELECT 1 FROM shade_data_health WHERE status='ERROR') THEN RAISE EXCEPTION 'healthy kiosk flow has integrity errors'; END IF;
END $$;
UPDATE inventory_valuation_settings SET method='FIFO' WHERE id=1;
DO $$ BEGIN
  IF (SELECT COUNT(*) FROM transaction_history) <> 3 THEN RAISE EXCEPTION 'valuation switch changed history'; END IF;
END $$;
UPDATE inventory_valuation_settings SET method='WAC' WHERE id=1;
DO $$ BEGIN
  BEGIN
    INSERT INTO operation_requests (id, operation_type) VALUES ('00000000-0000-0000-0000-000000000002','CREDIT_PAYMENT');
    RAISE EXCEPTION 'payment operation unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
INSERT INTO day_closings (business_date, cash_sales, credit_sales, credit_payments, sales_revenue, units_sold, wac_gross_profit, fifo_gross_profit, stock_discrepancy_units, outstanding_debt)
VALUES (CURRENT_DATE, 200, 100, 0, 300, 3, 120, 120, 0, 100);
DO $$ BEGIN
  IF (SELECT sales_revenue FROM day_closings WHERE business_date=CURRENT_DATE) <> 300 THEN RAISE EXCEPTION 'day revenue mismatch'; END IF;
END $$;
ROLLBACK;
