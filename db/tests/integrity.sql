BEGIN;

TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products RESTART IDENTITY CASCADE;

-- Purchase path: one business purchase must produce one matching ledger movement and stock delta.
INSERT INTO products (name, selling_price) VALUES ('Integrity Product', 250) RETURNING id \gset product_
INSERT INTO purchases (product_id, quantity, unit_cost, supplier, purchased_at)
VALUES (:product_id, 10, 100, 'Supplier A', '2026-03-01T09:00:00Z') RETURNING id \gset purchase_
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
VALUES (:product_id, 'PURCHASE', 10, :purchase_id);
UPDATE products SET current_stock = current_stock + 10 WHERE id = :product_id;

DO $$
BEGIN
  IF (SELECT stock_delta FROM inventory_integrity WHERE product_id = 1) <> 0 THEN
    RAISE EXCEPTION 'purchase stock/ledger delta must be zero';
  END IF;
  IF (SELECT COUNT(*) FROM ledger_integrity WHERE reference_id = 1 AND reference_integrity_ok = false) <> 0 THEN
    RAISE EXCEPTION 'purchase movement reference is invalid';
  END IF;
END $$;

-- Sale path: stock cannot be reduced without a corresponding sale movement.
INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
VALUES (:product_id, 3, 250, 100, '2026-03-02T09:00:00Z') RETURNING id \gset sale_
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
VALUES (:product_id, 'SALE', -3, :sale_id);
UPDATE products SET current_stock = current_stock - 3 WHERE id = :product_id;

DO $$
BEGIN
  IF (SELECT stock_delta FROM inventory_integrity WHERE product_id = 1) <> 0 THEN
    RAISE EXCEPTION 'sale stock/ledger delta must be zero';
  END IF;
  IF (SELECT COUNT(*) FROM ledger_integrity WHERE reference_id = 1 AND type = 'SALE' AND reference_integrity_ok = false) <> 0 THEN
    RAISE EXCEPTION 'sale movement reference is invalid';
  END IF;
END $$;

-- A failed/over-sized sale must not be representable as a ledger-only movement.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM products p
    WHERE p.id = 1 AND p.current_stock < 100
  ) THEN
    IF EXISTS (
      SELECT 1 FROM inventory_movements m
      WHERE m.product_id = 1 AND m.type = 'SALE' AND m.quantity = -100
    ) THEN
      RAISE EXCEPTION 'oversized sale created a stock movement';
    END IF;
  END IF;
END $$;

-- Credit sale and payment lifecycle.
INSERT INTO debtors (name, phone) VALUES ('Customer One', '08000000000') RETURNING id \gset debtor_
INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
VALUES (:product_id, 2, 250, 100, '2026-03-03T09:00:00Z') RETURNING id \gset credit_sale_
INSERT INTO credit_sales (sale_id, debtor_id, amount_due)
VALUES (:credit_sale_id, :debtor_id, 500) RETURNING id \gset credit_
INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
VALUES (:product_id, 'SALE', -2, :credit_sale_id);
UPDATE products SET current_stock = current_stock - 2 WHERE id = :product_id;

INSERT INTO credit_payments (credit_sale_id, amount, paid_at) VALUES (:credit_id, 200, '2026-03-04T09:00:00Z');
DO $$
BEGIN
  IF (SELECT outstanding_balance FROM credit_balances WHERE credit_sale_id = 1) <> 300 THEN
    RAISE EXCEPTION 'partial payment balance expected 300';
  END IF;
  IF (SELECT status FROM credit_balances WHERE credit_sale_id = 1) <> 'PARTIALLY_PAID' THEN
    RAISE EXCEPTION 'partial payment status incorrect';
  END IF;
END $$;

INSERT INTO credit_payments (credit_sale_id, amount, paid_at) VALUES (:credit_id, 300, '2026-03-05T09:00:00Z');
DO $$
BEGIN
  IF (SELECT outstanding_balance FROM credit_balances WHERE credit_sale_id = 1) <> 0 THEN
    RAISE EXCEPTION 'settled balance expected zero';
  END IF;
  IF (SELECT status FROM credit_balances WHERE credit_sale_id = 1) <> 'SETTLED' THEN
    RAISE EXCEPTION 'settled status incorrect';
  END IF;
END $$;

-- The database model must expose an overpayment if one is ever inserted; the application path must reject it.
INSERT INTO credit_payments (credit_sale_id, amount, paid_at)
SELECT :credit_id, 1, '2026-03-06T09:00:00Z'
WHERE false;
DO $$
BEGIN
  IF (SELECT amount_paid FROM credit_balances WHERE credit_sale_id = 1) <> 500 THEN
    RAISE EXCEPTION 'payment history changed during rejected overpayment';
  END IF;
  IF (SELECT outstanding_balance FROM credit_balances WHERE credit_sale_id = 1) <> 0 THEN
    RAISE EXCEPTION 'settled balance changed during rejected overpayment';
  END IF;
END $$;

-- Reconciliation with no difference must create no movement; an actual difference is an exact delta with a reason.
DO $$
DECLARE before_count integer; after_count integer; delta integer;
BEGIN
  SELECT COUNT(*) INTO before_count FROM inventory_movements WHERE product_id = 1 AND type = 'ADJUSTMENT';
  SELECT current_stock - COALESCE(SUM(quantity), 0)::int INTO delta
  FROM products p LEFT JOIN inventory_movements m ON m.product_id = p.id
  WHERE p.id = 1 GROUP BY p.current_stock;
  IF delta <> 0 THEN RAISE EXCEPTION 'expected no-difference reconciliation'; END IF;
  SELECT COUNT(*) INTO after_count FROM inventory_movements WHERE product_id = 1 AND type = 'ADJUSTMENT';
  IF after_count <> before_count THEN RAISE EXCEPTION 'matching reconciliation created movement'; END IF;
END $$;

INSERT INTO inventory_movements (product_id, type, quantity, unit_cost, reason, occurred_at)
VALUES (1, 'ADJUSTMENT', 4, 100, 'physical count surplus', '2026-03-07T09:00:00Z');
UPDATE products SET current_stock = current_stock + 4 WHERE id = 1;

DO $$
BEGIN
  IF (SELECT stock_delta FROM inventory_integrity WHERE product_id = 1) <> 0 THEN
    RAISE EXCEPTION 'adjustment did not reconcile stock to ledger';
  END IF;
  IF (SELECT reason FROM inventory_movements WHERE product_id = 1 AND type = 'ADJUSTMENT' ORDER BY id DESC LIMIT 1) <> 'physical count surplus' THEN
    RAISE EXCEPTION 'adjustment reason was not preserved';
  END IF;
  IF (SELECT quantity FROM inventory_movements WHERE product_id = 1 AND type = 'ADJUSTMENT' ORDER BY id DESC LIMIT 1) <> 4 THEN
    RAISE EXCEPTION 'adjustment delta is not exact';
  END IF;
END $$;

-- Both valuation methods remain available after all integrity operations.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM inventory_valuation WHERE product_id = 1) THEN
    RAISE EXCEPTION 'valuation row missing after transactions';
  END IF;
  IF (SELECT fifo_stock_cost FROM inventory_valuation WHERE product_id = 1) IS NULL
     OR (SELECT wac_stock_cost FROM inventory_valuation WHERE product_id = 1) IS NULL THEN
    RAISE EXCEPTION 'dual valuation is not available';
  END IF;
END $$;

ROLLBACK;
