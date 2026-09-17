# Shade

Kiosk stock, sales and inventory intelligence.

## Stack

- Next.js App Router
- Vercel
- Neon Postgres through the Vercel Marketplace
- Neon serverless driver

## Database

Run `db/schema.sql` against the Neon database provisioned for the Vercel project.

The intended source of truth is the inventory movement ledger. Product `current_stock` is a fast operational value and every purchase/sale must have a corresponding movement.

## First milestone

A kiosk operator must be able to record products, purchases and sales and later reconstruct exactly what happened to stock and money.
