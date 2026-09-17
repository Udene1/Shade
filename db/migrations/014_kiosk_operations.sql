CREATE TABLE IF NOT EXISTS operation_requests (
  id UUID PRIMARY KEY,
  operation_type TEXT NOT NULL CHECK (operation_type IN ('SALE','CREDIT_SALE','PURCHASE','CREDIT_PAYMENT')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  result JSONB
);

CREATE TABLE IF NOT EXISTS day_closings (
  id BIGSERIAL PRIMARY KEY,
  business_date DATE NOT NULL UNIQUE,
  cash_sales NUMERIC(14,2) NOT NULL DEFAULT 0,
  credit_sales NUMERIC(14,2) NOT NULL DEFAULT 0,
  credit_payments NUMERIC(14,2) NOT NULL DEFAULT 0,
  purchases NUMERIC(14,2) NOT NULL DEFAULT 0,
  sales_revenue NUMERIC(14,2) NOT NULL DEFAULT 0,
  units_sold INTEGER NOT NULL DEFAULT 0,
  wac_gross_profit NUMERIC(14,2) NOT NULL DEFAULT 0,
  fifo_gross_profit NUMERIC(14,2) NOT NULL DEFAULT 0,
  stock_discrepancy_units INTEGER NOT NULL DEFAULT 0,
  outstanding_debt NUMERIC(14,2) NOT NULL DEFAULT 0,
  note TEXT,
  closed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE VIEW transaction_history AS
SELECT
  'SALE'::TEXT AS transaction_type,
  s.id AS transaction_id,
  s.sold_at AS occurred_at,
  p.id AS product_id,
  p.name AS product_name,
  s.quantity,
  s.unit_price,
  s.unit_cost,
  (s.quantity * s.unit_price)::numeric AS amount,
  NULL::TEXT AS counterparty,
  NULL::TEXT AS note
FROM sales s JOIN products p ON p.id = s.product_id
UNION ALL
SELECT
  'PURCHASE', pu.id, pu.purchased_at, p.id, p.name, pu.quantity,
  NULL::numeric, pu.unit_cost, (pu.quantity * pu.unit_cost)::numeric,
  pu.supplier, NULL::TEXT
FROM purchases pu JOIN products p ON p.id = pu.product_id
UNION ALL
SELECT
  'CREDIT_PAYMENT', cp.id, cp.paid_at, s.product_id, p.name, 0,
  NULL::numeric, NULL::numeric, cp.amount, d.name, cp.note
FROM credit_payments cp
JOIN credit_sales cs ON cs.id = cp.credit_sale_id
JOIN sales s ON s.id = cs.sale_id
JOIN products p ON p.id = s.product_id
JOIN debtors d ON d.id = cs.debtor_id
UNION ALL
SELECT
  'CREDIT_SALE', cs.id, cs.created_at, s.product_id, p.name, s.quantity,
  s.unit_price, s.unit_cost, cs.amount_due, d.name, d.notes
FROM credit_sales cs
JOIN sales s ON s.id = cs.sale_id
JOIN products p ON p.id = s.product_id
JOIN debtors d ON d.id = cs.debtor_id;

CREATE INDEX IF NOT EXISTS idx_day_closings_business_date ON day_closings(business_date);
CREATE INDEX IF NOT EXISTS idx_operation_requests_created_at ON operation_requests(created_at);
