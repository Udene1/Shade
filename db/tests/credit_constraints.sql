BEGIN;

TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products RESTART IDENTITY CASCADE;

INSERT INTO products (name, selling_price) VALUES ('Credit Constraint Product', 100) RETURNING id \gset product_
INSERT INTO sales (product_id, quantity, unit_price, unit_cost) VALUES (:product_id, 2, 100, 40) RETURNING id \gset sale_
INSERT INTO debtors (name) VALUES ('Credit Customer') RETURNING id \gset debtor_
INSERT INTO credit_sales (sale_id, debtor_id, amount_due) VALUES (:sale_id, :debtor_id, 200) RETURNING id \gset credit_
INSERT INTO credit_payments (credit_sale_id, amount) VALUES (:credit_id, 150);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

DO $outer$
DECLARE
  credit_id_local BIGINT := :credit_id;
BEGIN
  BEGIN
    INSERT INTO credit_payments (credit_sale_id, amount) VALUES (credit_id_local, 51);
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'overpayment was accepted';
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  SET CONSTRAINTS ALL DEFERRED;
END
$outer$;

DO $outer$
DECLARE
  credit_id_local BIGINT := :credit_id;
BEGIN
  IF (SELECT SUM(amount) FROM credit_payments WHERE credit_sale_id = credit_id_local) <> 150 THEN
    RAISE EXCEPTION 'rejected overpayment changed payment history';
  END IF;
END
$outer$;

ROLLBACK;
