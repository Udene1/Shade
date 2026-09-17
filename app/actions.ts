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

export async function createProduct(_state: ActionState, formData: FormData): Promise<ActionState> {
  const name = text(formData, "name");
  const category = text(formData, "category") || null;
  const sellingPrice = nonNegativeMoney(text(formData, "selling_price"));
  const minimumStock = positiveInt(text(formData, "minimum_stock")) ?? 0;

  if (!name) return { ok: false, message: "Product name is required." };
  if (sellingPrice === null) return { ok: false, message: "Enter a valid selling price." };

  if (!process.env.DATABASE_URL) return { ok: false, message: "Database is not connected yet." };

  try {
    await sql`
      INSERT INTO products (name, category, selling_price, minimum_stock)
      VALUES (${name}, ${category}, ${sellingPrice}, ${minimumStock})
    `;
    revalidatePath("/");
    return { ok: true, message: `${name} added.` };
  } catch (error) {
    const message = error instanceof Error && error.message.includes("duplicate")
      ? "A product with that name already exists."
      : "Could not add the product.";
    return { ok: false, message };
  }
}

export async function recordPurchase(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id"));
  const quantity = positiveInt(text(formData, "quantity"));
  const unitCost = nonNegativeMoney(text(formData, "unit_cost"));
  const supplier = text(formData, "supplier") || null;

  if (!productId || !quantity || unitCost === null) {
    return { ok: false, message: "Select a product and enter a valid quantity and cost." };
  }
  if (!process.env.DATABASE_URL) return { ok: false, message: "Database is not connected yet." };

  try {
    const rows = await sql`
      WITH updated AS (
        UPDATE products
        SET current_stock = current_stock + ${quantity},
            selling_price = selling_price
        WHERE id = ${productId}
        RETURNING id
      ), purchase AS (
        INSERT INTO purchases (product_id, quantity, unit_cost, supplier)
        SELECT id, ${quantity}, ${unitCost}, ${supplier}
        FROM updated
        RETURNING id, product_id
      )
      INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
      SELECT product_id, 'PURCHASE', ${quantity}, id
      FROM purchase
      RETURNING product_id
    `;
    if (rows.length === 0) return { ok: false, message: "Product was not found." };
    revalidatePath("/");
    return { ok: true, message: "Purchase recorded and stock increased." };
  } catch {
    return { ok: false, message: "Could not record the purchase." };
  }
}

export async function recordSale(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id"));
  const quantity = positiveInt(text(formData, "quantity"));

  if (!productId || !quantity) {
    return { ok: false, message: "Select a product and enter a valid quantity." };
  }
  if (!process.env.DATABASE_URL) return { ok: false, message: "Database is not connected yet." };

  try {
    const rows = await sql`
      WITH product AS (
        SELECT id, selling_price, current_stock,
               COALESCE((
                 SELECT p.unit_cost
                 FROM purchases p
                 WHERE p.product_id = products.id
                 ORDER BY p.purchased_at DESC, p.id DESC
                 LIMIT 1
               ), 0)::numeric AS unit_cost
        FROM products
        WHERE id = ${productId}
        FOR UPDATE
      ), updated AS (
        UPDATE products
        SET current_stock = products.current_stock - ${quantity}
        FROM product
        WHERE products.id = product.id
          AND product.current_stock >= ${quantity}
        RETURNING products.id
      ), sale AS (
        INSERT INTO sales (product_id, quantity, unit_price, unit_cost)
        SELECT product.id, ${quantity}, product.selling_price, product.unit_cost
        FROM product
        JOIN updated ON updated.id = product.id
        RETURNING id, product_id
      )
      INSERT INTO inventory_movements (product_id, type, quantity, reference_id)
      SELECT product_id, 'SALE', -${quantity}, id
      FROM sale
      RETURNING product_id
    `;

    if (rows.length === 0) {
      const product = await sql`SELECT current_stock FROM products WHERE id = ${productId}`;
      if (product.length === 0) return { ok: false, message: "Product was not found." };
      return { ok: false, message: `Not enough stock. Only ${product[0].current_stock} available.` };
    }

    revalidatePath("/");
    return { ok: true, message: "Sale recorded and stock reduced." };
  } catch {
    return { ok: false, message: "Could not record the sale." };
  }
}
