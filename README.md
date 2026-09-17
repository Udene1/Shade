# Shade

Kiosk stock, sales and inventory intelligence.

## Stack

- Next.js App Router
- Vercel
- Neon Postgres through the Vercel Marketplace
- Neon serverless driver

## Database

Run `db/schema.sql` followed by the migrations in `db/migrations/` against the Neon database provisioned for the Vercel project.

The intended source of truth is the inventory movement ledger. Product `current_stock` is a fast operational value and every purchase/sale must have a corresponding movement.

Inventory valuation is derived from that ledger. Shade always calculates both **WAC (weighted average cost)** and **FIFO (first in, first out)** from the complete movement history; the selected method only controls which calculated value the dashboard presents. Switching methods does not rewrite the ledger or replace either calculation.

Valuation uses the business event time (`occurred_at`) rather than database insertion time, so delayed entry of an old purchase, sale, or physical-count adjustment does not silently reorder the inventory history.

Stock reconciliation compares the operational count with the movement ledger. Differences are recorded as explicit adjustment movements with a reason rather than silently changing history.

## First milestone

A kiosk operator must be able to record products, purchases and sales and later reconstruct exactly what happened to stock and money.

## Verification

CI provisions PostgreSQL, applies the schema and migrations, runs real database valuation/reconciliation tests, then runs lint and the production build. There are no mock inventory calculations in the verification path.
