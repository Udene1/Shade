CREATE OR REPLACE FUNCTION enforce_credit_payment_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  due NUMERIC(14,2);
  paid NUMERIC(14,2);
BEGIN
  SELECT amount_due INTO due
  FROM credit_sales
  WHERE id = COALESCE(NEW.credit_sale_id, OLD.credit_sale_id);

  SELECT COALESCE(SUM(amount), 0)::NUMERIC(14,2) INTO paid
  FROM credit_payments
  WHERE credit_sale_id = COALESCE(NEW.credit_sale_id, OLD.credit_sale_id);

  IF due IS NULL THEN
    RAISE EXCEPTION 'credit payment references a missing credit sale';
  END IF;

  IF paid > due THEN
    RAISE EXCEPTION 'credit payments exceed amount due for credit sale %', COALESCE(NEW.credit_sale_id, OLD.credit_sale_id);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS credit_payment_balance_integrity ON credit_payments;
CREATE CONSTRAINT TRIGGER credit_payment_balance_integrity
AFTER INSERT OR UPDATE OR DELETE ON credit_payments
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION enforce_credit_payment_balance();

CREATE OR REPLACE FUNCTION enforce_credit_sale_amount_due()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  expected NUMERIC(14,2);
BEGIN
  SELECT quantity * unit_price INTO expected
  FROM sales
  WHERE id = NEW.sale_id;

  IF expected IS NULL THEN
    RAISE EXCEPTION 'credit sale references a missing sale';
  END IF;

  IF NEW.amount_due <> expected THEN
    RAISE EXCEPTION 'credit sale % amount_due % does not match sale total %', NEW.id, NEW.amount_due, expected;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS credit_sale_amount_due_integrity ON credit_sales;
CREATE CONSTRAINT TRIGGER credit_sale_amount_due_integrity
AFTER INSERT OR UPDATE ON credit_sales
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION enforce_credit_sale_amount_due();
