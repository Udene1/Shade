ALTER TABLE operation_requests
  ADD COLUMN IF NOT EXISTS claim_token UUID,
  ADD COLUMN IF NOT EXISTS lease_expires_at TIMESTAMPTZ;

UPDATE operation_requests
SET claim_token = COALESCE(claim_token, md5(id::text || created_at::text)::uuid),
    lease_expires_at = COALESCE(lease_expires_at, created_at + INTERVAL '2 minutes')
WHERE claim_token IS NULL OR lease_expires_at IS NULL;

ALTER TABLE operation_requests
  ALTER COLUMN claim_token SET DEFAULT md5(random()::text || clock_timestamp()::text)::uuid;

CREATE INDEX IF NOT EXISTS idx_operation_requests_pending_lease
  ON operation_requests(lease_expires_at)
  WHERE completed_at IS NULL;

CREATE OR REPLACE FUNCTION claim_kiosk_operation(p_id UUID,p_type TEXT,p_token UUID)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE claimed BOOLEAN := false;
BEGIN
  INSERT INTO operation_requests (id, operation_type, claim_token, lease_expires_at)
  VALUES (p_id, p_type, p_token, NOW() + INTERVAL '2 minutes')
  ON CONFLICT (id) DO UPDATE
  SET claim_token = EXCLUDED.claim_token, lease_expires_at = EXCLUDED.lease_expires_at,
      completed_at = NULL, result = NULL
  WHERE operation_requests.completed_at IS NULL
    AND operation_requests.operation_type = EXCLUDED.operation_type
    AND COALESCE(operation_requests.lease_expires_at, operation_requests.created_at) < NOW()
  RETURNING true INTO claimed;
  RETURN COALESCE(claimed, false);
END;
$$;

CREATE OR REPLACE FUNCTION complete_kiosk_operation(p_id UUID,p_token UUID,p_result JSONB)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  UPDATE operation_requests
  SET completed_at = NOW(), result = p_result, lease_expires_at = NULL
  WHERE id = p_id AND claim_token = p_token AND completed_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'operation % lost its execution claim', p_id; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION record_purchase_operation(
  p_operation_id UUID,p_product_id BIGINT,p_quantity INTEGER,p_unit_cost NUMERIC(14,2),p_supplier TEXT,p_token UUID)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE product_row products%ROWTYPE; purchase_id BIGINT; result JSONB;
BEGIN
  IF NOT claim_kiosk_operation(p_operation_id,'PURCHASE',p_token) THEN
    SELECT result INTO result FROM operation_requests WHERE id=p_operation_id;
    IF result IS NOT NULL THEN RETURN result; END IF;
    RETURN jsonb_build_object('ok',false,'message','This operation is still being processed. Refresh and check transaction history before retrying.');
  END IF;
  SELECT * INTO product_row FROM products WHERE id=p_product_id FOR UPDATE;
  IF NOT FOUND THEN
    result:=jsonb_build_object('ok',false,'message','Product was not found.');
    PERFORM complete_kiosk_operation(p_operation_id,p_token,result); RETURN result;
  END IF;
  INSERT INTO purchases(product_id,quantity,unit_cost,supplier) VALUES(p_product_id,p_quantity,p_unit_cost,p_supplier) RETURNING id INTO purchase_id;
  UPDATE products SET current_stock=current_stock+p_quantity WHERE id=p_product_id;
  INSERT INTO inventory_movements(product_id,type,quantity,reference_id) VALUES(p_product_id,'PURCHASE',p_quantity,purchase_id);
  result:=jsonb_build_object('ok',true,'message','Purchase recorded and stock increased.');
  PERFORM complete_kiosk_operation(p_operation_id,p_token,result); RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION record_sale_operation(
  p_operation_id UUID,p_product_id BIGINT,p_quantity INTEGER,p_token UUID)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE product_row products%ROWTYPE; unit_cost NUMERIC(14,2); sale_id BIGINT; result JSONB;
BEGIN
  IF NOT claim_kiosk_operation(p_operation_id,'SALE',p_token) THEN
    SELECT result INTO result FROM operation_requests WHERE id=p_operation_id;
    IF result IS NOT NULL THEN RETURN result; END IF;
    RETURN jsonb_build_object('ok',false,'message','This operation is still being processed. Refresh and check transaction history before retrying.');
  END IF;
  SELECT * INTO product_row FROM products WHERE id=p_product_id FOR UPDATE;
  IF NOT FOUND THEN
    result:=jsonb_build_object('ok',false,'message','Product was not found.');
    PERFORM complete_kiosk_operation(p_operation_id,p_token,result); RETURN result;
  END IF;
  IF product_row.current_stock < p_quantity THEN
    result:=jsonb_build_object('ok',false,'message','Not enough stock for this sale.');
    PERFORM complete_kiosk_operation(p_operation_id,p_token,result); RETURN result;
  END IF;
  SELECT COALESCE((SELECT p.unit_cost FROM purchases p WHERE p.product_id=p_product_id ORDER BY p.purchased_at DESC,p.id DESC LIMIT 1),0)::NUMERIC(14,2) INTO unit_cost;
  INSERT INTO sales(product_id,quantity,unit_price,unit_cost) VALUES(p_product_id,p_quantity,product_row.selling_price,unit_cost) RETURNING id INTO sale_id;
  UPDATE products SET current_stock=current_stock-p_quantity WHERE id=p_product_id;
  INSERT INTO inventory_movements(product_id,type,quantity,reference_id) VALUES(p_product_id,'SALE',-p_quantity,sale_id);
  result:=jsonb_build_object('ok',true,'message','Sale recorded and stock reduced.');
  PERFORM complete_kiosk_operation(p_operation_id,p_token,result); RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION record_credit_sale_operation(
  p_operation_id UUID,p_product_id BIGINT,p_quantity INTEGER,p_debtor_name TEXT,p_phone TEXT,p_note TEXT,p_token UUID)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE product_row products%ROWTYPE; debtor_id BIGINT; sale_id BIGINT; unit_cost NUMERIC(14,2); result JSONB;
BEGIN
  IF NOT claim_kiosk_operation(p_operation_id,'CREDIT_SALE',p_token) THEN
    SELECT result INTO result FROM operation_requests WHERE id=p_operation_id;
    IF result IS NOT NULL THEN RETURN result; END IF;
    RETURN jsonb_build_object('ok',false,'message','This operation is still being processed. Refresh and check transaction history before retrying.');
  END IF;
  SELECT * INTO product_row FROM products WHERE id=p_product_id FOR UPDATE;
  IF NOT FOUND THEN
    result:=jsonb_build_object('ok',false,'message','Product was not found.');
    PERFORM complete_kiosk_operation(p_operation_id,p_token,result); RETURN result;
  END IF;
  IF product_row.current_stock < p_quantity THEN
    result:=jsonb_build_object('ok',false,'message','Not enough stock for this credit sale.');
    PERFORM complete_kiosk_operation(p_operation_id,p_token,result); RETURN result;
  END IF;
  SELECT COALESCE((SELECT p.unit_cost FROM purchases p WHERE p.product_id=p_product_id ORDER BY p.purchased_at DESC,p.id DESC LIMIT 1),0)::NUMERIC(14,2) INTO unit_cost;
  SELECT d.id INTO debtor_id FROM debtors d
  WHERE lower(trim(d.name))=lower(trim(p_debtor_name)) AND d.phone IS NOT DISTINCT FROM p_phone
  ORDER BY d.id LIMIT 1;
  IF debtor_id IS NULL THEN
    INSERT INTO debtors(name,phone,notes) VALUES(p_debtor_name,p_phone,p_note) RETURNING id INTO debtor_id;
  END IF;
  INSERT INTO sales(product_id,quantity,unit_price,unit_cost) VALUES(p_product_id,p_quantity,product_row.selling_price,unit_cost) RETURNING id INTO sale_id;
  INSERT INTO credit_sales(sale_id,debtor_id,amount_due) VALUES(sale_id,debtor_id,p_quantity*product_row.selling_price);
  UPDATE products SET current_stock=current_stock-p_quantity WHERE id=p_product_id;
  INSERT INTO inventory_movements(product_id,type,quantity,reference_id) VALUES(p_product_id,'SALE',-p_quantity,sale_id);
  result:=jsonb_build_object('ok',true,'message','Credit sale recorded for '||p_debtor_name);
  PERFORM complete_kiosk_operation(p_operation_id,p_token,result); RETURN result;
END;
$$;

UPDATE operation_requests
SET result=jsonb_build_object('ok',false,'message','This previous operation expired before completing. Retry the operation.'),
    completed_at=NOW(),lease_expires_at=NULL
WHERE completed_at IS NULL AND COALESCE(lease_expires_at,created_at)<NOW();

CREATE OR REPLACE VIEW shade_data_health AS
WITH stock AS (
 SELECT COUNT(*)::int AS bad FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id
 GROUP BY p.id HAVING p.current_stock<>COALESCE(SUM(m.quantity),0)
), refs AS (
 SELECT COUNT(*)::int AS bad FROM inventory_movements m
 WHERE (m.type='PURCHASE' AND NOT EXISTS(SELECT 1 FROM purchases p WHERE p.id=m.reference_id AND p.product_id=m.product_id))
 OR (m.type='SALE' AND NOT EXISTS(SELECT 1 FROM sales s WHERE s.id=m.reference_id AND s.product_id=m.product_id))
), credits AS (
 SELECT COUNT(*)::int AS bad FROM credit_sales cs LEFT JOIN sales s ON s.id=cs.sale_id
 WHERE s.id IS NULL OR cs.amount_due<>s.quantity*s.unit_price
), payments AS (
 SELECT COUNT(*)::int AS bad FROM credit_sales cs
 LEFT JOIN LATERAL(SELECT COALESCE(SUM(cp.amount),0)::numeric AS paid FROM credit_payments cp WHERE cp.credit_sale_id=cs.id)p ON true
 WHERE p.paid>cs.amount_due
), valuation AS (
 SELECT COUNT(*)::int AS bad FROM inventory_valuation v WHERE v.current_stock<>v.ledger_quantity
), closings AS (
 SELECT COUNT(*)::int AS bad FROM day_closings d
 WHERE d.sales_revenue<>d.cash_sales+d.credit_sales OR d.units_sold<0 OR d.stock_discrepancy_units<0
), operations AS (
 SELECT COUNT(*)::int AS bad FROM operation_requests o
 WHERE o.completed_at IS NULL AND o.created_at<NOW()-INTERVAL '15 minutes'
)
SELECT 'STOCK_LEDGER'::text AS check_name,CASE WHEN (SELECT COUNT(*) FROM stock)=0 THEN 'OK' ELSE 'ERROR' END AS status,
 CASE WHEN (SELECT COUNT(*) FROM stock)=0 THEN 'Every product stock count matches its inventory ledger.' ELSE (SELECT COUNT(*)::text FROM stock)||' product(s) have stock/ledger mismatches.' END AS detail
UNION ALL SELECT 'MOVEMENT_REFERENCES',CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM refs)=0 THEN 'OK' ELSE 'ERROR' END,
 CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM refs)=0 THEN 'Purchase and sale movements reference matching business records.' ELSE (SELECT COALESCE(SUM(bad),0)::text FROM refs)||' invalid inventory movement reference(s).' END
UNION ALL SELECT 'CREDIT_SALES',CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM credits)=0 THEN 'OK' ELSE 'ERROR' END,
 CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM credits)=0 THEN 'Credit sales match their underlying sale totals.' ELSE (SELECT COALESCE(SUM(bad),0)::text FROM credits)||' credit sale integrity error(s).' END
UNION ALL SELECT 'CREDIT_PAYMENTS',CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM payments)=0 THEN 'OK' ELSE 'ERROR' END,
 CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM payments)=0 THEN 'Recorded credit payments do not exceed amounts due.' ELSE (SELECT COALESCE(SUM(bad),0)::text FROM payments)||' overpayment error(s).' END
UNION ALL SELECT 'VALUATION_QUANTITY',CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM valuation)=0 THEN 'OK' ELSE 'ERROR' END,
 CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM valuation)=0 THEN 'WAC/FIFO valuation quantity agrees with the inventory ledger.' ELSE (SELECT COALESCE(SUM(bad),0)::text FROM valuation)||' valuation quantity mismatch(es).' END
UNION ALL SELECT 'DAY_CLOSINGS',CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM closings)=0 THEN 'OK' ELSE 'ERROR' END,
 CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM closings)=0 THEN 'Closed-day totals pass basic consistency checks.' ELSE (SELECT COALESCE(SUM(bad),0)::text FROM closings)||' day closing consistency error(s).' END
UNION ALL SELECT 'PENDING_OPERATIONS',CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM operations)=0 THEN 'OK' ELSE 'WARNING' END,
 CASE WHEN (SELECT COALESCE(SUM(bad),0) FROM operations)=0 THEN 'No operation request has been pending for more than 15 minutes.' ELSE (SELECT COALESCE(SUM(bad),0)::text FROM operations)||' operation request(s) have been pending for more than 15 minutes; inspect before retrying.' END;
