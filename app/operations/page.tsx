import Link from "next/link";
import { sql } from "@/lib/db";
import { DayClosing, TransactionHistory, type HistoryRow } from "@/app/components/KioskOperations";

export const dynamic = "force-dynamic";

export default async function OperationsPage() {
  const rows = process.env.DATABASE_URL ? await sql`SELECT transaction_type, transaction_id, occurred_at, product_name, quantity, unit_price, unit_cost, amount, counterparty, note FROM transaction_history ORDER BY occurred_at DESC, transaction_id DESC LIMIT 1000` : [];
  const history = rows as HistoryRow[];
  const today = new Date().toISOString().slice(0, 10);
  return <main><header className="header"><div><h1>Shade operations</h1><p>Transaction history and end-of-day controls.</p></div><div className="row"><a className="button" href="/api/export">BACK UP DATA</a><Link href="/">Back to kiosk</Link></div></header><DayClosing defaultDate={today} /><TransactionHistory rows={history} /></main>;
}
