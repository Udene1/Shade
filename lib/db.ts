import { neon } from "@neondatabase/serverless";

let cachedSql: ReturnType<typeof neon> | null = null;

export const sql = ((strings: TemplateStringsArray, ...values: unknown[]): Promise<any[]> => {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error("DATABASE_URL is required for database access.");
  cachedSql ??= neon(connectionString);
  return cachedSql(strings, ...values) as Promise<any[]>;
});
