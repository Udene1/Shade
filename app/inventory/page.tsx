import { sql } from "@/lib/db";
import { InventoryControls } from "@/app/components/InventoryControls";
import { DataHealth } from "@/app/components/DataHealth";
export const dynamic = "force-dynamic";
export default async function InventoryPage() {
 let products:any[]=[]; let mismatches:any[]=[]; let method="WAC"; let checks:any[]=[];
 if(process.env.DATABASE_URL){try{
 products=await sql`SELECT id,name,current_stock,minimum_stock FROM products ORDER BY name`;
 mismatches=await sql`SELECT p.id,p.name,p.current_stock::int AS current_stock,COALESCE(SUM(m.quantity),0)::int AS ledger_stock FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id GROUP BY p.id HAVING p.current_stock<>COALESCE(SUM(m.quantity),0) ORDER BY p.name`;
 const settings=await sql`SELECT method FROM inventory_valuation_settings WHERE id=1`;method=String(settings[0]?.method??"WAC");
 checks=await sql`SELECT check_name,status,detail FROM shade_data_health ORDER BY CASE status WHEN 'ERROR' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,check_name`;
 }catch{}}
 return <main><div className="page-heading"><div><div className="eyebrow">STOCK CONTROL</div><h1>Inventory</h1><p>Manage stock valuation, physical counts, and inventory integrity.</p></div></div><InventoryControls method={method} products={products.map(p=>({id:Number(p.id),name:String(p.name),current_stock:Number(p.current_stock)}))} mismatches={mismatches.map(p=>({...p,id:Number(p.id),current_stock:Number(p.current_stock),ledger_stock:Number(p.ledger_stock)}))}/><DataHealth checks={checks as any}/></main>;
}