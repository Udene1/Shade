import { neon } from "@neondatabase/serverless";

type NeonSql = ReturnType<typeof neon>;

let cachedSql: NeonSql | null = null;

export const sql = ((strings: TemplateStringsArray, ...values: unknown[]) => {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error("DATABASE_URL is required for database access.");
  cachedSql ??= neon(connectionString);
  return cachedSql(strings, ...values);
}) as NeonSql;
