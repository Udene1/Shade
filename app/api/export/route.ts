import { sql } from "@/lib/db";

export const dynamic = "force-dynamic";

export async function GET() {
  if (!process.env.DATABASE_URL) {
    return Response.json({ ok: false, message: "Database is not connected." }, { status: 503 });
  }

  try {
    const [products, purchases, sales, debtors, creditSales, creditPayments, closings] = await Promise.all([
      sql`SELECT * FROM products ORDER BY id`,
      sql`SELECT * FROM purchases ORDER BY id`,
      sql`SELECT * FROM sales ORDER BY id`,
      sql`SELECT * FROM debtors ORDER BY id`,
      sql`SELECT * FROM credit_sales ORDER BY id`,
      sql`SELECT * FROM credit_payments ORDER BY id`,
      sql`SELECT * FROM day_closings ORDER BY business_date`,
    ]);

    const backup = {
      exported_at: new Date().toISOString(),
      products,
      purchases,
      sales,
      debtors,
      credit_sales: creditSales,
      credit_payments: creditPayments,
      day_closings: closings,
    };

    return new Response(JSON.stringify(backup, null, 2), {
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Content-Disposition": `attachment; filename="shade-backup-${new Date().toISOString().slice(0, 10)}.json"`,
        "Cache-Control": "no-store",
      },
    });
  } catch {
    return Response.json({ ok: false, message: "Could not create the backup." }, { status: 500 });
  }
}
