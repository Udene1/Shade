CREATE OR REPLACE VIEW inventory_integrity AS
SELECT
  p.id AS product_id,
  p.name,
  p.current_stock,
  COALESCE(SUM(m.quantity), 0)::numeric AS ledger_stock,
  p.current_stock - COALESCE(SUM(m.quantity), 0)::numeric AS stock_delta,
  COUNT(m.id) FILTER (WHERE m.type = 'PURCHASE') AS purchase_movements,
  COUNT(m.id) FILTER (WHERE m.type = 'SALE') AS sale_movements,
  COUNT(m.id) FILTER (WHERE m.type = 'ADJUSTMENT') AS adjustment_movements
FROM products p
LEFT JOIN inventory_movements m ON m.product_id = p.id
GROUP BY p.id, p.name, p.current_stock;

CREATE OR REPLACE VIEW credit_balances AS
SELECT
  cs.id AS credit_sale_id,
  cs.sale_id,
  cs.debtor_id,
  d.name AS debtor_name,
  cs.amount_due,
  COALESCE(SUM(cp.amount), 0)::numeric AS amount_paid,
  GREATEST(cs.amount_due - COALESCE(SUM(cp.amount), 0), 0)::numeric AS outstanding_balance,
  CASE
    WHEN COALESCE(SUM(cp.amount), 0) = 0 THEN 'OPEN'
    WHEN COALESCE(SUM(cp.amount), 0) < cs.amount_due THEN 'PARTIALLY_PAID'
    WHEN COALESCE(SUM(cp.amount), 0) = cs.amount_due THEN 'SETTLED'
    ELSE 'OVERPAID'
  END AS status
FROM credit_sales cs
JOIN debtors d ON d.id = cs.debtor_id
LEFT JOIN credit_payments cp ON cp.credit_sale_id = cs.id
GROUP BY cs.id, cs.sale_id, cs.debtor_id, d.name, cs.amount_due;

CREATE OR REPLACE VIEW credit_integrity AS
SELECT
  cb.*,
  CASE WHEN cb.amount_paid <= cb.amount_due THEN true ELSE false END AS payment_integrity_ok,
  s.quantity * s.unit_price AS sale_amount
FROM credit_balances cb
JOIN sales s ON s.id = cb.sale_id;

CREATE OR REPLACE VIEW ledger_integrity AS
SELECT
  m.id AS movement_id,
  m.product_id,
  m.type,
  m.quantity,
  m.reference_id,
  m.occurred_at,
  CASE
    WHEN m.type = 'PURCHASE' THEN EXISTS (
      SELECT 1 FROM purchases p WHERE p.id = m.reference_id
        AND p.product_id = m.product_id AND p.quantity = m.quantity
    )
    WHEN m.type = 'SALE' THEN EXISTS (
      SELECT 1 FROM sales s WHERE s.id = m.reference_id
        AND s.product_id = m.product_id AND -s.quantity = m.quantity
    )
    WHEN m.type = 'ADJUSTMENT' THEN true
    ELSE false
  END AS reference_integrity_ok
FROM inventory_movements m;

CREATE INDEX IF NOT EXISTS idx_credit_payments_credit_sale_paid_at
  ON credit_payments(credit_sale_id, paid_at, id);
