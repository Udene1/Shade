import { readFile, readdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { Pool } from "@neondatabase/serverless";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const schemaPath = join(root, "db", "schema.sql");
const migrationsDir = join(root, "db", "migrations");

if (!process.env.DATABASE_URL) {
  throw new Error("DATABASE_URL is required to run database migrations");
}

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const client = await pool.connect();

try {
  await client.query("SELECT pg_advisory_lock(hashtext('shade:migrations'))");

  await client.query(await readFile(schemaPath, "utf8"));

  await client.query(`
    CREATE TABLE IF NOT EXISTS shade_schema_migrations (
      filename TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  const files = (await readdir(migrationsDir))
    .filter((name) => /^\d+_.*\.sql$/.test(name))
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));

  const appliedRows = await client.query(
    "SELECT filename FROM shade_schema_migrations ORDER BY filename",
  );
  const applied = new Set(appliedRows.rows.map((row) => row.filename));

  for (const filename of files) {
    if (applied.has(filename)) continue;

    const migration = await readFile(join(migrationsDir, filename), "utf8");
    await client.query("BEGIN");
    try {
      await client.query(migration);
      await client.query(
        "INSERT INTO shade_schema_migrations (filename) VALUES ($1)",
        [filename],
      );
      await client.query("COMMIT");
      console.log(`Applied ${filename}`);
    } catch (error) {
      await client.query("ROLLBACK");
      throw new Error(`Migration ${filename} failed: ${error.message}`, {
        cause: error,
      });
    }
  }

  console.log(`Database migration complete (${files.length} migrations tracked).`);
} finally {
  await client.query("SELECT pg_advisory_unlock(hashtext('shade:migrations'))").catch(() => {});
  client.release();
  await pool.end();
}
