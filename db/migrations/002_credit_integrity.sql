-- Credit/debtor integrity migration.
-- Safe to run repeatedly after the initial schema migration.

CREATE TABLE IF NOT EXISTS debtors (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS credit_sales (
  id BIGSERIAL PRIMARY KEY,
  sale_id BIGINT NOT NULL UNIQUE REFERENCES sales(id),
  debtor_id BIGINT NOT NULL REFERENCES debtors(id),
  amount_due NUMERIC(14,2) NOT NULL CHECK (amount_due >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS credit_payments (
  id BIGSERIAL PRIMARY KEY,
  credit_sale_id BIGINT NOT NULL REFERENCES credit_sales(id),
  amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  paid_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  note TEXT
);

CREATE INDEX IF NOT EXISTS idx_credit_sales_debtor_id ON credit_sales(debtor_id);
CREATE INDEX IF NOT EXISTS idx_credit_payments_credit_sale_id ON credit_payments(credit_sale_id);
CREATE INDEX IF NOT EXISTS idx_debtors_name ON debtors(name);
CREATE INDEX IF NOT EXISTS idx_debtors_phone ON debtors(phone);
