# Ledger Suit

Multi-tenant financial management SaaS. Simpler than a spreadsheet to operate,
backed by a real double-entry ledger.

This repository contains **Phases 1–4**: the multi-tenant accounting
foundation, a public product site, guided owner onboarding, the four
core-finance product pages, operational workflows, and a database-enforced
Stripe subscription with a 14-day trial and Resend delivery.

---

## Stack

| Layer | Choice |
|---|---|
| Database | PostgreSQL 17 on Supabase |
| Auth | Supabase Auth |
| Storage | Supabase Storage, private bucket |
| Frontend | Nuxt 4 + TypeScript + Tailwind CSS 4 |
| Billing | Stripe Checkout + Portal; database-authoritative access state |
| Email | Resend through Supabase Edge Functions |

---

## Quick start

```bash
pnpm install
cp .env.example .env

pnpm db:start      # boots the local Supabase stack (needs Docker)
pnpm db:reset      # replays every migration from empty, then seeds
pnpm dev           # http://localhost:3000
```

`pnpm db:start` prints the local API URL and keys. Copy them into `.env` if they
differ from the defaults already in `.env.example`.

### Seeded development accounts

Password for all of them: `ledgersuit`

| Email | Organization | Role |
|---|---|---|
| `owner@alpha.test` | Alpha Trading | owner |
| `accountant@alpha.test` | Alpha Trading | accountant |
| `viewer@alpha.test` | Alpha Trading | viewer |
| `owner@beta.test` | Beta Supplies | owner |

Two organizations exist on purpose, so cross-tenant leaks are visible during
development rather than only in the test suite.

---

## Scripts

| Command | What it does |
|---|---|
| `pnpm dev` | Nuxt dev server |
| `pnpm build` | Production build |
| `pnpm typecheck` | `vue-tsc` over the whole app |
| `pnpm lint` | ESLint |
| `pnpm test:e2e` | Playwright journeys against local Supabase |
| `pnpm db:start` / `pnpm db:stop` | Local Supabase stack |
| `pnpm db:reset` | Drop, replay all migrations, apply `supabase/seed.sql` |
| `pnpm db:test` | pgTAP suite (`supabase/tests/`) |
| `pnpm db:lint` | Supabase schema linter |
| `pnpm db:types` | Regenerate `types/database.types.ts` from the local database |

---

## Database workflow — read this before changing the schema

**The Git repository is the source of truth for the database.** Supabase is
linked to this repository and applies committed migrations through its own
deployment process.

Do:

- put every schema change in a new timestamped file under `supabase/migrations/`
- validate locally with `pnpm db:reset && pnpm db:test && pnpm db:lint`
- commit the migration and let the linked deployment apply it

Do **not**:

- run `supabase db push` against the linked remote project
- paste DDL into the Supabase SQL editor
- edit or delete a migration that has already been applied — write a new one

A migration that has shipped is history. Corrections go forward, never
backward.

---

## Layout

```
app/                    Nuxt application (pages, composables, utils)
docs/                   Architecture, environment and deployment notes
supabase/
  migrations/           Versioned schema — the authoritative definition
  functions/            Stripe and Resend Edge Functions
  tests/                pgTAP: accounting integrity and tenant isolation
  seed.sql              Development data. Fake figures only.
types/database.types.ts Generated from the schema; do not hand-edit
```

---

## What Phases 1–4 guarantee

Verified by `pnpm db:test` (105 assertions) and `pnpm test:e2e`:

- every posting produces balanced ledger entries — `SUM(debits) = SUM(credits)`
- reversals return the affected accounts to exactly their prior balance
- `Assets = Liabilities + Equity` holds after every operation
- posted transactions and their ledger lines cannot be edited or deleted, **not
  even by a database superuser** — the guard is a trigger, not a grant
- a user who knows another organization's UUID still gets nothing: no reads, no
  writes, no reports, no ledger, no audit log
- a foreign account id cannot be smuggled into your own organization's posting
- posting into a locked period is refused without `books.override_lock`
- retrying a posting with the same idempotency key returns the original record
- commitments support full/partial settlement, postponement, cancellation,
  reminders and controlled automatic conversion into real ledger transactions
- recurring occurrences are idempotent, confirmable, skippable and retryable
- organization invitations are created and accepted through controlled RPCs
- direct client mutation cannot bypass financial or notification workflows
- the Dashboard, Transactions, Accounts and Reports journeys run end-to-end
- account creation collects the owner and business profile, provisions a full
  starter ledger atomically, verifies the email with an in-app six-digit OTP,
  and continues directly into Stripe Checkout
- the public landing and three-step signup journey run end-to-end in English
  and share the Building Suit monochrome design system with the application
- a permission-aware global add drawer reaches every supported transaction,
  account, operational, tagging, counterparty, and team invitation workflow
- a new organization cannot write until Stripe Checkout collects a payment
  method and starts its 14-day trial
- expired billing is enforced as read-only inside PostgreSQL, while tenant data
  remains available to authorized members
- Stripe webhook retries are idempotent and scheduled financial jobs skip
  organizations without write access

See [docs/architecture.md](docs/architecture.md) for how.

---

## Documentation

- [Architecture](docs/architecture.md) — tenancy, ledger design, posting engine
- [Environment variables](docs/environment.md)
- [Deployment](docs/deployment.md)
- [Phase 1–3 status](docs/phase-1-to-3-status.md)
