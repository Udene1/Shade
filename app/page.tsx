import { sql } from "@/lib/db";
import { KioskActions } from "@/app/components/KioskActions";
import { InventoryControls } from "@/app/components/InventoryControls";

type Product = { id: number; name: string; category: string | null; selling_price: number | string; current_stock: number | string; minimum_stock: number | string };
type Debt = { id: number; debtor_name: string; product_name: string; amount_due: number | string; paid: number | string; balance: number | string };
type Seller = { name: string; sold: number | string; revenue: number | string; profit: number | string };
type Reconciliation = { id: number; name: string; current_stock: number; ledger_stock: number };
type DashboardMetrics = { revenue: number | string; cost: number | string; units: number | string; stock_value: number | string; valuation_method: string };

async function getDashboard() {
  if (!process.env.DATABASE_URL) return { connected: false, metrics: null as DashboardMetrics | null, products: [] as Product[], bestSellers: [] as Seller[], lowStock: [] as Product[], debts: [] as Debt[], outstanding: 0, mismatches: [] as Reconciliation[] };
  try {
    const metricsRows = await sql`
      SELECT COALESCE((SELECT SUM(quantity * unit_price) FROM sales WHERE sold_at >= CURRENT_DATE), 0)::numeric AS revenue,
        COALESCE((SELECT SUM(CASE WHEN settings.method = 'FIFO' THEN c.fifo_cost ELSE c.wac_cost END)
          FROM sales s JOIN inventory_movements m ON m.reference_id = s.id AND m.type = 'SALE'
          JOIN inventory_sale_costs c ON c.movement_id = m.id CROSS JOIN inventory_valuation_settings settings
          WHERE s.sold_at >= CURRENT_DATE AND settings.id = 1), 0)::numeric AS cost,
        COALESCE((SELECT SUM(quantity) FROM sales WHERE sold_at >= CURRENT_DATE), 0)::int AS units,
        COALESCE((SELECT SUM(selected_stock_cost) FROM inventory_valuation_selected), 0)::numeric AS stock_value,
        (SELECT method FROM inventory_valuation_settings WHERE id = 1) AS valuation_method`;
    const metrics = metricsRows[0] as DashboardMetrics;
    const products = (await sql`SELECT id, name, category, selling_price, current_stock, minimum_stock FROM products ORDER BY name`) as Product[];
    const sellerRows = await sql`
      SELECT p.name, COALESCE(SUM(s.quantity), 0)::int AS sold, COALESCE(SUM(s.quantity * s.unit_price), 0)::numeric AS revenue,
        COALESCE(SUM(CASE WHEN settings.method = 'FIFO' THEN c.fifo_cost ELSE c.wac_cost END), 0)::numeric AS cost
      FROM products p LEFT JOIN sales s ON s.product_id = p.id LEFT JOIN inventory_movements m ON m.reference_id = s.id AND m.type = 'SALE'
      LEFT JOIN inventory_sale_costs c ON c.movement_id = m.id CROSS JOIN inventory_valuation_settings settings
      GROUP BY p.id, settings.method ORDER BY sold DESC, cost ASC LIMIT 8`;
    const bestSellers: Seller[] = sellerRows.map((p) => ({ name: String(p.name), sold: Number(p.sold), revenue: Number(p.revenue), profit: Number(p.revenue) - Number(p.cost) }));
    const debts = (await sql`
      SELECT cs.id, d.name AS debtor_name, p.name AS product_name, cs.amount_due,
        COALESCE(SUM(cp.amount), 0)::numeric AS paid, (cs.amount_due - COALESCE(SUM(cp.amount), 0))::numeric AS balance
      FROM credit_sales cs JOIN debtors d ON d.id = cs.debtor_id JOIN sales s ON s.id = cs.sale_id JOIN products p ON p.id = s.product_id
      LEFT JOIN credit_payments cp ON cp.credit_sale_id = cs.id GROUP BY cs.id, d.name, p.name, cs.amount_due
      HAVING cs.amount_due - COALESCE(SUM(cp.amount), 0) > 0 ORDER BY cs.created_at ASC`) as Debt[];
    const mismatches = (await sql`
      SELECT p.id, p.name, p.current_stock::int AS current_stock, COALESCE(SUM(m.quantity), 0)::int AS ledger_stock
      FROM products p LEFT JOIN inventory_movements m ON m.product_id = p.id GROUP BY p.id
      HAVING p.current_stock <> COALESCE(SUM(m.quantity), 0) ORDER BY p.name`) as Reconciliation[];
    const outstanding = debts.reduce((sum, d) => sum + Number(d.balance), 0);
    return { connected: true, metrics, products, bestSellers, lowStock: products.filter((p) => Number(p.current_stock) <= Number(p.minimum_stock)), debts, outstanding, mismatches };
  } catch {
    return { connected: false, metrics: null as DashboardMetrics | null, products: [] as Product[], bestSellers: [] as Seller[], lowStock: [] as Product[], debts: [] as Debt[], outstanding: 0, mismatches: [] as Reconciliation[] };
  }
}

export default async function Home() {
  const data = await getDashboard();
  const revenue = Number(data.metrics?.revenue ?? 0), cost = Number(data.metrics?.cost ?? 0), profit = revenue - cost;
  const units = Number(data.metrics?.units ?? 0), stockValue = Number(data.metrics?.stock_value ?? 0), method = data.metrics?.valuation_method ?? "WAC";
  return (
    <main>
      <header className="header"><div><h1>Shade</h1><p>Stock, sales and the money tied up in your kiosk.</p></div><span className="badge">{data.connected ? "Database connected" : "Database not configured"}</span></header>
      <section className="grid">
        <div className="card"><div className="metric-label">Today&apos;s sales</div><div className="metric">₦{revenue.toLocaleString()}</div></div>
        <div className="card"><div className="metric-label">Gross profit ({method})</div><div className="metric">₦{profit.toLocaleString()}</div></div>
        <div className="card"><div className="metric-label">Units sold</div><div className="metric">{units.toLocaleString()}</div></div>
        <div className="card"><div className="metric-label">Inventory cost ({method})</div><div className="metric">₦{stockValue.toLocaleString()}</div></div>
        <div className="card"><div className="metric-label">Money owed to me</div><div className="metric">₦{data.outstanding.toLocaleString()}</div></div>
      </section>
      {data.lowStock.length > 0 && <section className="card section warning"><h2>Low stock</h2>{data.lowStock.map((p) => <div className="row" key={p.id}><strong>{p.name}</strong><span>{p.current_stock} left · minimum {p.minimum_stock}</span></div>)}</section>}
      <section className="card section"><h2>Best sellers</h2>{data.bestSellers.length === 0 ? <p className="muted">Record sales to see which products move fastest.</p> : data.bestSellers.map((p) => <div className="row" key={p.name}><div><strong>{p.name}</strong><div className="muted">{p.sold} sold · ₦{Number(p.revenue).toLocaleString()} revenue</div></div><strong>₦{Number(p.profit).toLocaleString()}</strong></div>)}</section>
      <InventoryControls
        method={method}
        products={data.products.map((p) => ({ id: Number(p.id), name: p.name, current_stock: Number(p.current_stock) }))}
        mismatches={data.mismatches}
      />
      <KioskActions products={data.products.map((p) => ({ id: Number(p.id), name: p.name, selling_price: Number(p.selling_price), current_stock: Number(p.current_stock) }))} debts={data.debts.map((d) => ({ ...d, id: Number(d.id) }))} />
    </main>
  );
}
