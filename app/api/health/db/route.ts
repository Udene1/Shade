import { NextResponse } from "next/server";
import { sql } from "@/lib/db";

const REQUIRED_TABLES = [
  "products",
  "purchases",
  "sales",
  "inventory_movements",
  "inventory_valuation",
  "inventory_valuation_settings",
  "credit_sales",
  "credit_payments",
  "inventory_decision_signals",
];

export async function GET() {
  if (!process.env.DATABASE_URL) {
    return NextResponse.json(
      { ok: false, status: "NOT_CONFIGURED", database: "DATABASE_URL is not configured" },
      { status: 503 },
    );
  }

  try {
    const databaseRows = await sql`SELECT current_database() AS database, current_timestamp AS checked_at`;
    const tableRows = await sql`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = ANY(${REQUIRED_TABLES})
      ORDER BY table_name
    `;
    const present = tableRows.map((row) => String(row.table_name));
    const missing = REQUIRED_TABLES.filter((table) => !present.includes(table));

    if (missing.length > 0) {
      return NextResponse.json(
        { ok: false, status: "MIGRATION_INCOMPLETE", database: String(databaseRows[0]?.database ?? ""), missing_tables: missing },
        { status: 503 },
      );
    }

    return NextResponse.json({
      ok: true,
      status: "READY",
      database: String(databaseRows[0]?.database ?? ""),
      checked_at: databaseRows[0]?.checked_at,
      tables: present,
    });
  } catch {
    return NextResponse.json(
      { ok: false, status: "UNAVAILABLE", database: "PostgreSQL connection failed" },
      { status: 503 },
    );
  }
}
