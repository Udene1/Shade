"use client";

import { useActionState } from "react";
import { createProduct, recordPurchase, recordSale, type ActionState } from "@/app/actions";

type Product = { id: number; name: string; selling_price: number; current_stock: number };

const initial: ActionState = { ok: false, message: "" };

function Result({ state }: { state: ActionState }) {
  if (!state.message) return null;
  return <p className={state.ok ? "success" : "error"}>{state.message}</p>;
}

export function KioskActions({ products }: { products: Product[] }) {
  const [saleState, saleAction, salePending] = useActionState(recordSale, initial);
  const [purchaseState, purchaseAction, purchasePending] = useActionState(recordPurchase, initial);
  const [productState, productAction, productPending] = useActionState(createProduct, initial);

  return (
    <div className="sections">
      <section className="card section">
        <h2>Sell</h2>
        <form action={saleAction} className="form">
          <label>Product<select name="product_id" required defaultValue=""><option value="" disabled>Select product</option>{products.map((p) => <option key={p.id} value={p.id}>{p.name} — {p.current_stock} in stock</option>)}</select></label>
          <label>Quantity<input name="quantity" type="number" min="1" inputMode="numeric" defaultValue="1" required /></label>
          <button type="submit" disabled={salePending}>{salePending ? "Recording…" : "SELL"}</button>
          <Result state={saleState} />
        </form>
      </section>

      <section className="card section">
        <h2>Buy stock</h2>
        <form action={purchaseAction} className="form">
          <label>Product<select name="product_id" required defaultValue=""><option value="" disabled>Select product</option>{products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label>
          <div className="form-grid"><label>Quantity<input name="quantity" type="number" min="1" inputMode="numeric" defaultValue="1" required /></label><label>Unit cost<input name="unit_cost" type="number" min="0" step="0.01" inputMode="decimal" required /></label></div>
          <label>Supplier <span className="muted">(optional)</span><input name="supplier" /></label>
          <button type="submit" disabled={purchasePending}>{purchasePending ? "Recording…" : "RECORD PURCHASE"}</button>
          <Result state={purchaseState} />
        </form>
      </section>

      <section className="card section">
        <h2>Add product</h2>
        <form action={productAction} className="form">
          <label>Name<input name="name" required /></label>
          <label>Category <span className="muted">(optional)</span><input name="category" /></label>
          <div className="form-grid"><label>Selling price<input name="selling_price" type="number" min="0" step="0.01" inputMode="decimal" required /></label><label>Minimum stock<input name="minimum_stock" type="number" min="0" inputMode="numeric" defaultValue="0" required /></label></div>
          <button type="submit" disabled={productPending}>{productPending ? "Adding…" : "ADD PRODUCT"}</button>
          <Result state={productState} />
        </form>
      </section>
    </div>
  );
}
