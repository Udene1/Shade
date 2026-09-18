import { sql } from "@/lib/db";
import { KioskActions } from "@/app/components/KioskActions";
import { InventoryControls } from "@/app/components/InventoryControls";
import { DataHealth } from "@/app/components/DataHealth";

type Product = { id: number; name: string; category: string | null; selling_price: number | string; current_stock: number | string; minimum_stock: number | string };
type Debt = { id: number; debtor_name: string; product_name: string; amount_due: number | string; paid: number | string; balance: number | string };
type Seller = { name: string; sold: number | string; revenue: number | string; profit: number | string };
type Reconciliation = { id: number; name: string; current_stock: number; ledger_stock: number };
type Velocity = { product_id: number; name: string; current_stock: number | string; units_sold: number | string; revenue: number | string; fifo_gross_profit: number | string; wac_gross_profit: number | string; units_per_day: number | string; average_stock_units: number | string | null; inventory_turnover_units: number | string | null; stock_cover_days: number | string | null; last_sale_at: string | null };
type Attention = { product_id: number; name: string; current_stock: number | string; units_sold_30d: number | string; units_sold_90d: number | string; fifo_stock_cost: number | string; wac_stock_cost: number | string; attention_status: string };
type Concentration = { name: string; outstanding_balance: number | string; outstanding_share: number | string; open_credit_sales: number };
type CapitalProductivity = { fifo_gross_profit_30d: number | string; wac_gross_profit_30d: number | string; fifo_capital_in_stock: number | string; wac_capital_in_stock: number | string; fifo_gross_profit_per_current_stock_cost_30d: number | string | null; wac_gross_profit_per_current_stock_cost_30d: number | string | null };
type DecisionSignal = { product_id: number; name: string; current_stock: number | string; units_sold_30d: number | string; units_sold_90d: number | string; units_per_day: number | string; stock_cover_days: number | string | null; inventory_turnover_units: number | string | null; fifo_gross_profit_30d: number | string; wac_gross_profit_30d: number | string; fifo_capital_in_stock: number | string; wac_capital_in_stock: number | string; fifo_gross_profit_per_current_stock_cost_30d: number | string | null; wac_gross_profit_per_current_stock_cost_30d: number | string | null; decision_signal: string; evidence: string };
type DashboardMetrics = { revenue: number | string; cost: number | string; units: number | string; stock_value: number | string; valuation_method: string };\ntype HealthCheck = { check_name: string; status: string; detail: string };

async function getDashboard() {
  if (!process.env.DATABASE_URL) return { connected: false, metrics: null as DashboardMetrics | null, products: [] as Product[], bestSellers: [] as Seller[], lowStock: [] as Product[], debts: [] as Debt[], outstanding: 0, mismatches: [] as Reconciliation[], velocity: [] as Velocity[], attention: [] as Attention[], concentration: [] as Concentration[], capitalProductivity: null as CapitalProductivity | null, decisionSignals: [] as DecisionSignal[], healthChecks: [] as HealthCheck[] };
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
    const velocity = (await sql`SELECT product_id, name, current_stock, units_sold, revenue, fifo_gross_profit, wac_gross_profit, units_per_day, average_stock_units, inventory_turnover_units, stock_cover_days, last_sale_at FROM product_sales_velocity WHERE window_days = 30 ORDER BY units_sold DESC, revenue DESC, name ASC`) as Velocity[];
    const attention = (await sql`SELECT product_id, name, current_stock, units_sold_30d, units_sold_90d, fifo_stock_cost, wac_stock_cost, attention_status FROM inventory_attention WHERE attention_status <> 'NORMAL' ORDER BY CASE attention_status WHEN 'LOW_STOCK' THEN 1 WHEN 'NO_SALES_30D' THEN 2 WHEN 'DEAD_STOCK_90D' THEN 3 WHEN 'SLOW_STOCK' THEN 4 ELSE 5 END, name LIMIT 12`) as Attention[];
    const concentration = (await sql`SELECT name, outstanding_balance, outstanding_share, open_credit_sales FROM debtor_concentration ORDER BY outstanding_balance DESC LIMIT 8`) as Concentration[];
    const capitalProductivityRows = await sql`SELECT fifo_gross_profit_30d, wac_gross_profit_30d, fifo_capital_in_stock, wac_capital_in_stock, fifo_gross_profit_per_current_stock_cost_30d, wac_gross_profit_per_current_stock_cost_30d FROM store_capital_productivity`;
    const capitalProductivity = (capitalProductivityRows[0] ?? null) as CapitalProductivity | null;
    const decisionSignals = (await sql`SELECT product_id, name, current_stock, units_sold_30d, units_sold_90d, units_per_day, stock_cover_days, inventory_turnover_units, fifo_gross_profit_30d, wac_gross_profit_30d, fifo_capital_in_stock, wac_capital_in_stock, fifo_gross_profit_per_current_stock_cost_30d, wac_gross_profit_per_current_stock_cost_30d, decision_signal, evidence FROM inventory_decision_signals WHERE decision_signal <> 'MEASURED_NORMAL' ORDER BY CASE decision_signal WHEN 'REPLENISHMENT_PRESSURE' THEN 1 WHEN 'CAPITAL_TIED_NO_DEMAND' THEN 2 WHEN 'CAPITAL_TIED_LOW_RECENT_DEMAND' THEN 3 WHEN 'SLOW_CAPITAL' THEN 4 ELSE 5 END, name LIMIT 12`) as DecisionSignal[];\n    const healthChecks = (await sql`SELECT check_name, status, detail FROM shade_data_health ORDER BY CASE status WHEN 'ERROR' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END, check_name`) as HealthCheck[];
    const debts = (await sql`SELECT cs.id, d.name AS debtor_name, p.name AS product_name, cs.amount_due, COALESCE(SUM(cp.amount), 0)::numeric AS paid, (cs.amount_due - COALESCE(SUM(cp.amount), 0))::numeric AS balance FROM credit_sales cs JOIN debtors d ON d.id = cs.debtor_id JOIN sales s ON s.id = cs.sale_id JOIN products p ON p.id = s.product_id LEFT JOIN credit_payments cp ON cp.credit_sale_id = cs.id GROUP BY cs.id, d.name, p.name, cs.amount_due HAVING cs.amount_due - COALESCE(SUM(cp.amount), 0) > 0 ORDER BY cs.created_at ASC`) as Debt[];
    const mismatches = (await sql`SELECT p.id, p.name, p.current_stock::int AS current_stock, COALESCE(SUM(m.quantity), 0)::int AS ledger_stock FROM products p LEFT JOIN inventory_movements m ON m.product_id = p.id GROUP BY p.id HAVING p.current_stock <> COALESCE(SUM(m.quantity), 0) ORDER BY p.name`) as Reconciliation[];
    const outstanding = debts.reduce((sum, d) => sum + Number(d.balance), 0);
    return { connected: true, metrics, products, bestSellers, lowStock: products.filter((p) => Number(p.current_stock) <= Number(p.minimum_stock)), debts, outstanding, mismatches, velocity, attention, concentration, capitalProductivity, decisionSignals, healthChecks };
  } catch {
    return { connected: false, metrics: null as DashboardMetrics | null, products: [] as Product[], bestSellers: [] as Seller[], lowStock: [] as Product[], debts: [] as Debt[], outstanding: 0, mismatches: [] as Reconciliation[], velocity: [] as Velocity[], attention: [] as Attention[], concentration: [] as Concentration[], capitalProductivity: null as CapitalProductivity | null, decisionSignals: [] as DecisionSignal[] };
  }
}

export default async function Home() {
  const data = await getDashboard();
  const revenue = Number(data.metrics?.revenue ?? 0), cost = Number(data.metrics?.cost ?? 0), profit = revenue - cost;
  const units = Number(data.metrics?.units ?? 0), stockValue = Number(data.metrics?.stock_value ?? 0), method = data.metrics?.valuation_method ?? "WAC";
  const measuredMovers = data.velocity.slice(0, 8);
  const idleStock = data.velocity.filter((p) => Number(p.current_stock) > 0 && Number(p.units_sold) === 0).slice(0, 8);
  const statusLabel: Record<string, string> = { LOW_STOCK: "Low stock", NO_SALES_30D: "No sales in 30d", DEAD_STOCK_90D: "No sales in 90d", SLOW_STOCK: "Slow stock" };
  const decisionLabel: Record<string, string> = { REPLENISHMENT_PRESSURE: "Replenishment pressure", CAPITAL_TIED_NO_DEMAND: "Capital tied · no 90d demand", CAPITAL_TIED_LOW_RECENT_DEMAND: "Capital tied · no 30d demand", SLOW_CAPITAL: "Slow capital" };
  const capitalProductivity = data.capitalProductivity;
  const selectedCapitalProductivity = method === "FIFO" ? Number(capitalProductivity?.fifo_gross_profit_per_current_stock_cost_30d ?? 0) : Number(capitalProductivity?.wac_gross_profit_per_current_stock_cost_30d ?? 0);
  const selectedCapitalInStock = method === "FIFO" ? Number(capitalProductivity?.fifo_capital_in_stock ?? 0) : Number(capitalProductivity?.wac_capital_in_stock ?? 0);
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
      {capitalProductivity && <section className="card section"><h2>30-day capital productivity ({method})</h2><div className="row"><div><strong>Gross profit / current stock cost</strong><div className="muted">₦{(method === "FIFO" ? Number(capitalProductivity.fifo_gross_profit_30d) : Number(capitalProductivity.wac_gross_profit_30d)).toLocaleString()} gross profit against ₦{selectedCapitalInStock.toLocaleString()} currently tied in stock</div></div><strong>{selectedCapitalProductivity.toFixed(2)}×</strong></div><p className="muted">This is a current-capital productivity ratio, not a historical inventory-return rate. It uses the selected WAC/FIFO valuation.</p></section>}
      {data.decisionSignals.length > 0 && <section className="card section"><h2>Inventory signals from observed data</h2>{data.decisionSignals.map((p) => <div className="row" key={p.product_id}><div><strong>{p.name}</strong><div className="muted">{p.evidence} · {Number(p.units_sold_30d).toLocaleString()} sold in 30d · {p.stock_cover_days == null ? "no cover estimate" : `${Number(p.stock_cover_days).toFixed(1)} days cover`} · {method} capital productivity {Number(method === "FIFO" ? p.fifo_gross_profit_per_current_stock_cost_30d ?? 0 : p.wac_gross_profit_per_current_stock_cost_30d ?? 0).toFixed(2)}×</div></div><span>{decisionLabel[p.decision_signal] ?? p.decision_signal}</span></div>)}</section>}
      {data.lowStock.length > 0 && <section className="card section warning"><h2>Low stock</h2>{data.lowStock.map((p) => <div className="row" key={p.id}><strong>{p.name}</strong><span>{p.current_stock} left · minimum {p.minimum_stock}</span></div>)}</section>}
      <section className="card section"><h2>30-day sales velocity</h2>{measuredMovers.length === 0 ? <p className="muted">Record dated sales to measure product movement.</p> : measuredMovers.map((p) => <div className="row" key={p.product_id}><div><strong>{p.name}</strong><div className="muted">{Number(p.units_sold).toLocaleString()} sold · {Number(p.units_per_day).toFixed(2)} units/day · {p.stock_cover_days == null ? "no cover estimate" : `${Number(p.stock_cover_days).toFixed(1)} days of stock`}</div></div><strong>{p.inventory_turnover_units == null ? "—" : `${Number(p.inventory_turnover_units).toFixed(2)}×`}</strong></div>)}</section>
      {data.attention.length > 0 && <section className="card section"><h2>Inventory needing attention</h2>{data.attention.map((p) => <div className="row" key={p.product_id}><div><strong>{p.name}</strong><div className="muted">{Number(p.current_stock).toLocaleString()} units · {Number(p.units_sold_30d).toLocaleString()} sold in 30d · {Number(p.units_sold_90d).toLocaleString()} in 90d</div></div><span>{statusLabel[p.attention_status] ?? p.attention_status}</span></div>)}</section>}
      {idleStock.length > 0 && <section className="card section"><h2>No sales in 30 days</h2>{idleStock.map((p) => <div className="row" key={p.product_id}><div><strong>{p.name}</strong><div className="muted">{Number(p.current_stock).toLocaleString()} units currently held</div></div><span className="muted">₦{Number(p.revenue).toLocaleString()}</span></div>)}</section>}
      {data.concentration.length > 0 && <section className="card section"><h2>Debtor concentration</h2>{data.concentration.map((d) => <div className="row" key={d.name}><div><strong>{d.name}</strong><div className="muted">{d.open_credit_sales} open credit sale{d.open_credit_sales === 1 ? "" : "s"}</div></div><strong>₦{Number(d.outstanding_balance).toLocaleString()} · {(Number(d.outstanding_share) * 100).toFixed(1)}%</strong></div>)}</section>}
      <section className="card section"><h2>Best sellers</h2>{data.bestSellers.length === 0 ? <p className="muted">Record sales to see which products move fastest.</p> : data.bestSellers.map((p) => <div className="row" key={p.name}><div><strong>{p.name}</strong><div className="muted">{p.sold} sold · ₦{Number(p.revenue).toLocaleString()} revenue</div></div><strong>₦{Number(p.profit).toLocaleString()}</strong></div>)}</section>
      <DataHealth checks={data.healthChecks} />\n      <InventoryControls method={method} products={data.products.map((p) => ({ id: Number(p.id), name: p.name, current_stock: Number(p.current_stock) }))} mismatches={data.mismatches} />
      <KioskActions products={data.products.map((p) => ({ id: Number(p.id), name: p.name, category: p.category, selling_price: Number(p.selling_price), current_stock: Number(p.current_stock), minimum_stock: Number(p.minimum_stock) }))} debts={data.debts.map((d) => ({ ...d, id: Number(d.id) }))} />
    </main>
  );
}
