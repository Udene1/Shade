BEGIN;

TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products, operation_requests, day_closings RESTART IDENTITY CASCADE;

INSERT INTO products (name, selling_price, minimum_stock) VALUES ('Kiosk Test', 100, 2);

-- Real ledger operations: purchase then sale.
INSERT INTO purchases (product_id, quantity, unit_cost) SELECT id, 10, 60 FROM products WHERE name = 'Kiosk Test';
UPDATE products SET current_stock = 10 WHERE name = 'Kiosk Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id) SELECT id, 'PURCHASE', 10, (SELECT id FROM purchases ORDER BY id DESC LIMIT 1) FROM products WHERE name = 'Kiosk Test';

INSERT INTO operation_requests (id, operation_type, completed_at, result) VALUES ('00000000-0000-0000-0000-000000000001','SALE',NOW(),'{"ok":true,"message":"Sale recorded"}');
INSERT INTO sales (product_id, quantity, unit_price, unit_cost) SELECT id, 2, 100, 60 FROM products WHERE name = 'Kiosk Test';
UPDATE products SET current_stock = current_stock - 2 WHERE name = 'Kiosk Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id) SELECT id, 'SALE', -2, (SELECT id FROM sales ORDER BY id DESC LIMIT 1) FROM products WHERE name = 'Kiosk Test';

DO $$ BEGIN
  IF (SELECT current_stock FROM products WHERE name='Kiosk Test') <> 8 THEN RAISE EXCEPTION 'ledger stock mismatch'; END IF;
  IF (SELECT COUNT(*) FROM transaction_history WHERE product_name='Kiosk Test') <> 2 THEN RAISE EXCEPTION 'transaction history mismatch'; END IF;
  IF (SELECT result->>'ok' FROM operation_requests WHERE id='00000000-0000-0000-0000-000000000001') <> 'true' THEN RAISE EXCEPTION 'operation result missing'; END IF;
END $$;

INSERT INTO day_closings (business_date, cash_sales, credit_sales, sales_revenue, units_sold, wac_gross_profit, fifo_gross_profit, stock_discrepancy_units, outstanding_debt)
VALUES (CURRENT_DATE, 200, 0, 200, 2, 80, 80, 0, 0);

DO $$ BEGIN
  IF (SELECT COUNT(*) FROM day_closings WHERE business_date=CURRENT_DATE) <> 1 THEN RAISE EXCEPTION 'day closing missing'; END IF;
END $$;

ROLLBACK;
