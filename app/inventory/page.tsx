import { sql } from "@/lib/db";
import { InventoryControls } from "@/app/components/InventoryControls";
import { DataHealth } from "@/app/components/DataHealth";
type ProductRow = { id: number | string; name: string; current_stock: number | string };
type MismatchRow = { id: number | string; name: string; current_stock: number | string; ledger_stock: number | string };
type HealthRow = { check_name: string; status: string; detail: string };
export const dynamic = "force-dynamic";
export default async function InventoryPage() {
 let products: ProductRow[]=[]; let mismatches: MismatchRow[]=[]; let method="WAC"; let checks: HealthRow[]=[];
 if(process.env.DATABASE_URL){try{
 products=await sql`SELECT id,name,current_stock FROM products ORDER BY name` as ProductRow[];
 mismatches=await sql`SELECT p.id,p.name,p.current_stock::int AS current_stock,COALESCE(SUM(m.quantity),0)::int AS ledger_stock FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id GROUP BY p.id HAVING p.current_stock<>COALESCE(SUM(m.quantity),0) ORDER BY p.name` as MismatchRow[];
 const settings=await sql`SELECT method FROM inventory_valuation_settings WHERE id=1`;method=String(settings[0]?.method??"WAC");
 checks=await sql`SELECT check_name,status,detail FROM shade_data_health ORDER BY CASE status WHEN 'ERROR' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,check_name` as HealthRow[];
 }catch{}}
 return <main><div className="page-heading"><div><div className="eyebrow">STOCK CONTROL</div><h1>Inventory</h1><p>Manage stock valuation, physical counts, and inventory integrity.</p></div></div><InventoryControls method={method} products={products.map(p=>({id:Number(p.id),name:String(p.name),current_stock:Number(p.current_stock)}))} mismatches={mismatches.map(p=>({...p,id:Number(p.id),current_stock:Number(p.current_stock),ledger_stock:Number(p.ledger_stock)}))}/><DataHealth checks={checks}/></main>;
}