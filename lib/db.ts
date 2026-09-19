import { neon } from "@neondatabase/serverless";

type NeonSql = ReturnType<typeof neon>;

let cachedSql: NeonSql | null = null;

function getSql(): NeonSql {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error("DATABASE_URL is required for database access.");
  cachedSql ??= neon(connectionString);
  return cachedSql;
}

export const sql = Object.assign(
  ((strings: TemplateStringsArray, ...values: unknown[]) => getSql()(strings, ...values)) as NeonSql,
  {
    transaction: (...args: Parameters<NeonSql["transaction"]>) => getSql().transaction(...args),
  },
) as NeonSql;
