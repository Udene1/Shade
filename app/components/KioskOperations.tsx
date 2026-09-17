"use client";

import { useActionState, useState } from "react";
import { closeBusinessDay, type ActionState } from "@/app/actions";

const initial: ActionState = { ok: false, message: "" };

function OpId() {
  const [id] = useState(() => crypto.randomUUID());
  return <input type="hidden" name="operation_id" value={id} />;
}

export function DayClosing({ defaultDate }: { defaultDate: string }) {
  const [state, action, pending] = useActionState(closeBusinessDay, initial);
  return <section className="card section"><h2>Close the day</h2><p className="muted">Locks the recorded daily totals into a historical snapshot. It does not alter sales, stock or debt.</p><form action={action} className="form"><label>Business date<input type="date" name="business_date" defaultValue={defaultDate} required /></label><label>Note <span className="muted">(optional)</span><input name="note" placeholder="Anything to remember about today" /></label><OpId /><button type="submit" disabled={pending}>{pending ? "Closing…" : "CLOSE BUSINESS DAY"}</button>{state.message && <p className={state.ok ? "success" : "error"}>{state.message}</p>}</form></section>;
}

export type HistoryRow = { transaction_type: string; transaction_id: number; occurred_at: string; product_name: string; quantity: number; unit_price: number | string | null; unit_cost: number | string | null; amount: number | string; counterparty: string | null; note: string | null };

export function TransactionHistory({ rows }: { rows: HistoryRow[] }) {
  return <section className="card section"><div className="row"><div><h2>Transaction history</h2><p className="muted">Append-only business events. Corrections should be recorded as new events rather than rewriting history.</p></div></div>{rows.length === 0 ? <p className="muted">No transactions yet.</p> : <div className="history">{rows.slice(0, 50).map((r) => <div className="history-row" key={`${r.transaction_type}-${r.transaction_id}`}><div><strong>{r.transaction_type.replaceAll("_", " ")}</strong><div className="muted">{new Date(r.occurred_at).toLocaleString()} · {r.product_name}{r.quantity ? ` · ${r.quantity} units` : ""}</div></div><div><strong>₦{Number(r.amount).toLocaleString()}</strong>{r.counterparty && <div className="muted">{r.counterparty}</div>}</div></div>)}</div>}</section>;
}
