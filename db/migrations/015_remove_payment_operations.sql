ALTER TABLE operation_requests DROP CONSTRAINT IF EXISTS operation_requests_operation_type_check;
ALTER TABLE operation_requests ADD CONSTRAINT operation_requests_operation_type_check CHECK (operation_type IN ('SALE','CREDIT_SALE','PURCHASE'));

DROP VIEW IF EXISTS transaction_history;
CREATE VIEW transaction_history AS
SELECT
  'SALE'::TEXT AS transaction_type,
  s.id AS transaction_id,
  s.sold_at AS occurred_at,
  p.id AS product_id,
  p.name AS product_name,
  s.quantity,
  s.unit_price,
  s.unit_cost,
  (s.quantity * s.unit_price)::numeric(14,2) AS amount,
  NULL::TEXT AS counterparty,
  NULL::TEXT AS note
FROM sales s JOIN products p ON p.id = s.product_id
UNION ALL
SELECT
  'PURCHASE'::TEXT, pu.id, pu.purchased_at, p.id, p.name, pu.quantity,
  NULL::numeric(14,2), pu.unit_cost, (pu.quantity * pu.unit_cost)::numeric(14,2),
  pu.supplier, NULL::TEXT
FROM purchases pu JOIN products p ON p.id = pu.product_id
UNION ALL
SELECT
  'CREDIT_SALE'::TEXT, cs.id, cs.created_at, s.product_id, p.name, s.quantity,
  s.unit_price, s.unit_cost, cs.amount_due, d.name, d.notes
FROM credit_sales cs
JOIN sales s ON s.id = cs.sale_id
JOIN products p ON p.id = s.product_id
JOIN debtors d ON d.id = cs.debtor_id;
