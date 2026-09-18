import fs from "node:fs";
import { execFileSync } from "node:child_process";

const file = process.argv[2];
if (!file) throw new Error("Usage: npm run db:restore -- <backup.json> CONFIRM");
if (process.argv[3] !== "CONFIRM") throw new Error("Restore is destructive. Repeat with the literal word CONFIRM.");
if (!process.env.DATABASE_URL) throw new Error("DATABASE_URL is required.");
if (!fs.existsSync(file)) throw new Error(`Backup file not found: ${file}`);

const backup = JSON.parse(fs.readFileSync(file, "utf8"));
if (backup.format !== "shade-backup-v1") throw new Error("Unsupported Shade backup format.");

const tables = [
  ["products", backup.products, ["id","name","category","selling_price","current_stock","minimum_stock","created_at"]],
  ["purchases", backup.purchases, ["id","product_id","quantity","unit_cost","supplier","purchased_at"]],
  ["sales", backup.sales, ["id","product_id","quantity","unit_price","unit_cost","sold_at"]],
  ["inventory_movements", backup.inventory_movements, ["id","product_id","type","quantity","reference_id","created_at","occurred_at","unit_cost","reason"]],
  ["debtors", backup.debtors, ["id","name","phone","notes","created_at"]],
  ["credit_sales", backup.credit_sales, ["id","sale_id","debtor_id","amount_due","created_at"]],
  ["credit_payments", backup.credit_payments, ["id","credit_sale_id","amount","paid_at","note"]],
  ["operation_requests", backup.operation_requests, ["id","operation_type","created_at","completed_at","result"]],
  ["day_closings", backup.day_closings, ["id","business_date","cash_sales","credit_sales","credit_payments","purchases","sales_revenue","units_sold","wac_gross_profit","fifo_gross_profit","stock_discrepancy_units","outstanding_debt","note","closed_at"]],
  ["inventory_valuation_settings", backup.inventory_valuation_settings, ["id","method","updated_at"]]
];
for (const [name, rows] of tables) {
  if (!Array.isArray(rows)) throw new Error(`Backup is missing ${name}.`);
}
const q = (v) => v === null || v === undefined ? "NULL" : typeof v === "number" ? String(v) : typeof v === "boolean" ? (v ? "TRUE" : "FALSE") : `'${String(v).replaceAll("'", "''")}'`;
const sql = ["BEGIN;", "SET CONSTRAINTS ALL DEFERRED;", "TRUNCATE TABLE credit_payments, credit_sales, inventory_movements, sales, purchases, debtors, operation_requests, day_closings, products RESTART IDENTITY CASCADE;"];
for (const [name, rows, cols] of tables) for (const row of rows) {
  const missing = cols.filter((c) => !(c in row));
  if (missing.length) throw new Error(`${name} row ${row.id ?? "?"} is missing: ${missing.join(", ")}`);
  sql.push(`INSERT INTO ${name} (${cols.join(",")}) VALUES (${cols.map((c) => q(row[c])).join(",")});`);
}
sql.push("COMMIT;");
execFileSync("psql", ["--dbname", process.env.DATABASE_URL, "--set", "ON_ERROR_STOP=1"], { input: sql.join("\n"), stdio: ["pipe","inherit","inherit"] });
console.log(`Restored Shade backup from ${file}.`);
