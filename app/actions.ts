"use server";

import { revalidatePath } from "next/cache";
import { sql } from "@/lib/db";

export type ActionState = { ok: boolean; message: string };

function text(formData: FormData, key: string) {
  return String(formData.get(key) ?? "").trim();
}
function positiveInt(value: string) {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}
function nonNegativeMoney(value: string) {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : null;
}
function operationId(formData: FormData) {
  const value = text(formData, "operation_id");
  return value || crypto.randomUUID();
}
function operationToken() {
  return crypto.randomUUID();
}
function actionResult(rows: Array<Record<string, unknown>>, key: string): ActionState {
  const result = rows[0]?.[key];
  if (!result || typeof result !== "object") {
    return { ok: false, message: "The database did not return an operation result." };
  }
  return result as ActionState;
}

export async function createProduct(_state: ActionState, formData: FormData): Promise<ActionState> {
  const name = text(formData, "name"), category = text(formData, "category") || null;
  const sellingPrice = nonNegativeMoney(text(formData, "selling_price"));
  const minimumStock = positiveInt(text(formData, "minimum_stock")) ?? 0;
  if (!name) return { ok: false, message: "Product name is required." };
  if (sellingPrice === null) return { ok: false, message: "Enter a valid selling price." };
  if (!process.env.DATABASE_URL) return { ok: false, message: "Database is not connected yet." };
  try {
    await sql`INSERT INTO products (name, category, selling_price, minimum_stock) VALUES (${name}, ${category}, ${sellingPrice}, ${minimumStock})`;
    revalidatePath("/");
    return { ok: true, message: `${name} added.` };
  } catch (error) {
    console.error("createProduct failed", error);
    return { ok: false, message: "Could not add the product." };
  }
}

export async function updateProduct(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id"));
  const name = text(formData, "name"), category = text(formData, "category") || null;
  const sellingPrice = nonNegativeMoney(text(formData, "selling_price"));
  const minimumStock = positiveInt(text(formData, "minimum_stock")) ?? 0;
  if (!productId || !name || sellingPrice === null) return { ok: false, message: "Enter a valid product name and selling price." };
  try {
    const rows = await sql`UPDATE products SET name = ${name}, category = ${category}, selling_price = ${sellingPrice}, minimum_stock = ${minimumStock} WHERE id = ${productId} RETURNING id`;
    if (!rows.length) return { ok: false, message: "Product was not found." };
    revalidatePath("/");
    return { ok: true, message: `${name} updated. Historical sales remain unchanged.` };
  } catch (error) {
    console.error("updateProduct failed", error);
    return { ok: false, message: "Could not update the product." };
  }
}

export async function recordPurchase(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id"));
  const quantity = positiveInt(text(formData, "quantity"));
  const unitCost = nonNegativeMoney(text(formData, "unit_cost"));
  const supplier = text(formData, "supplier") || null;
  const op = operationId(formData);
  const token = operationToken();
  if (!productId || !quantity || unitCost === null) return { ok: false, message: "Select a product and enter a valid quantity and cost." };
  try {
    const rows = await sql`SELECT record_purchase_operation(${op}::uuid, ${productId}::bigint, ${quantity}::integer, ${unitCost}::numeric, ${supplier}, ${token}::uuid) AS result`;
    revalidatePath("/");
    return actionResult(rows as Array<Record<string, unknown>>, "result");
  } catch (error) {
    console.error("recordPurchase failed", { operationId: op, error });
    return { ok: false, message: "Could not record the purchase. No stock change was committed." };
  }
}

export async function recordSale(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id"));
  const quantity = positiveInt(text(formData, "quantity"));
  const op = operationId(formData);
  const token = operationToken();
  if (!productId || !quantity) return { ok: false, message: "Select a product and enter a valid quantity." };
  try {
    const rows = await sql`SELECT record_sale_operation(${op}::uuid, ${productId}::bigint, ${quantity}::integer, ${token}::uuid) AS result`;
    revalidatePath("/");
    return actionResult(rows as Array<Record<string, unknown>>, "result");
  } catch (error) {
    console.error("recordSale failed", { operationId: op, error });
    return { ok: false, message: "Could not record the sale. No stock change was committed." };
  }
}

export async function recordCreditSale(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id"));
  const quantity = positiveInt(text(formData, "quantity"));
  const debtorName = text(formData, "debtor_name");
  const phone = text(formData, "debtor_phone") || null;
  const note = text(formData, "debtor_note") || null;
  const op = operationId(formData);
  const token = operationToken();
  if (!productId || !quantity || !debtorName) return { ok: false, message: "Select a product, quantity and debtor name." };
  try {
    const rows = await sql`SELECT record_credit_sale_operation(${op}::uuid, ${productId}::bigint, ${quantity}::integer, ${debtorName}, ${phone}, ${note}, ${token}::uuid) AS result`;
    revalidatePath("/");
    return actionResult(rows as Array<Record<string, unknown>>, "result");
  } catch (error) {
    console.error("recordCreditSale failed", { operationId: op, error });
    return { ok: false, message: "Could not record the credit sale. No stock or debt change was committed." };
  }
}

export async function closeBusinessDay(_state: ActionState, formData: FormData): Promise<ActionState> {
  const businessDate = text(formData, "business_date") || new Date().toISOString().slice(0, 10);
  const note = text(formData, "note") || null;
  try {
    const rows = await sql`WITH existing AS (SELECT id FROM day_closings WHERE business_date = ${businessDate}::date), sales_day AS (SELECT COALESCE(SUM(s.quantity * s.unit_price) FILTER (WHERE cs.id IS NULL),0)::numeric AS cash_sales, COALESCE(SUM(s.quantity * s.unit_price) FILTER (WHERE cs.id IS NOT NULL),0)::numeric AS credit_sales, COALESCE(SUM(s.quantity),0)::int AS units_sold, COALESCE(SUM(CASE WHEN c.movement_id IS NOT NULL THEN c.wac_cost ELSE s.quantity * s.unit_cost END),0)::numeric AS wac_cost, COALESCE(SUM(CASE WHEN c.movement_id IS NOT NULL THEN c.fifo_cost ELSE s.quantity * s.unit_cost END),0)::numeric AS fifo_cost FROM sales s LEFT JOIN credit_sales cs ON cs.sale_id=s.id LEFT JOIN inventory_movements m ON m.reference_id=s.id AND m.type='SALE' LEFT JOIN inventory_sale_costs c ON c.movement_id=m.id WHERE s.sold_at::date=${businessDate}::date), purchases_day AS (SELECT COALESCE(SUM(quantity*unit_cost),0)::numeric AS amount FROM purchases WHERE purchased_at::date=${businessDate}::date), debt AS (SELECT COALESCE(SUM(amount_due),0)::numeric AS amount FROM credit_sales), mismatch AS (SELECT COUNT(*)::int AS count FROM (SELECT p.id FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id GROUP BY p.id HAVING p.current_stock <> COALESCE(SUM(m.quantity),0)) x), inserted AS (INSERT INTO day_closings (business_date,cash_sales,credit_sales,credit_payments,purchases,sales_revenue,units_sold,wac_gross_profit,fifo_gross_profit,stock_discrepancy_units,outstanding_debt,note) SELECT ${businessDate}::date,s.cash_sales,s.credit_sales,0,pu.amount,s.cash_sales+s.credit_sales,s.units_sold,(s.cash_sales+s.credit_sales)-s.wac_cost,(s.cash_sales+s.credit_sales)-s.fifo_cost,m.count,d.amount,${note} FROM sales_day s CROSS JOIN purchases_day pu CROSS JOIN debt d CROSS JOIN mismatch m WHERE NOT EXISTS (SELECT 1 FROM existing) RETURNING id) SELECT * FROM inserted`;
    if (!rows.length) return { ok: false, message: "That business day is already closed." };
    revalidatePath("/");
    return { ok: true, message: `Business day ${businessDate} closed.` };
  } catch (error) {
    console.error("closeBusinessDay failed", error);
    return { ok: false, message: "Could not close the business day." };
  }
}
