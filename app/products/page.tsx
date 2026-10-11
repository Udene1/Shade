import { sql } from "@/lib/db";
import { KioskActions } from "@/app/components/KioskActions";
export const dynamic = "force-dynamic";
export default async function ProductsPage() {
 const products = process.env.DATABASE_URL ? await sql`SELECT id, name, category, selling_price, current_stock, minimum_stock FROM products ORDER BY name` : [];
 return <main><div className="page-heading"><div><div className="eyebrow">CATALOGUE</div><h1>Products</h1><p>Add products, update prices, and set the stock level that should trigger a warning.</p></div></div><KioskActions view="products" products={(products as any[]).map(p=>({...p,id:Number(p.id),selling_price:Number(p.selling_price),current_stock:Number(p.current_stock),minimum_stock:Number(p.minimum_stock)}))}/></main>;
}