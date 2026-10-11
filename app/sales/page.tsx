import { sql } from "@/lib/db";
import { KioskActions } from "@/app/components/KioskActions";
export const dynamic = "force-dynamic";
export default async function SalesPage() {
 const products = process.env.DATABASE_URL ? await sql`SELECT id, name, category, selling_price, current_stock, minimum_stock FROM products ORDER BY name` : [];
 return <main><div className="page-heading"><div><div className="eyebrow">POINT OF SALE</div><h1>Sales</h1><p>Record a sale or sell on credit. Stock updates through the existing inventory ledger.</p></div></div><KioskActions view="sales" products={(products as any[]).map(p=>({...p,id:Number(p.id),selling_price:Number(p.selling_price),current_stock:Number(p.current_stock),minimum_stock:Number(p.minimum_stock)}))}/></main>;
}