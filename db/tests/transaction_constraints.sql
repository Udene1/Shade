BEGIN;

TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products RESTART IDENTITY CASCADE;

INSERT INTO products (name, selling_price) VALUES ('Constraint Product', 100) RETURNING id \gset product_
INSERT INTO purchases (product_id, quantity, unit_cost) VALUES (:product_id, 10, 40) RETURNING id \gset purchase_
UPDATE products SET current_stock = 10 WHERE id = :product_id;
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
VALUES (:product_id, 'PURCHASE', 10, :purchase_id);

-- The deferred trigger allows the stock update and movement insert to form one atomic business transaction.
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

-- A mismatched sale reference must fail at transaction validation time.
INSERT INTO sales (product_id, quantity, unit_price, unit_cost) VALUES (:product_id, 2, 100, 40) RETURNING id \gset sale_
INSERT INTO products (name, selling_price) VALUES ('Other Product', 100) RETURNING id \gset other_product_
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
VALUES (:other_product_id, 'SALE', -2, :sale_id);
DO $$
BEGIN
  BEGIN
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'invalid sale reference was accepted';
  EXCEPTION WHEN OTHERS THEN
    -- Any deferred constraint failure here proves the invalid business state cannot commit.
    NULL;
  END;
  SET CONSTRAINTS ALL DEFERRED;
END $$;

ROLLBACK;
