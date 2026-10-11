import { sql } from "@/lib/db";
import { KioskActions } from "@/app/components/KioskActions";
type ProductRow = { id: number | string; name: string; category: string | null; selling_price: number | string; current_stock: number | string; minimum_stock: number | string };
export const dynamic = "force-dynamic";
export default async function PurchasingPage() {
 const products: ProductRow[] = process.env.DATABASE_URL ? await sql`SELECT id, name, category, selling_price, current_stock, minimum_stock FROM products ORDER BY name` as ProductRow[] : [];
 return <main><div className="page-heading"><div><div className="eyebrow">RESTOCKING</div><h1>Buy stock</h1><p>Record purchases with unit cost and supplier details to keep inventory valuation accurate.</p></div></div><KioskActions view="purchasing" products={products.map(p=>({...p,id:Number(p.id),selling_price:Number(p.selling_price),current_stock:Number(p.current_stock),minimum_stock:Number(p.minimum_stock)}))}/></main>;
}