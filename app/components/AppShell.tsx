"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const links = [
  { href: "/", label: "Dashboard", icon: "▦" },
  { href: "/sales", label: "Sales", icon: "↗" },
  { href: "/inventory", label: "Inventory", icon: "▤" },
  { href: "/products", label: "Products", icon: "▣" },
  { href: "/purchasing", label: "Buy stock", icon: "＋" },
  { href: "/credit", label: "Credit & debtors", icon: "◎" },
  { href: "/operations", label: "Transactions", icon: "↻" },
];

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const active = links.find((item) => item.href === pathname);
  return <div className="app-shell">
    <aside className="sidebar">
      <Link href="/" className="brand"><span className="brand-mark">s</span><span><strong>shade</strong><small>Kiosk management</small></span></Link>
      <div className="nav-caption">WORKSPACE</div>
      <nav className="side-nav" aria-label="Main navigation">
        {links.map((item) => <Link key={item.href} href={item.href} className={pathname === item.href ? "nav-link active" : "nav-link"}><span className="nav-icon">{item.icon}</span>{item.label}{pathname === item.href && <span className="nav-indicator" />}</Link>)}
      </nav>
      <div className="sidebar-footer"><span className="status-dot" /> Your shop workspace</div>
    </aside>
    <div className="app-content">
      <header className="topbar"><div className="mobile-brand"><span className="brand-mark">s</span><strong>shade</strong></div><div className="breadcrumb">Workspace <span>/</span> <strong>{active?.label ?? "Operations"}</strong></div><span className="connection-pill"><span className="status-dot" /> Business workspace</span></header>
      <div className="page-content">{children}</div>
      <nav className="mobile-nav" aria-label="Main navigation">{[links[0], links[1], links[2], links[4], links[6]].map((item) => <Link key={item.href} href={item.href} className={pathname === item.href ? "mobile-nav-link active" : "mobile-nav-link"}><span>{item.icon}</span><small>{item.label === "Credit & debtors" ? "Credit" : item.label}</small></Link>)}</nav>
    </div>
  </div>;
}
