BEGIN;

TRUNCATE TABLE credit_payments, credit_sales, debtors, inventory_movements, sales, purchases, products RESTART IDENTITY CASCADE;

INSERT INTO products (name, selling_price, current_stock, minimum_stock)
VALUES ('Capital Product', 100, 10, 1);

INSERT INTO purchases (product_id, quantity, unit_cost, purchased_at)
SELECT id, 20, 50, CURRENT_TIMESTAMP - INTERVAL '20 days' FROM products;
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'PURCHASE', pu.quantity, pu.id, pu.unit_cost, pu.purchased_at
FROM products p JOIN purchases pu ON pu.product_id = p.id;

INSERT INTO sales (product_id, quantity, unit_price, unit_cost, sold_at)
SELECT id, 10, 100, 50, CURRENT_TIMESTAMP - INTERVAL '5 days' FROM products;
INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, occurred_at)
SELECT p.id, 'SALE', -s.quantity, s.id, s.unit_cost, s.sold_at
FROM products p JOIN sales s ON s.product_id = p.id;

DO $$
DECLARE fifo_cost numeric; wac_cost numeric; fifo_gp numeric; wac_gp numeric; fifo_ratio numeric; wac_ratio numeric; store_fifo numeric; store_wac numeric;
BEGIN
  SELECT fifo_capital_in_stock, wac_capital_in_stock, fifo_gross_profit_30d, wac_gross_profit_30d,
         fifo_gross_profit_per_current_stock_cost_30d, wac_gross_profit_per_current_stock_cost_30d
  INTO fifo_cost, wac_cost, fifo_gp, wac_gp, fifo_ratio, wac_ratio
  FROM product_capital_productivity WHERE name = 'Capital Product';

  IF fifo_cost <> 500 THEN RAISE EXCEPTION 'FIFO capital expected 500, got %', fifo_cost; END IF;
  IF wac_cost <> 500 THEN RAISE EXCEPTION 'WAC capital expected 500, got %', wac_cost; END IF;
  IF fifo_gp <> 500 THEN RAISE EXCEPTION 'FIFO gross profit expected 500, got %', fifo_gp; END IF;
  IF wac_gp <> 500 THEN RAISE EXCEPTION 'WAC gross profit expected 500, got %', wac_gp; END IF;
  IF fifo_ratio <> 1 THEN RAISE EXCEPTION 'FIFO productivity expected 1, got %', fifo_ratio; END IF;
  IF wac_ratio <> 1 THEN RAISE EXCEPTION 'WAC productivity expected 1, got %', wac_ratio; END IF;

  SELECT fifo_gross_profit_per_current_stock_cost_30d, wac_gross_profit_per_current_stock_cost_30d
  INTO store_fifo, store_wac FROM store_capital_productivity;
  IF store_fifo <> 1 THEN RAISE EXCEPTION 'store FIFO productivity expected 1, got %', store_fifo; END IF;
  IF store_wac <> 1 THEN RAISE EXCEPTION 'store WAC productivity expected 1, got %', store_wac; END IF;
END $$;

ROLLBACK;
