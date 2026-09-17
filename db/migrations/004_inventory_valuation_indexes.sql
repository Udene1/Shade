-- Valuation scans each product's movement history in deterministic chronological order.
-- Keep the ordering index separate from the valuation logic so the ledger remains the source of truth.
CREATE INDEX IF NOT EXISTS idx_inventory_movements_product_created_id
  ON inventory_movements(product_id, created_at, id);

CREATE INDEX IF NOT EXISTS idx_inventory_movements_sale_reference
  ON inventory_movements(type, reference_id)
  WHERE type = 'SALE';

CREATE INDEX IF NOT EXISTS idx_inventory_movements_purchase_reference
  ON inventory_movements(type, reference_id)
  WHERE type = 'PURCHASE';
