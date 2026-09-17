BEGIN;

TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products RESTART IDENTITY CASCADE;

-- Scenario 1: crossing FIFO layers and WAC divergence.
INSERT INTO products (name, selling_price, current_stock) VALUES ('Layer Test', 300, 0);

INSERT INTO purchases (product_id, quantity, unit_cost, purchased_at)
SELECT id, 10, 100, '2026-01-01T09:00:00Z' FROM products WHERE name = 'Layer Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
SELECT p.id, 'PURCHASE', 10, pu.id FROM products p JOIN purchases pu ON pu.product_id = p.id
WHERE p.name = 'Layer Test' AND pu.unit_cost = 100;

INSERT INTO purchases (product_id, quantity, unit_cost, purchased_at)
SELECT id, 10, 200, '2026-01-02T09:00:00Z' FROM products WHERE name = 'Layer Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
SELECT p.id, 'PURCHASE', 10, pu.id FROM products p JOIN purchases pu ON pu.product_id = p.id
WHERE p.name = 'Layer Test' AND pu.unit_cost = 200;

INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, 12, 300, 150, '2026-01-03T09:00:00Z' FROM products WHERE name = 'Layer Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
SELECT p.id, 'SALE', -12, s.id FROM products p JOIN sales s ON s.product_id = p.id
WHERE p.name = 'Layer Test' AND s.quantity = 12;
UPDATE products SET current_stock = 8 WHERE name = 'Layer Test';

DO $$
DECLARE sale_fifo numeric; sale_wac numeric; stock_fifo numeric; stock_wac numeric; ledger_qty numeric;
BEGIN
  SELECT fifo_cost, wac_cost INTO sale_fifo, sale_wac FROM inventory_sale_costs
  WHERE movement_id = (SELECT id FROM inventory_movements WHERE type = 'SALE' ORDER BY id DESC LIMIT 1);
  SELECT fifo_stock_cost, wac_stock_cost, ledger_quantity INTO stock_fifo, stock_wac, ledger_qty
  FROM inventory_valuation WHERE product_id = (SELECT id FROM products WHERE name = 'Layer Test');
  IF sale_fifo <> 1400 THEN RAISE EXCEPTION 'cross-layer FIFO sale expected 1400, got %', sale_fifo; END IF;
  IF sale_wac <> 1800 THEN RAISE EXCEPTION 'cross-layer WAC sale expected 1800, got %', sale_wac; END IF;
  IF stock_fifo <> 1600 THEN RAISE EXCEPTION 'cross-layer FIFO stock expected 1600, got %', stock_fifo; END IF;
  IF stock_wac <> 1200 THEN RAISE EXCEPTION 'cross-layer WAC stock expected 1200, got %', stock_wac; END IF;
  IF ledger_qty <> 8 THEN RAISE EXCEPTION 'ledger quantity expected 8, got %', ledger_qty; END IF;
END $$;

-- Scenario 2: sale exactly consumes the remaining FIFO layer, then repurchase at a new cost.
INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, 8, 300, 200, '2026-01-04T09:00:00Z' FROM products WHERE name = 'Layer Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
SELECT p.id, 'SALE', -8, s.id FROM products p JOIN sales s ON s.product_id = p.id
WHERE p.name = 'Layer Test' AND s.quantity = 8;
UPDATE products SET current_stock = 0 WHERE name = 'Layer Test';

INSERT INTO purchases (product_id, quantity, unit_cost, purchased_at)
SELECT id, 5, 500, '2026-01-05T09:00:00Z' FROM products WHERE name = 'Layer Test';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
SELECT p.id, 'PURCHASE', 5, pu.id FROM products p JOIN purchases pu ON pu.product_id = p.id
WHERE p.name = 'Layer Test' AND pu.unit_cost = 500;
UPDATE products SET current_stock = 5 WHERE name = 'Layer Test';

DO $$
DECLARE sale_fifo numeric; sale_wac numeric; stock_fifo numeric; stock_wac numeric;
BEGIN
  SELECT fifo_cost, wac_cost INTO sale_fifo, sale_wac FROM inventory_sale_costs
  WHERE movement_id = (SELECT id FROM inventory_movements WHERE type = 'SALE' ORDER BY id DESC LIMIT 1);
  SELECT fifo_stock_cost, wac_stock_cost INTO stock_fifo, stock_wac FROM inventory_valuation
  WHERE product_id = (SELECT id FROM products WHERE name = 'Layer Test');
  IF sale_fifo <> 1600 THEN RAISE EXCEPTION 'exact-layer FIFO sale expected 1600, got %', sale_fifo; END IF;
  IF sale_wac <> 1200 THEN RAISE EXCEPTION 'exact-layer WAC sale expected 1200, got %', sale_wac; END IF;
  IF stock_fifo <> 2500 THEN RAISE EXCEPTION 'post-repurchase FIFO stock expected 2500, got %', stock_fifo; END IF;
  IF stock_wac <> 2500 THEN RAISE EXCEPTION 'post-repurchase WAC stock expected 2500, got %', stock_wac; END IF;
END $$;

-- Scenario 3: positive and negative adjustments are valuation events, not hidden stock edits.
INSERT INTO inventory_movements (product_id, type, quantity, unit_cost, reason, created_at)
SELECT id, 'ADJUSTMENT', 5, 600, 'physical count surplus', '2026-01-06T09:00:00Z' FROM products WHERE name = 'Layer Test';
UPDATE products SET current_stock = 10 WHERE name = 'Layer Test';
INSERT INTO inventory_movements (product_id, type, quantity, unit_cost, reason, created_at)
SELECT id, 'ADJUSTMENT', -3, 600, 'damaged units', '2026-01-07T09:00:00Z' FROM products WHERE name = 'Layer Test';
UPDATE products SET current_stock = 7 WHERE name = 'Layer Test';

DO $$
DECLARE stock_fifo numeric; stock_wac numeric; ledger_qty numeric; adjustment_count integer;
BEGIN
  SELECT fifo_stock_cost, wac_stock_cost, ledger_quantity INTO stock_fifo, stock_wac, ledger_qty
  FROM inventory_valuation WHERE product_id = (SELECT id FROM products WHERE name = 'Layer Test');
  SELECT COUNT(*) INTO adjustment_count FROM inventory_movements
  WHERE type = 'ADJUSTMENT' AND product_id = (SELECT id FROM products WHERE name = 'Layer Test');
  IF stock_fifo <> 4000 THEN RAISE EXCEPTION 'adjusted FIFO stock expected 4000, got %', stock_fifo; END IF;
  IF stock_wac <> 3850 THEN RAISE EXCEPTION 'adjusted WAC stock expected 3850, got %', stock_wac; END IF;
  IF ledger_qty <> 7 THEN RAISE EXCEPTION 'adjusted ledger quantity expected 7, got %', ledger_qty; END IF;
  IF adjustment_count <> 2 THEN RAISE EXCEPTION 'expected 2 adjustment events, got %', adjustment_count; END IF;
END $$;

-- Scenario 4: identical timestamps are deterministic because movement id is the tie-breaker.
INSERT INTO products (name, selling_price, current_stock) VALUES ('Tie Test', 400, 0);
INSERT INTO inventory_movements (product_id, type, quantity, unit_cost, created_at)
SELECT id, 'ADJUSTMENT', 5, 100, '2026-02-01T09:00:00Z' FROM products WHERE name = 'Tie Test';
INSERT INTO inventory_movements (product_id, type, quantity, unit_cost, created_at)
SELECT id, 'ADJUSTMENT', 5, 300, '2026-02-01T09:00:00Z' FROM products WHERE name = 'Tie Test';
INSERT INTO inventory_movements (product_id, type, quantity, unit_cost, created_at)
SELECT id, 'ADJUSTMENT', -5, 0, '2026-02-02T09:00:00Z' FROM products WHERE name = 'Tie Test';
UPDATE products SET current_stock = 5 WHERE name = 'Tie Test';

DO $$
DECLARE stock_fifo numeric; stock_wac numeric;
BEGIN
  SELECT fifo_stock_cost, wac_stock_cost INTO stock_fifo, stock_wac FROM inventory_valuation
  WHERE product_id = (SELECT id FROM products WHERE name = 'Tie Test');
  IF stock_fifo <> 1500 THEN RAISE EXCEPTION 'tie-order FIFO stock expected 1500, got %', stock_fifo; END IF;
  IF stock_wac <> 1000 THEN RAISE EXCEPTION 'tie-order WAC stock expected 1000, got %', stock_wac; END IF;
END $$;

-- Selection is a presentation/accounting-policy choice; underlying WAC/FIFO values remain intact.
UPDATE inventory_valuation_settings SET method = 'FIFO' WHERE id = 1;
DO $$
BEGIN
  IF (SELECT selected_stock_cost FROM inventory_valuation_selected WHERE product_id = (SELECT id FROM products WHERE name = 'Layer Test')) <> 4000
    THEN RAISE EXCEPTION 'FIFO selection did not expose FIFO value';
  END IF;
END $$;
UPDATE inventory_valuation_settings SET method = 'WAC' WHERE id = 1;
DO $$
BEGIN
  IF (SELECT selected_stock_cost FROM inventory_valuation_selected WHERE product_id = (SELECT id FROM products WHERE name = 'Layer Test')) <> 3850
    THEN RAISE EXCEPTION 'WAC selection did not expose WAC value';
  END IF;
END $$;

-- Every tested product must reconcile: current stock equals the authoritative movement ledger.
DO $$
DECLARE mismatches integer;
BEGIN
  SELECT COUNT(*) INTO mismatches FROM inventory_valuation WHERE current_stock <> ledger_quantity;
  IF mismatches <> 0 THEN RAISE EXCEPTION 'stock/ledger mismatch count expected 0, got %', mismatches; END IF;
END $$;

ROLLBACK;
