import { sql } from "@/lib/db";

export const dynamic = "force-dynamic";

export async function GET() {
  if (!process.env.DATABASE_URL) {
    return Response.json({ ok: false, message: "Database is not connected." }, { status: 503 });
  }

  try {
    const [products, purchases, sales, movements, debtors, creditSales, creditPayments, operationRequests, closings, valuationSettings, health] = await Promise.all([
      sql`SELECT * FROM products ORDER BY id`,
      sql`SELECT * FROM purchases ORDER BY id`,
      sql`SELECT * FROM sales ORDER BY id`,
      sql`SELECT * FROM inventory_movements ORDER BY id`,
      sql`SELECT * FROM debtors ORDER BY id`,
      sql`SELECT * FROM credit_sales ORDER BY id`,
      sql`SELECT * FROM credit_payments ORDER BY id`,
      sql`SELECT * FROM operation_requests ORDER BY created_at, id`,
      sql`SELECT * FROM day_closings ORDER BY business_date`,\n      sql`SELECT * FROM inventory_valuation_settings WHERE id = 1`,\n      sql`SELECT check_name, status, detail FROM shade_data_health ORDER BY check_name`,
    ]);

    const backup = {
      format: "shade-backup-v1",
      exported_at: new Date().toISOString(),
      products,
      purchases,
      sales,
      inventory_movements: movements,
      debtors,
      credit_sales: creditSales,
      credit_payments: creditPayments,
      operation_requests: operationRequests,
      day_closings: closings,\n      inventory_valuation_settings: valuationSettings,\n      health_snapshot: health,
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
