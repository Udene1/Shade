CREATE OR REPLACE VIEW shade_data_health AS
WITH stock AS (
  SELECT COUNT(*)::int AS bad FROM products p LEFT JOIN inventory_movements m ON m.product_id = p.id
  GROUP BY p.id HAVING p.current_stock <> COALESCE(SUM(m.quantity), 0)
),
refs AS (
  SELECT COUNT(*)::int AS bad FROM inventory_movements m
  WHERE (m.type = 'PURCHASE' AND NOT EXISTS (SELECT 1 FROM purchases p WHERE p.id = m.reference_id AND p.product_id = m.product_id))
     OR (m.type = 'SALE' AND NOT EXISTS (SELECT 1 FROM sales s WHERE s.id = m.reference_id AND s.product_id = m.product_id))
),
credits AS (
  SELECT COUNT(*)::int AS bad FROM credit_sales cs LEFT JOIN sales s ON s.id = cs.sale_id
  WHERE s.id IS NULL OR cs.amount_due <> s.quantity * s.unit_price
),
payments AS (
  SELECT COUNT(*)::int AS bad FROM credit_sales cs
  LEFT JOIN LATERAL (SELECT COALESCE(SUM(cp.amount), 0)::numeric AS paid FROM credit_payments cp WHERE cp.credit_sale_id = cs.id) p ON true
  WHERE p.paid > cs.amount_due
),
valuation AS (
  SELECT COUNT(*)::int AS bad FROM inventory_valuation v WHERE v.current_stock <> v.ledger_quantity
),
closings AS (
  SELECT COUNT(*)::int AS bad FROM day_closings d
  WHERE d.sales_revenue <> d.cash_sales + d.credit_sales OR d.units_sold < 0 OR d.stock_discrepancy_units < 0
),
operations AS (
  SELECT COUNT(*)::int AS bad FROM operation_requests o
  WHERE o.completed_at IS NULL AND o.created_at < NOW() - INTERVAL '15 minutes'
)
SELECT 'STOCK_LEDGER'::text AS check_name,
  CASE WHEN (SELECT COUNT(*) FROM stock) = 0 THEN 'OK' ELSE 'ERROR' END AS status,
  CASE WHEN (SELECT COUNT(*) FROM stock) = 0 THEN 'Every product stock count matches its inventory ledger.'
       ELSE (SELECT COUNT(*)::text FROM stock) || ' product(s) have stock/ledger mismatches.' END AS detail
UNION ALL
SELECT 'MOVEMENT_REFERENCES', CASE WHEN (SELECT bad FROM (SELECT COALESCE(SUM(bad),0)::int bad FROM refs) x) = 0 THEN 'OK' ELSE 'ERROR' END,
  CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM refs) = 0 THEN 'Purchase and sale movements reference matching business records.'
       ELSE (SELECT COALESCE(SUM(bad),0)::text FROM refs) || ' invalid inventory movement reference(s).' END
UNION ALL
SELECT 'CREDIT_SALES', CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM credits) = 0 THEN 'OK' ELSE 'ERROR' END,
  CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM credits) = 0 THEN 'Credit sales match their underlying sale totals.'
       ELSE (SELECT COALESCE(SUM(bad),0)::text FROM credits) || ' credit sale integrity error(s).' END
UNION ALL
SELECT 'CREDIT_PAYMENTS', CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM payments) = 0 THEN 'OK' ELSE 'ERROR' END,
  CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM payments) = 0 THEN 'Recorded credit payments do not exceed amounts due.'
       ELSE (SELECT COALESCE(SUM(bad),0)::text FROM payments) || ' overpayment error(s).' END
UNION ALL
SELECT 'VALUATION_QUANTITY', CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM valuation) = 0 THEN 'OK' ELSE 'ERROR' END,
  CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM valuation) = 0 THEN 'WAC/FIFO valuation quantity agrees with the inventory ledger.'
       ELSE (SELECT COALESCE(SUM(bad),0)::text FROM valuation) || ' valuation quantity mismatch(es).' END
UNION ALL
SELECT 'DAY_CLOSINGS', CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM closings) = 0 THEN 'OK' ELSE 'ERROR' END,
  CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM closings) = 0 THEN 'Closed-day totals pass basic consistency checks.'
       ELSE (SELECT COALESCE(SUM(bad),0)::text FROM closings) || ' day closing consistency error(s).' END
UNION ALL
SELECT 'PENDING_OPERATIONS', CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM operations) = 0 THEN 'OK' ELSE 'WARNING' END,
  CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM operations) = 0 THEN 'No operation request has been pending for more than 15 minutes.'
       ELSE (SELECT COALESCE(SUM(bad),0)::text FROM operations) || ' operation request(s) have been pending for more than 15 minutes; inspect before retrying.' END;
