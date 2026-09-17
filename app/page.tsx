import { sql } from "@/lib/db";

async function getDashboard() {
  if (!process.env.DATABASE_URL) {
    return { connected: false, metrics: null, products: [] as Array<{ name: string; stock: number; sold: number; revenue: number; profit: number }> };
  }

  try {
    const metrics = await sql`
      SELECT
        COALESCE(SUM(s.quantity * s.unit_price), 0)::numeric AS revenue,
        COALESCE(SUM(s.quantity * s.unit_cost), 0)::numeric AS cost,
        COALESCE(SUM(s.quantity), 0)::int AS units
      FROM sales s
      WHERE s.sold_at >= CURRENT_DATE
    `;
    const products = await sql`
      SELECT p.name,
             p.current_stock AS stock,
             COALESCE(SUM(s.quantity), 0)::int AS sold,
             COALESCE(SUM(s.quantity * s.unit_price), 0)::numeric AS revenue,
             COALESCE(SUM(s.quantity * (s.unit_price - s.unit_cost)), 0)::numeric AS profit
      FROM products p
      LEFT JOIN sales s ON s.product_id = p.id
      GROUP BY p.id
      ORDER BY sold DESC, profit DESC
      LIMIT 8
    `;
    return { connected: true, metrics: metrics[0], products };
  } catch {
    return { connected: false, metrics: null, products: [] };
  }
}

export default async function Home() {
  const data = await getDashboard();
  const revenue = Number(data.metrics?.revenue ?? 0);
  const cost = Number(data.metrics?.cost ?? 0);
  const profit = revenue - cost;
  const units = Number(data.metrics?.units ?? 0);

  return (
    <main>
      <header className="header">
        <div>
          <h1>Shade</h1>
          <p>Stock, sales and the money tied up in your kiosk.</p>
        </div>
        <span className="badge">{data.connected ? "Database connected" : "Database not configured"}</span>
      </header>

      <section className="grid">
        <div className="card"><div className="metric-label">Today&apos;s sales</div><div className="metric">₦{revenue.toLocaleString()}</div></div>
        <div className="card"><div className="metric-label">Gross profit</div><div className="metric">₦{profit.toLocaleString()}</div></div>
        <div className="card"><div className="metric-label">Units sold</div><div className="metric">{units.toLocaleString()}</div></div>
        <div className="card"><div className="metric-label">Stock value</div><div className="metric">₦0</div></div>
      </section>

      <div className="sections">
        <section className="card section">
          <h2>Best sellers</h2>
          {data.products.length === 0 ? <p className="muted">Record sales to see which products move fastest.</p> : data.products.map((p) => (
            <div className="row" key={p.name}>
              <div><strong>{p.name}</strong><div className="muted">{p.sold} sold · {p.stock} in stock</div></div>
              <strong>₦{Number(p.profit).toLocaleString()}</strong>
            </div>
          ))}
        </section>
        <section className="card section">
          <h2>Quick actions</h2>
          <div className="row"><strong>Record a sale</strong><span className="muted">Coming next</span></div>
          <div className="row"><strong>Record a purchase</strong><span className="muted">Coming next</span></div>
          <div className="row"><strong>Add product</strong><span className="muted">Coming next</span></div>
        </section>
      </div>
    </main>
  );
}
