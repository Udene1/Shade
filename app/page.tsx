import { sql } from "@/lib/db";
import { KioskActions } from "@/app/components/KioskActions";

type Product = { id: number; name: string; category: string | null; selling_price: number; current_stock: number; minimum_stock: number };
type Debt = { id: number; debtor_name: string; product_name: string; amount_due: number; paid: number; balance: number };

async function getDashboard() {
  if (!process.env.DATABASE_URL) return { connected: false, metrics: null, products: [] as Product[], bestSellers: [], lowStock: [] as Product[], debts: [] as Debt[], outstanding: 0 };
  try {
    const metrics = await sql`
      SELECT
        COALESCE((SELECT SUM(quantity * unit_price) FROM sales WHERE sold_at >= CURRENT_DATE), 0)::numeric AS revenue,
        COALESCE((SELECT SUM(quantity * unit_cost) FROM sales WHERE sold_at >= CURRENT_DATE), 0)::numeric AS cost,
        COALESCE((SELECT SUM(quantity) FROM sales WHERE sold_at >= CURRENT_DATE), 0)::int AS units,
        COALESCE((SELECT SUM(current_stock * selling_price) FROM products), 0)::numeric AS stock_value
    `;
    const products = await sql<Product[]>`SELECT id, name, category, selling_price, current_stock, minimum_stock FROM products ORDER BY name`;
    const bestSellers = await sql`SELECT p.name, COALESCE(SUM(s.quantity), 0)::int AS sold, COALESCE(SUM(s.quantity * s.unit_price), 0)::numeric AS revenue, COALESCE(SUM(s.quantity * (s.unit_price - s.unit_cost)), 0)::numeric AS profit FROM products p LEFT JOIN sales s ON s.product_id = p.id GROUP BY p.id ORDER BY sold DESC, profit DESC LIMIT 8`;
    const debts = await sql<Debt[]>`
      SELECT cs.id, d.name AS debtor_name, p.name AS product_name,
             cs.amount_due,
             COALESCE(SUM(cp.amount), 0)::numeric AS paid,
             (cs.amount_due - COALESCE(SUM(cp.amount), 0))::numeric AS balance
      FROM credit_sales cs
      JOIN debtors d ON d.id = cs.debtor_id
      JOIN sales s ON s.id = cs.sale_id
      JOIN products p ON p.id = s.product_id
      LEFT JOIN credit_payments cp ON cp.credit_sale_id = cs.id
      GROUP BY cs.id, d.name, p.name, cs.amount_due
      HAVING cs.amount_due - COALESCE(SUM(cp.amount), 0) > 0
      ORDER BY cs.created_at ASC
    `;
    const outstanding = debts.reduce((sum, d) => sum + Number(d.balance), 0);
    return { connected: true, metrics: metrics[0], products, bestSellers, lowStock: products.filter((p) => Number(p.current_stock) <= Number(p.minimum_stock)), debts, outstanding };
  } catch {
    return { connected: false, metrics: null, products: [] as Product[], bestSellers: [], lowStock: [] as Product[], debts: [] as Debt[], outstanding: 0 };
  }
}

export default async function Home() {
  const data = await getDashboard();
  const revenue = Number(data.metrics?.revenue ?? 0);
  const cost = Number(data.metrics?.cost ?? 0);
  const profit = revenue - cost;
  const units = Number(data.metrics?.units ?? 0);
  const stockValue = Number(data.metrics?.stock_value ?? 0);
  return (
    <main>
      <header className="header"><div><h1>Shade</h1><p>Stock, sales and the money tied up in your kiosk.</p></div><span className="badge">{data.connected ? "Database connected" : "Database not configured"}</span></header>
      <section className="grid">
        <div className="card"><div className="metric-label">Today&apos;s sales</div><div className="metric">₦{revenue.toLocaleString()}</div></div>
        <div className="card"><div className="metric-label">Gross profit</div><div className="metric">₦{profit.toLocaleString()}</div></div>
        <div className="card"><div className="metric-label">Units sold</div><div className="metric">{units.toLocaleString()}</div></div>
        <div className="card"><div className="metric-label">Stock value</div><div className="metric">₦{stockValue.toLocaleString()}</div></div>
        <div className="card"><div className="metric-label">Money owed to me</div><div className="metric">₦{data.outstanding.toLocaleString()}</div></div>
      </section>
      {data.lowStock.length > 0 && <section className="card section warning"><h2>Low stock</h2>{data.lowStock.map((p) => <div className="row" key={p.id}><strong>{p.name}</strong><span>{p.current_stock} left · minimum {p.minimum_stock}</span></div>)}</section>}
      <section className="card section"><h2>Best sellers</h2>{data.bestSellers.length === 0 ? <p className="muted">Record sales to see which products move fastest.</p> : data.bestSellers.map((p) => <div className="row" key={p.name}><div><strong>{p.name}</strong><div className="muted">{p.sold} sold · ₦{Number(p.revenue).toLocaleString()} revenue</div></div><strong>₦{Number(p.profit).toLocaleString()}</strong></div>)}</section>
      <KioskActions products={data.products} debts={data.debts} />
    </main>
  );
}
