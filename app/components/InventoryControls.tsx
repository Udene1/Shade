"use client";

import { useActionState } from "react";
import { recordStockAdjustment, setValuationMethod } from "@/app/valuation-actions";
import type { ActionState } from "@/app/actions";

type Product = { id: number; name: string; current_stock: number };
type Reconciliation = { id: number; name: string; current_stock: number; ledger_stock: number };
const initial: ActionState = { ok: false, message: "" };

function Result({ state }: { state: ActionState }) {
  if (!state.message) return null;
  return <p className={state.ok ? "success" : "error"}>{state.message}</p>;
}

export function InventoryControls({ method, mismatches }: { method: string; mismatches: Reconciliation[] }) {
  const [methodState, methodAction, methodPending] = useActionState(setValuationMethod, initial);
  const [adjustState, adjustAction, adjustPending] = useActionState(recordStockAdjustment, initial);
  return (
    <>
      <section className="card section">
        <h2>Inventory valuation</h2>
        <p className="muted">The database recalculates inventory cost and sale cost from the ledger whenever you switch methods.</p>
        <form action={methodAction} className="form-grid">
          <select name="method" defaultValue={method} aria-label="Inventory valuation method">
            <option value="WAC">WAC — weighted average cost</option>
            <option value="FIFO">FIFO — first in, first out</option>
          </select>
          <button type="submit" disabled={methodPending}>{methodPending ? "Switching…" : `USE ${method}`}</button>
        </form>
        <Result state={methodState} />
      </section>
      <section className="card section">
        <h2>Stock reconciliation</h2>
        <p className="muted">Count the physical stock. Any difference becomes an explicit adjustment in the inventory ledger.</p>
        {mismatches.length === 0 ? <p className="success">Operational stock matches the inventory ledger.</p> : mismatches.map((p) => (
          <form action={adjustAction} className="form" key={p.id}>
            <strong>{p.name}</strong>
            <div className="muted">System: {p.current_stock} · Ledger: {p.ledger_stock}</div>
            <input type="hidden" name="product_id" value={p.id} />
            <label>Actual count<input name="actual_stock" type="number" min="0" inputMode="numeric" defaultValue={p.current_stock} required /></label>
            <label>Reason<input name="reason" placeholder="e.g. damaged / missing / recount" required /></label>
            <button type="submit" disabled={adjustPending}>{adjustPending ? "Reconciling…" : "RECONCILE STOCK"}</button>
          </form>
        ))}
        <Result state={adjustState} />
      </section>
    </>
  );
}
