BEGIN;

TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products RESTART IDENTITY CASCADE;

INSERT INTO products (name, selling_price, current_stock) VALUES ('Valuation Test', 200, 0);

-- Two purchase layers: 10 @ 100, then 10 @ 200.
INSERT INTO purchases (product_id, quantity, unit_cost, purchased_at)
SELECT id, 10, 100, '2026-01-01T09:00:00Z' FROM products WHERE name = 'Valuation Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
SELECT p.id, 'PURCHASE', 10, pu.id FROM products p JOIN purchases pu ON pu.product_id = p.id WHERE p.name = 'Valuation Test' AND pu.unit_cost = 100;

INSERT INTO purchases (product_id, quantity, unit_cost, purchased_at)
SELECT id, 10, 200, '2026-01-02T09:00:00Z' FROM products WHERE name = 'Valuation Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
SELECT p.id, 'PURCHASE', 10, pu.id FROM products p JOIN purchases pu ON pu.product_id = p.id WHERE p.name = 'Valuation Test' AND pu.unit_cost = 200;

-- Sell 5. FIFO = 500. WAC = 750.
INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, 5, 200, 150, '2026-01-03T09:00:00Z' FROM products WHERE name = 'Valuation Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
SELECT p.id, 'SALE', -5, s.id FROM products p JOIN sales s ON s.product_id = p.id WHERE p.name = 'Valuation Test' AND s.quantity = 5;

UPDATE products SET current_stock = 15 WHERE name = 'Valuation Test';

DO $$
DECLARE
  sale_fifo numeric;
  sale_wac numeric;
  stock_fifo numeric;
  stock_wac numeric;
BEGIN
  SELECT fifo_cost, wac_cost INTO sale_fifo, sale_wac
  FROM inventory_sale_costs
  WHERE movement_id = (SELECT id FROM inventory_movements WHERE type = 'SALE' ORDER BY id DESC LIMIT 1);

  SELECT fifo_stock_cost, wac_stock_cost INTO stock_fifo, stock_wac
  FROM inventory_valuation
  WHERE product_id = (SELECT id FROM products WHERE name = 'Valuation Test');

  IF sale_fifo <> 500 THEN RAISE EXCEPTION 'FIFO sale cost expected 500, got %', sale_fifo; END IF;
  IF sale_wac <> 750 THEN RAISE EXCEPTION 'WAC sale cost expected 750, got %', sale_wac; END IF;
  IF stock_fifo <> 2500 THEN RAISE EXCEPTION 'FIFO stock cost expected 2500, got %', stock_fifo; END IF;
  IF stock_wac <> 2250 THEN RAISE EXCEPTION 'WAC stock cost expected 2250, got %', stock_wac; END IF;

  UPDATE inventory_valuation_settings SET method = 'FIFO' WHERE id = 1;
  IF (SELECT selected_stock_cost FROM inventory_valuation_selected WHERE product_id = (SELECT id FROM products WHERE name = 'Valuation Test')) <> 2500
    THEN RAISE EXCEPTION 'FIFO selection did not switch to FIFO value'; END IF;

  UPDATE inventory_valuation_settings SET method = 'WAC' WHERE id = 1;
  IF (SELECT selected_stock_cost FROM inventory_valuation_selected WHERE product_id = (SELECT id FROM products WHERE name = 'Valuation Test')) <> 2250
    THEN RAISE EXCEPTION 'WAC selection did not switch to WAC value'; END IF;
END $$;

ROLLBACK;
