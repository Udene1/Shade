import type { Metadata } from "next";
import "./globals.css";
import { AppShell } from "@/app/components/AppShell";

export const metadata: Metadata = {
  title: "Shade — Stock & Sales",
  description: "Simple kiosk inventory and sales tracking.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body><AppShell>{children}</AppShell></body></html>;
}
