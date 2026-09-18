"use server";

import { revalidatePath } from "next/cache";
import { sql } from "@/lib/db";

export type ActionState = { ok: boolean; message: string };
function text(formData: FormData, key: string) { return String(formData.get(key) ?? "").trim(); }
function positiveInt(value: string) { const n = Number(value); return Number.isInteger(n) && n > 0 ? n : null; }
function nonNegativeMoney(value: string) { const n = Number(value); return Number.isFinite(n) && n >= 0 ? n : null; }
function operationId(formData: FormData) { const value = text(formData, "operation_id"); return value || crypto.randomUUID(); }

async function existingOperation(id: string): Promise<ActionState | null> {
  const rows = await sql`SELECT result FROM operation_requests WHERE id = ${id}::uuid` as Array<{ result: ActionState | null }>;
  if (!rows.length) return null;
  const result = rows[0].result as ActionState | null;
  return result ?? { ok: false, message: "This operation is still being processed. Refresh and check transaction history before retrying." };
}

export async function createProduct(_state: ActionState, formData: FormData): Promise<ActionState> {
  const name = text(formData, "name"), category = text(formData, "category") || null;
  const sellingPrice = nonNegativeMoney(text(formData, "selling_price"));
  const minimumStock = positiveInt(text(formData, "minimum_stock")) ?? 0;
  if (!name) return { ok: false, message: "Product name is required." };
  if (sellingPrice === null) return { ok: false, message: "Enter a valid selling price." };
  if (!process.env.DATABASE_URL) return { ok: false, message: "Database is not connected yet." };
  try { await sql`INSERT INTO products (name, category, selling_price, minimum_stock) VALUES (${name}, ${category}, ${sellingPrice}, ${minimumStock})`; revalidatePath("/"); return { ok: true, message: `${name} added.` }; }
  catch { return { ok: false, message: "Could not add the product." }; }
}

export async function updateProduct(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id"));
  const name = text(formData, "name"), category = text(formData, "category") || null;
  const sellingPrice = nonNegativeMoney(text(formData, "selling_price"));
  const minimumStock = positiveInt(text(formData, "minimum_stock")) ?? 0;
  if (!productId || !name || sellingPrice === null) return { ok: false, message: "Enter a valid product name and selling price." };
  try { const rows = await sql`UPDATE products SET name = ${name}, category = ${category}, selling_price = ${sellingPrice}, minimum_stock = ${minimumStock} WHERE id = ${productId} RETURNING id`; if (!rows.length) return { ok: false, message: "Product was not found." }; revalidatePath("/"); return { ok: true, message: `${name} updated. Historical sales remain unchanged.` }; } catch { return { ok: false, message: "Could not update the product." }; }
}

export async function recordPurchase(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id")), quantity = positiveInt(text(formData, "quantity")), unitCost = nonNegativeMoney(text(formData, "unit_cost")), supplier = text(formData, "supplier") || null, op = operationId(formData);
  if (!productId || !quantity || unitCost === null) return { ok: false, message: "Select a product and enter a valid quantity and cost." };
  try {
    const rows = await sql`WITH op AS (INSERT INTO operation_requests (id, operation_type) VALUES (${op}::uuid, 'PURCHASE') ON CONFLICT (id) DO NOTHING RETURNING id), updated AS (UPDATE products SET current_stock = current_stock + ${quantity} WHERE id = ${productId} AND EXISTS (SELECT 1 FROM op) RETURNING id), purchase AS (INSERT INTO purchases (product_id, quantity, unit_cost, supplier) SELECT id, ${quantity}, ${unitCost}, ${supplier} FROM updated RETURNING id, product_id), movement AS (INSERT INTO inventory_movements (product_id, type, quantity, reference_id) SELECT product_id, 'PURCHASE', ${quantity}, id FROM purchase RETURNING id), result AS (SELECT EXISTS(SELECT 1 FROM purchase) AS applied) UPDATE operation_requests SET completed_at = NOW(), result = jsonb_build_object('ok', true, 'message', 'Purchase recorded and stock increased.') WHERE id = ${op}::uuid AND EXISTS (SELECT 1 FROM result WHERE applied) RETURNING result`;
    if (!rows.length) { const prior = await existingOperation(op); if (prior) return prior; return { ok: false, message: "Product was not found." }; }
    revalidatePath("/"); return rows[0].result as ActionState;
  } catch { return { ok: false, message: "Could not record the purchase." }; }
}

export async function recordSale(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id")), quantity = positiveInt(text(formData, "quantity")), op = operationId(formData);
  if (!productId || !quantity) return { ok: false, message: "Select a product and enter a valid quantity." };
  try {
    const rows = await sql`WITH op AS (INSERT INTO operation_requests (id, operation_type) VALUES (${op}::uuid, 'SALE') ON CONFLICT (id) DO NOTHING RETURNING id), product AS (SELECT id, selling_price, current_stock, COALESCE((SELECT p.unit_cost FROM purchases p WHERE p.product_id = products.id ORDER BY p.purchased_at DESC, p.id DESC LIMIT 1), 0)::numeric AS unit_cost FROM products WHERE id = ${productId} FOR UPDATE), updated AS (UPDATE products SET current_stock = products.current_stock - ${quantity} FROM product WHERE products.id = product.id AND product.current_stock >= ${quantity} AND EXISTS (SELECT 1 FROM op) RETURNING products.id), sale AS (INSERT INTO sales (product_id, quantity, unit_price, unit_cost) SELECT product.id, ${quantity}, product.selling_price, product.unit_cost FROM product JOIN updated ON updated.id = product.id RETURNING id, product_id), movement AS (INSERT INTO inventory_movements (product_id, type, quantity, reference_id) SELECT product_id, 'SALE', -${quantity}, id FROM sale RETURNING id), result AS (SELECT EXISTS(SELECT 1 FROM sale) AS applied) UPDATE operation_requests SET completed_at = NOW(), result = CASE WHEN EXISTS (SELECT 1 FROM result WHERE applied) THEN jsonb_build_object('ok', true, 'message', 'Sale recorded and stock reduced.') ELSE jsonb_build_object('ok', false, 'message', 'Not enough stock or product was not found.') END WHERE id = ${op}::uuid AND EXISTS (SELECT 1 FROM op) RETURNING result`;
    if (!rows.length) { const prior = await existingOperation(op); if (prior) return prior; return { ok: false, message: "Could not start the sale operation." }; }
    revalidatePath("/"); return rows[0].result as ActionState;
  } catch { return { ok: false, message: "Could not record the sale." }; }
}

export async function recordCreditSale(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id")), quantity = positiveInt(text(formData, "quantity"));
  const debtorName = text(formData, "debtor_name"), phone = text(formData, "debtor_phone") || null, note = text(formData, "debtor_note") || null, op = operationId(formData);
  if (!productId || !quantity || !debtorName) return { ok: false, message: "Select a product, quantity and debtor name." };
  try {
    const rows = await sql`WITH op AS (INSERT INTO operation_requests (id, operation_type) VALUES (${op}::uuid, 'CREDIT_SALE') ON CONFLICT (id) DO NOTHING RETURNING id), product AS (SELECT id, selling_price, current_stock, COALESCE((SELECT p.unit_cost FROM purchases p WHERE p.product_id = products.id ORDER BY p.purchased_at DESC, p.id DESC LIMIT 1), 0)::numeric AS unit_cost FROM products WHERE id = ${productId} FOR UPDATE), updated AS (UPDATE products SET current_stock = products.current_stock - ${quantity} FROM product WHERE products.id = product.id AND product.current_stock >= ${quantity} AND EXISTS (SELECT 1 FROM op) RETURNING products.id), sale AS (INSERT INTO sales (product_id, quantity, unit_price, unit_cost) SELECT product.id, ${quantity}, product.selling_price, product.unit_cost FROM product JOIN updated ON updated.id = product.id RETURNING id, product_id, quantity, unit_price), existing_debtor AS (SELECT id FROM debtors WHERE lower(trim(name)) = lower(trim(${debtorName})) AND (phone IS NOT DISTINCT FROM ${phone}) ORDER BY id LIMIT 1), new_debtor AS (INSERT INTO debtors (name, phone, notes) SELECT ${debtorName}, ${phone}, ${note} WHERE EXISTS (SELECT 1 FROM sale) AND NOT EXISTS (SELECT 1 FROM existing_debtor) RETURNING id), debtor AS (SELECT id FROM existing_debtor UNION ALL SELECT id FROM new_debtor LIMIT 1), credit AS (INSERT INTO credit_sales (sale_id, debtor_id, amount_due) SELECT sale.id, debtor.id, sale.quantity * sale.unit_price FROM sale CROSS JOIN debtor RETURNING id, sale_id), movement AS (INSERT INTO inventory_movements (product_id, type, quantity, reference_id) SELECT sale.product_id, 'SALE', -sale.quantity, sale.id FROM sale JOIN credit ON credit.sale_id = sale.id RETURNING id), result AS (SELECT EXISTS(SELECT 1 FROM credit) AS applied) UPDATE operation_requests SET completed_at = NOW(), result = CASE WHEN EXISTS (SELECT 1 FROM result WHERE applied) THEN jsonb_build_object('ok', true, 'message', 'Credit sale recorded for ' || ${debtorName}) ELSE jsonb_build_object('ok', false, 'message', 'Not enough stock or product was not found.') END WHERE id = ${op}::uuid AND EXISTS (SELECT 1 FROM op) RETURNING result`;
    if (!rows.length) { const prior = await existingOperation(op); if (prior) return prior; return { ok: false, message: "Could not start the credit sale operation." }; }
    revalidatePath("/"); return rows[0].result as ActionState;
  } catch { return { ok: false, message: "Could not record the credit sale." }; }
}

export async function closeBusinessDay(_state: ActionState, formData: FormData): Promise<ActionState> {
  const businessDate = text(formData, "business_date") || new Date().toISOString().slice(0, 10);
  const note = text(formData, "note") || null;
  try {
    const rows = await sql`WITH existing AS (SELECT id FROM day_closings WHERE business_date = ${businessDate}::date), sales_day AS (SELECT COALESCE(SUM(s.quantity * s.unit_price) FILTER (WHERE cs.id IS NULL),0)::numeric AS cash_sales, COALESCE(SUM(s.quantity * s.unit_price) FILTER (WHERE cs.id IS NOT NULL),0)::numeric AS credit_sales, COALESCE(SUM(s.quantity),0)::int AS units_sold, COALESCE(SUM(CASE WHEN c.movement_id IS NOT NULL THEN c.wac_cost ELSE s.quantity * s.unit_cost END),0)::numeric AS wac_cost, COALESCE(SUM(CASE WHEN c.movement_id IS NOT NULL THEN c.fifo_cost ELSE s.quantity * s.unit_cost END),0)::numeric AS fifo_cost FROM sales s LEFT JOIN credit_sales cs ON cs.sale_id=s.id LEFT JOIN inventory_movements m ON m.reference_id=s.id AND m.type='SALE' LEFT JOIN inventory_sale_costs c ON c.movement_id=m.id WHERE s.sold_at::date=${businessDate}::date), purchases_day AS (SELECT COALESCE(SUM(quantity*unit_cost),0)::numeric AS amount FROM purchases WHERE purchased_at::date=${businessDate}::date), debt AS (SELECT COALESCE(SUM(amount_due),0)::numeric AS amount FROM credit_sales), mismatch AS (SELECT COUNT(*)::int AS count FROM (SELECT p.id FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id GROUP BY p.id HAVING p.current_stock <> COALESCE(SUM(m.quantity),0)) x), inserted AS (INSERT INTO day_closings (business_date,cash_sales,credit_sales,credit_payments,purchases,sales_revenue,units_sold,wac_gross_profit,fifo_gross_profit,stock_discrepancy_units,outstanding_debt,note) SELECT ${businessDate}::date,s.cash_sales,s.credit_sales,0,pu.amount,s.cash_sales+s.credit_sales,s.units_sold,(s.cash_sales+s.credit_sales)-s.wac_cost,(s.cash_sales+s.credit_sales)-s.fifo_cost,m.count,d.amount,${note} FROM sales_day s CROSS JOIN purchases_day pu CROSS JOIN debt d CROSS JOIN mismatch m WHERE NOT EXISTS (SELECT 1 FROM existing) RETURNING id) SELECT * FROM inserted`;
    if (!rows.length) return { ok: false, message: "That business day is already closed." };
    revalidatePath("/"); return { ok: true, message: `Business day ${businessDate} closed.` };
  } catch { return { ok: false, message: "Could not close the business day." }; }
}
