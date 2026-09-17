"use server";

import { revalidatePath } from "next/cache";
import { sql } from "@/lib/db";

export type ActionState = { ok: boolean; message: string };

function text(formData: FormData, key: string) { return String(formData.get(key) ?? "").trim(); }
function positiveInt(value: string) { const n = Number(value); return Number.isInteger(n) && n > 0 ? n : null; }
function nonNegativeMoney(value: string) { const n = Number(value); return Number.isFinite(n) && n >= 0 ? n : null; }

export async function createProduct(_state: ActionState, formData: FormData): Promise<ActionState> {
  const name = text(formData, "name"), category = text(formData, "category") || null;
  const sellingPrice = nonNegativeMoney(text(formData, "selling_price"));
  const minimumStock = positiveInt(text(formData, "minimum_stock")) ?? 0;
  if (!name) return { ok: false, message: "Product name is required." };
  if (sellingPrice === null) return { ok: false, message: "Enter a valid selling price." };
  if (!process.env.DATABASE_URL) return { ok: false, message: "Database is not connected yet." };
  try { await sql`INSERT INTO products (name, category, selling_price, minimum_stock) VALUES (${name}, ${category}, ${sellingPrice}, ${minimumStock})`; revalidatePath("/"); return { ok: true, message: `${name} added.` }; }
  catch (error) { return { ok: false, message: error instanceof Error && error.message.includes("duplicate") ? "A product with that name already exists." : "Could not add the product." }; }
}

export async function recordPurchase(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id")), quantity = positiveInt(text(formData, "quantity")), unitCost = nonNegativeMoney(text(formData, "unit_cost")), supplier = text(formData, "supplier") || null;
  if (!productId || !quantity || unitCost === null) return { ok: false, message: "Select a product and enter a valid quantity and cost." };
  if (!process.env.DATABASE_URL) return { ok: false, message: "Database is not connected yet." };
  try {
    const rows = await sql`WITH updated AS (UPDATE products SET current_stock = current_stock + ${quantity} WHERE id = ${productId} RETURNING id), purchase AS (INSERT INTO purchases (product_id, quantity, unit_cost, supplier) SELECT id, ${quantity}, ${unitCost}, ${supplier} FROM updated RETURNING id, product_id) INSERT INTO inventory_movements (product_id, type, quantity, reference_id) SELECT product_id, 'PURCHASE', ${quantity}, id FROM purchase RETURNING product_id`;
    if (!rows.length) return { ok: false, message: "Product was not found." };
    revalidatePath("/"); return { ok: true, message: "Purchase recorded and stock increased." };
  } catch { return { ok: false, message: "Could not record the purchase." }; }
}

async function createSale(productId: number, quantity: number) {
  return sql`WITH product AS (SELECT id, selling_price, current_stock, COALESCE((SELECT p.unit_cost FROM purchases p WHERE p.product_id = products.id ORDER BY p.purchased_at DESC, p.id DESC LIMIT 1), 0)::numeric AS unit_cost FROM products WHERE id = ${productId} FOR UPDATE), updated AS (UPDATE products SET current_stock = products.current_stock - ${quantity} FROM product WHERE products.id = product.id AND product.current_stock >= ${quantity} RETURNING products.id), sale AS (INSERT INTO sales (product_id, quantity, unit_price, unit_cost) SELECT product.id, ${quantity}, product.selling_price, product.unit_cost FROM product JOIN updated ON updated.id = product.id RETURNING id, product_id) INSERT INTO inventory_movements (product_id, type, quantity, reference_id) SELECT product_id, 'SALE', -${quantity}, id FROM sale RETURNING product_id, reference_id`;
}

export async function recordSale(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id")), quantity = positiveInt(text(formData, "quantity"));
  if (!productId || !quantity) return { ok: false, message: "Select a product and enter a valid quantity." };
  if (!process.env.DATABASE_URL) return { ok: false, message: "Database is not connected yet." };
  try {
    const rows = await createSale(productId, quantity);
    if (!rows.length) { const product = await sql`SELECT current_stock FROM products WHERE id = ${productId}`; if (!product.length) return { ok: false, message: "Product was not found." }; return { ok: false, message: `Not enough stock. Only ${product[0].current_stock} available.` }; }
    revalidatePath("/"); return { ok: true, message: "Sale recorded and stock reduced." };
  } catch { return { ok: false, message: "Could not record the sale." }; }
}

export async function recordCreditSale(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id")), quantity = positiveInt(text(formData, "quantity"));
  const debtorName = text(formData, "debtor_name"), phone = text(formData, "debtor_phone") || null, note = text(formData, "debtor_note") || null;
  if (!productId || !quantity || !debtorName) return { ok: false, message: "Select a product, quantity and debtor name." };
  if (!process.env.DATABASE_URL) return { ok: false, message: "Database is not connected yet." };
  try {
    const rows = await sql`
      WITH product AS (SELECT id, selling_price, current_stock, COALESCE((SELECT p.unit_cost FROM purchases p WHERE p.product_id = products.id ORDER BY p.purchased_at DESC, p.id DESC LIMIT 1), 0)::numeric AS unit_cost FROM products WHERE id = ${productId} FOR UPDATE),
      updated AS (UPDATE products SET current_stock = products.current_stock - ${quantity} FROM product WHERE products.id = product.id AND product.current_stock >= ${quantity} RETURNING products.id),
      sale AS (INSERT INTO sales (product_id, quantity, unit_price, unit_cost) SELECT product.id, ${quantity}, product.selling_price, product.unit_cost FROM product JOIN updated ON updated.id = product.id RETURNING id, product_id, quantity, unit_price),
      existing_debtor AS (SELECT id FROM debtors WHERE lower(trim(name)) = lower(trim(${debtorName})) AND (phone IS NOT DISTINCT FROM ${phone}) ORDER BY id LIMIT 1),
      new_debtor AS (INSERT INTO debtors (name, phone, notes) SELECT ${debtorName}, ${phone}, ${note} WHERE EXISTS (SELECT 1 FROM sale) AND NOT EXISTS (SELECT 1 FROM existing_debtor) RETURNING id),
      debtor AS (SELECT id FROM existing_debtor UNION ALL SELECT id FROM new_debtor LIMIT 1),
      credit AS (INSERT INTO credit_sales (sale_id, debtor_id, amount_due) SELECT sale.id, debtor.id, sale.quantity * sale.unit_price FROM sale CROSS JOIN debtor RETURNING id, sale_id)
      INSERT INTO inventory_movements (product_id, type, quantity, reference_id) SELECT sale.product_id, 'SALE', -sale.quantity, sale.id FROM sale JOIN credit ON credit.sale_id = sale.id RETURNING product_id`;
    if (!rows.length) { const product = await sql`SELECT current_stock FROM products WHERE id = ${productId}`; if (!product.length) return { ok: false, message: "Product was not found." }; return { ok: false, message: `Not enough stock. Only ${product[0].current_stock} available.` }; }
    revalidatePath("/"); return { ok: true, message: `Credit sale recorded for ${debtorName}.` };
  } catch { return { ok: false, message: "Could not record the credit sale." }; }
}

export async function recordCreditPayment(_state: ActionState, formData: FormData): Promise<ActionState> {
  const creditSaleId = positiveInt(text(formData, "credit_sale_id")), amount = nonNegativeMoney(text(formData, "amount")), note = text(formData, "note") || null;
  if (!creditSaleId || amount === null || amount <= 0) return { ok: false, message: "Enter a valid payment amount." };
  if (!process.env.DATABASE_URL) return { ok: false, message: "Database is not connected yet." };
  try {
    const rows = await sql`WITH debt AS (SELECT cs.id, cs.amount_due - COALESCE((SELECT SUM(cp.amount) FROM credit_payments cp WHERE cp.credit_sale_id = cs.id), 0) AS balance FROM credit_sales cs WHERE cs.id = ${creditSaleId} FOR UPDATE) INSERT INTO credit_payments (credit_sale_id, amount, note) SELECT id, ${amount}, ${note} FROM debt WHERE ${amount} <= balance AND balance > 0 RETURNING id`;
    if (!rows.length) return { ok: false, message: "Payment exceeds the outstanding balance or the debt was not found." };
    revalidatePath("/"); return { ok: true, message: "Payment recorded." };
  } catch { return { ok: false, message: "Could not record the payment." }; }
}
