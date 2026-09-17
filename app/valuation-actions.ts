"use server";

import { revalidatePath } from "next/cache";
import { sql } from "@/lib/db";
import type { ActionState } from "@/app/actions";

function text(formData: FormData, key: string) { return String(formData.get(key) ?? "").trim(); }
function positiveInt(value: string) { const n = Number(value); return Number.isInteger(n) && n > 0 ? n : null; }

export async function setValuationMethod(_state: ActionState, formData: FormData): Promise<ActionState> {
  const method = text(formData, "method");
  if (method !== "WAC" && method !== "FIFO") return { ok: false, message: "Choose WAC or FIFO." };
  if (!process.env.DATABASE_URL) return { ok: false, message: "Database is not connected yet." };
  try {
    await sql`UPDATE inventory_valuation_settings SET method = ${method}, updated_at = NOW() WHERE id = 1`;
    revalidatePath("/");
    return { ok: true, message: `Inventory valuation switched to ${method}.` };
  } catch { return { ok: false, message: "Could not change the valuation method." }; }
}

export async function recordStockAdjustment(_state: ActionState, formData: FormData): Promise<ActionState> {
  const productId = positiveInt(text(formData, "product_id"));
  const actualStock = Number(text(formData, "actual_stock"));
  const reason = text(formData, "reason");
  if (!productId || !Number.isInteger(actualStock) || actualStock < 0 || !reason) return { ok: false, message: "Select a product, enter a non-negative stock count, and give a reason." };
  if (!process.env.DATABASE_URL) return { ok: false, message: "Database is not connected yet." };
  try {
    const rows = await sql`
      WITH product AS (SELECT id, current_stock FROM products WHERE id = ${productId} FOR UPDATE),
      ledger AS (
        SELECT product.id, COALESCE(SUM(m.quantity), 0)::int AS ledger_stock
        FROM product LEFT JOIN inventory_movements m ON m.product_id = product.id
        GROUP BY product.id
      ),
      updated AS (
        UPDATE products p SET current_stock = ${actualStock}
        FROM ledger l WHERE p.id = l.id RETURNING p.id
      )
      INSERT INTO inventory_movements (product_id, type, quantity, reference_id, unit_cost, reason)
      SELECT l.id, 'ADJUSTMENT', ${actualStock} - l.ledger_stock, NULL,
        COALESCE((SELECT unit_cost FROM inventory_movements WHERE product_id = l.id AND unit_cost IS NOT NULL ORDER BY created_at DESC, id DESC LIMIT 1), 0),
        ${reason}
      FROM ledger l JOIN updated u ON u.id = l.id
      WHERE ${actualStock} <> l.ledger_stock
      RETURNING product_id`;
    if (!rows.length) {
      const product = await sql`SELECT id FROM products WHERE id = ${productId}`;
      if (!product.length) return { ok: false, message: "Product was not found." };
      return { ok: true, message: "Stock already matched the ledger; no adjustment was needed." };
    }
    revalidatePath("/");
    return { ok: true, message: "Stock reconciled and the difference was recorded in the ledger." };
  } catch { return { ok: false, message: "Could not reconcile the stock." }; }
}
