import Link from "next/link";
import { sql } from "@/lib/db";
import { DayClosing, TransactionHistory, type HistoryRow } from "@/app/components/KioskOperations";

export const dynamic = "force-dynamic";

export default async function OperationsPage() {
  const rows = process.env.DATABASE_URL ? await sql`SELECT transaction_type, transaction_id, occurred_at, product_name, quantity, unit_price, unit_cost, amount, counterparty, note FROM transaction_history ORDER BY occurred_at DESC, transaction_id DESC LIMIT 1000` : [];
  const history = rows as HistoryRow[];
  const today = new Date().toISOString().slice(0, 10);
  return <main><div className="page-heading"><div><div className="eyebrow">RECORDS & CLOSEOUT</div><h1>Transactions</h1><p>Review business events, close the day, or export a backup of your data.</p></div><a className="button" href="/api/export">Back up data</a></div><DayClosing defaultDate={today} /><TransactionHistory rows={history} /></main>;
}
