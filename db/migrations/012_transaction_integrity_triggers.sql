CREATE OR REPLACE FUNCTION enforce_inventory_stock_ledger_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  product_id_to_check BIGINT;
  current_stock_value INTEGER;
  ledger_stock_value INTEGER;
BEGIN
  product_id_to_check := COALESCE(NEW.product_id, OLD.product_id);

  SELECT current_stock INTO current_stock_value
  FROM products
  WHERE id = product_id_to_check;

  SELECT COALESCE(SUM(quantity), 0)::INTEGER INTO ledger_stock_value
  FROM inventory_movements
  WHERE product_id = product_id_to_check;

  IF current_stock_value IS DISTINCT FROM ledger_stock_value THEN
    RAISE EXCEPTION 'inventory stock/ledger mismatch for product %: current_stock=%, ledger_stock=%',
      product_id_to_check, current_stock_value, ledger_stock_value;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS inventory_stock_ledger_consistency_on_movement ON inventory_movements;
CREATE CONSTRAINT TRIGGER inventory_stock_ledger_consistency_on_movement
AFTER INSERT OR UPDATE OR DELETE ON inventory_movements
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION enforce_inventory_stock_ledger_consistency();

DROP TRIGGER IF EXISTS inventory_stock_ledger_consistency_on_product ON products;
CREATE CONSTRAINT TRIGGER inventory_stock_ledger_consistency_on_product
AFTER UPDATE OF current_stock ON products
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION enforce_inventory_stock_ledger_consistency();

CREATE OR REPLACE FUNCTION prevent_invalid_inventory_movement_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.type = 'PURCHASE' THEN
    IF NOT EXISTS (
      SELECT 1 FROM purchases
      WHERE id = NEW.reference_id AND product_id = NEW.product_id
    ) THEN
      RAISE EXCEPTION 'purchase movement % does not reference the same product purchase', NEW.id;
    END IF;
  ELSIF NEW.type = 'SALE' THEN
    IF NOT EXISTS (
      SELECT 1 FROM sales
      WHERE id = NEW.reference_id AND product_id = NEW.product_id
    ) THEN
      RAISE EXCEPTION 'sale movement % does not reference the same product sale', NEW.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS inventory_movement_reference_integrity ON inventory_movements;
CREATE CONSTRAINT TRIGGER inventory_movement_reference_integrity
AFTER INSERT OR UPDATE ON inventory_movements
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION prevent_invalid_inventory_movement_reference();
