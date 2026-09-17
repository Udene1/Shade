BEGIN;

TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products RESTART IDENTITY CASCADE;

INSERT INTO products (name, selling_price, current_stock, minimum_stock) VALUES
  ('Low Stock', 100, 2, 3),
  ('No Sales', 100, 5, 1),
  ('Moving Stock', 100, 10, 1);

INSERT INTO purchases (product_id, quantity, unit_cost, purchased_at)
SELECT id, CASE name WHEN 'Low Stock' THEN 2 WHEN 'No Sales' THEN 5 ELSE 10 END, 50, CURRENT_TIMESTAMP - INTERVAL '120 days' FROM products;
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'PURCHASE', pu.quantity, pu.id, pu.unit_cost, pu.purchased_at
FROM products p JOIN purchases pu ON pu.product_id = p.id;

INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, 5, 100, 50, CURRENT_TIMESTAMP - INTERVAL '5 days' FROM products WHERE name = 'Moving Stock';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'SALE', -s.quantity, s.id, s.unit_cost, s.sold_at
FROM products p JOIN sales s ON s.product_id = p.id;

DO $$
DECLARE status_low text; status_idle text; status_move text; units numeric;
BEGIN
  SELECT attention_status INTO status_low FROM inventory_attention WHERE name = 'Low Stock';
  SELECT attention_status INTO status_idle FROM inventory_attention WHERE name = 'No Sales';
  SELECT attention_status, units_sold_30d INTO status_move, units
  FROM inventory_attention WHERE name = 'Moving Stock';
  IF status_low <> 'LOW_STOCK' THEN RAISE EXCEPTION 'low stock status mismatch: %', status_low; END IF;
  IF status_idle <> 'NO_SALES_30D' THEN RAISE EXCEPTION 'no-sales status mismatch: %', status_idle; END IF;
  IF status_move <> 'NORMAL' THEN RAISE EXCEPTION 'moving stock status mismatch: %', status_move; END IF;
  IF units <> 5 THEN RAISE EXCEPTION 'moving stock units expected 5, got %', units; END IF;
END $$;

INSERT INTO debtors (name) VALUES ('Large Debtor'), ('Small Debtor');
INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, 1, 100, 50, CURRENT_TIMESTAMP FROM products WHERE name = 'Moving Stock';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'SALE', -1, s.id, 50, s.sold_at FROM products p JOIN sales s ON s.product_id = p.id ORDER BY s.id DESC LIMIT 1;
INSERT INTO credit_sales (sale_id, debtor_id, amount_due)
SELECT s.id, d.id, 900 FROM sales s JOIN debtors d ON d.name = 'Large Debtor' WHERE s.id = (SELECT MAX(id) FROM sales);
INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, 1, 100, 50, CURRENT_TIMESTAMP FROM products WHERE name = 'Moving Stock';
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'SALE', -1, s.id, 50, s.sold_at FROM products p JOIN sales s ON s.product_id = p.id ORDER BY s.id DESC LIMIT 1;
INSERT INTO credit_sales (sale_id, debtor_id, amount_due)
SELECT s.id, d.id, 100 FROM sales s JOIN debtors d ON d.name = 'Small Debtor' WHERE s.id = (SELECT MAX(id) FROM sales);

DO $$
DECLARE share numeric; total numeric; debtor_count bigint;
BEGIN
  SELECT outstanding_debt, debtors_with_balance, largest_debtor_share INTO total, debtor_count, share FROM store_debt_concentration;
  IF total <> 1000 THEN RAISE EXCEPTION 'debt total expected 1000, got %', total; END IF;
  IF debtor_count <> 2 THEN RAISE EXCEPTION 'debtor count expected 2, got %', debtor_count; END IF;
  IF share <> 0.9 THEN RAISE EXCEPTION 'largest debtor share expected 0.9, got %', share; END IF;
END $$;

ROLLBACK;
