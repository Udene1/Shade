BEGIN;
TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products, operation_requests, day_closings RESTART IDENTITY CASCADE;
INSERT INTO products (name, selling_price, minimum_stock) VALUES ('Health Product', 100, 1);
INSERT INTO purchases (product_id, quantity, unit_cost, purchased_at) SELECT id, 10, 60, NOW() - INTERVAL '1 day' FROM products;
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, occurred_at, unit_cost)
SELECT p.id, 'PURCHASE', pu.quantity, pu.id, pu.purchased_at, pu.unit_cost FROM products p JOIN purchases pu ON pu.product_id = p.id;
INSERT INTO sales (product_id, quantity, unit_price, unit_cost) SELECT id, 2, 100, 60 FROM products;
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, occurred_at, unit_cost)
SELECT p.id, 'SALE', -s.quantity, s.id, s.sold_at, s.unit_cost FROM products p JOIN sales s ON s.product_id = p.id;
UPDATE products SET current_stock = 8;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM shade_data_health WHERE status = 'ERROR') THEN RAISE EXCEPTION 'healthy fixture produced an integrity error'; END IF;
END $$;
UPDATE products SET current_stock = 7;
DO $$ BEGIN
  IF (SELECT status FROM shade_data_health WHERE check_name='STOCK_LEDGER') <> 'ERROR' THEN RAISE EXCEPTION 'stock mismatch was not detected'; END IF;
END $$;
ROLLBACK;
