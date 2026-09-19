BEGIN;
TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products, operation_requests, day_closings RESTART IDENTITY CASCADE;

INSERT INTO products (name, selling_price, minimum_stock) VALUES ('Kiosk Test', 100, 2);

SELECT record_purchase_operation(
  '00000000-0000-0000-0000-000000000101',
  (SELECT id FROM products WHERE name='Kiosk Test'),
  10, 60, 'Test Supplier',
  '10000000-0000-0000-0000-000000000101'
);

DO $$ BEGIN
  IF (SELECT current_stock FROM products WHERE name='Kiosk Test') <> 10 THEN RAISE EXCEPTION 'purchase operation did not update stock'; END IF;
  IF (SELECT COUNT(*) FROM purchases) <> 1 THEN RAISE EXCEPTION 'purchase operation did not create purchase'; END IF;
  IF (SELECT COUNT(*) FROM inventory_movements WHERE type='PURCHASE') <> 1 THEN RAISE EXCEPTION 'purchase operation did not create movement'; END IF;
END $$;

SELECT record_sale_operation(
  '00000000-0000-0000-0000-000000000102',
  (SELECT id FROM products WHERE name='Kiosk Test'),
  2,
  '10000000-0000-0000-0000-000000000102'
);

DO $$ BEGIN
  IF (SELECT current_stock FROM products WHERE name='Kiosk Test') <> 8 THEN RAISE EXCEPTION 'cash sale operation did not reduce stock'; END IF;
  IF (SELECT COUNT(*) FROM sales) <> 1 THEN RAISE EXCEPTION 'cash sale operation did not create sale'; END IF;
END $$;

SELECT record_credit_sale_operation(
  '00000000-0000-0000-0000-000000000103',
  (SELECT id FROM products WHERE name='Kiosk Test'),
  1,
  'Credit Customer',
  '08000000000',
  'test credit',
  '10000000-0000-0000-0000-000000000103'
);

DO $$ BEGIN
  IF (SELECT current_stock FROM products WHERE name='Kiosk Test') <> 7 THEN RAISE EXCEPTION 'credit sale operation did not reduce stock'; END IF;
  IF (SELECT COUNT(*) FROM credit_sales) <> 1 THEN RAISE EXCEPTION 'credit sale operation did not create credit sale'; END IF;
  IF (SELECT SUM(amount_due) FROM credit_sales) <> 100 THEN RAISE EXCEPTION 'credit amount mismatch'; END IF;
END $$;

INSERT INTO operation_requests(id, operation_type, created_at, claim_token, lease_expires_at)
VALUES (
  '00000000-0000-0000-0000-000000000104',
  'PURCHASE',
  NOW() - INTERVAL '30 minutes',
  '10000000-0000-0000-0000-000000000104',
  NOW() - INTERVAL '1 minute'
);

SELECT record_purchase_operation(
  '00000000-0000-0000-0000-000000000104',
  (SELECT id FROM products WHERE name='Kiosk Test'),
  3, 70, 'Recovered Supplier',
  '20000000-0000-0000-0000-000000000104'
);

DO $$ BEGIN
  IF (SELECT current_stock FROM products WHERE name='Kiosk Test') <> 10 THEN RAISE EXCEPTION 'stale operation was not reclaimed'; END IF;
  IF (SELECT result->>'ok' FROM operation_requests WHERE id='00000000-0000-0000-0000-000000000104') <> 'true' THEN RAISE EXCEPTION 'reclaimed operation was not completed'; END IF;
END $$;

INSERT INTO operation_requests(id, operation_type, created_at, claim_token, lease_expires_at)
VALUES (
  '00000000-0000-0000-0000-000000000105',
  'SALE',
  NOW(),
  '10000000-0000-0000-0000-000000000105',
  NOW() + INTERVAL '10 minutes'
);

SELECT record_sale_operation(
  '00000000-0000-0000-0000-000000000105',
  (SELECT id FROM products WHERE name='Kiosk Test'),
  1,
  '30000000-0000-0000-0000-000000000105'
);

DO $$ BEGIN
  IF (SELECT current_stock FROM products WHERE name='Kiosk Test') <> 10 THEN RAISE EXCEPTION 'active operation was incorrectly reclaimed'; END IF;
  IF (SELECT result IS NULL FROM operation_requests WHERE id='00000000-0000-0000-0000-000000000105') IS NOT TRUE THEN RAISE EXCEPTION 'active operation was unexpectedly completed'; END IF;
END $$;

DO $$ BEGIN
  IF (SELECT COUNT(*) FROM transaction_history WHERE product_name='Kiosk Test') <> 4 THEN RAISE EXCEPTION 'transaction history mismatch'; END IF;
  IF (SELECT COUNT(*) FROM transaction_history WHERE transaction_type='CREDIT_SALE') <> 1 THEN RAISE EXCEPTION 'credit sale missing from history'; END IF;
  IF (SELECT COUNT(*) FROM inventory_sale_costs) <> 2 THEN RAISE EXCEPTION 'sale valuation records missing'; END IF;
  IF EXISTS (SELECT 1 FROM shade_data_health WHERE status='ERROR') THEN RAISE EXCEPTION 'healthy kiosk flow has integrity errors'; END IF;
END $$;

UPDATE inventory_valuation_settings SET method='FIFO' WHERE id=1;
DO $$ BEGIN
  IF (SELECT COUNT(*) FROM transaction_history) <> 4 THEN RAISE EXCEPTION 'valuation switch changed history'; END IF;
END $$;
UPDATE inventory_valuation_settings SET method='WAC' WHERE id=1;

DO $$ BEGIN
  BEGIN
    INSERT INTO operation_requests(id, operation_type)
    VALUES ('00000000-0000-0000-0000-000000000106','CREDIT_PAYMENT');
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
