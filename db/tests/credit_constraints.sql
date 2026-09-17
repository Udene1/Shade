BEGIN;

TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products RESTART IDENTITY CASCADE;

INSERT INTO products (name, selling_price) VALUES ('Credit Constraint Product', 100) RETURNING id \gset product_
INSERT INTO sales (product_id, quantity, unit_price, unit_cost) VALUES (:product_id, 2, 100, 40) RETURNING id \gset sale_
INSERT INTO debtors (name) VALUES ('Credit Customer') RETURNING id \gset debtor_
INSERT INTO credit_sales (sale_id, debtor_id, amount_due) VALUES (:sale_id, :debtor_id, 200) RETURNING id \gset credit_
INSERT INTO credit_payments (credit_sale_id, amount) VALUES (:credit_id, 150);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

CREATE OR REPLACE FUNCTION assert_credit_overpayment_rejected(target_credit_sale_id BIGINT)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
  BEGIN
    INSERT INTO credit_payments (credit_sale_id, amount) VALUES (target_credit_sale_id, 51);
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'overpayment was accepted';
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  SET CONSTRAINTS ALL DEFERRED;

  IF (SELECT SUM(amount) FROM credit_payments WHERE credit_sale_id = target_credit_sale_id) <> 150 THEN
    RAISE EXCEPTION 'rejected overpayment changed payment history';
  END IF;
END
$function$;

SELECT assert_credit_overpayment_rejected(:credit_id);
DROP FUNCTION assert_credit_overpayment_rejected(BIGINT);

ROLLBACK;
