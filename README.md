# Ledger Suit

Multi-tenant financial management SaaS. Simpler than a spreadsheet to operate,
backed by a real double-entry ledger.

This repository currently contains **Phase 1 — the accounting foundation**:
schema, tenancy, authorization, the posting engine, row level security,
reporting RPCs, seed data and an automated test suite. The four product pages
(Dashboard, Transactions, Accounts, Reports) arrive in Phase 2.

---

## Stack

| Layer | Choice |
|---|---|
| Database | PostgreSQL 17 on Supabase |
| Auth | Supabase Auth |
| Storage | Supabase Storage, private bucket |
| Frontend | Nuxt 4 + TypeScript + Tailwind CSS 4 |
| Billing | Provider-agnostic tables; no vendor SDK in the domain |

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
  tests/                pgTAP: accounting integrity and tenant isolation
  seed.sql              Development data. Fake figures only.
types/database.types.ts Generated from the schema; do not hand-edit
```

---

## What Phase 1 guarantees

Verified by `pnpm db:test` (45 assertions, all passing):

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

See [docs/architecture.md](docs/architecture.md) for how.

---

## Documentation

- [Architecture](docs/architecture.md) — tenancy, ledger design, posting engine
- [Environment variables](docs/environment.md)
- [Deployment](docs/deployment.md)
