# Deployment

## Database

This repository is linked to a Supabase project. **Supabase detects migrations
committed to this repository and applies them through the linked deployment
process.** The repository migration history is the authoritative representation
of the production schema.

```
implement
  → write migration files under supabase/migrations/
  → validate locally (pnpm db:reset && pnpm db:test && pnpm db:lint)
  → commit
  → push through the normal Git workflow
  → Supabase detects and applies
```

### Never

- `supabase db push` against the linked remote project
- DDL pasted into the Supabase SQL editor
- editing or deleting a migration that has already been applied
- resetting the production database
- resolving a migration conflict by deleting migration history

Applied migrations are immutable historical records. If a shipped migration was
wrong, write a new migration that corrects it.

### Writing a migration

Name it `supabase/migrations/<YYYYMMDDHHMMSS>_<description>.sql`, in dependency
order. Assume it will one day run against a database holding real customer
financial data, which means:

- no destructive table recreation
- no dropping a populated column without a staged migration and an explicit
  backfill
- create indexes deliberately; on a large table use `create index concurrently`
  in its own migration
- repair migrations must be idempotent and safe to re-run
- preserve immutable financial history and tenant isolation throughout

### Validating before commit

```bash
pnpm db:reset     # full replay from empty, then seed
pnpm db:test      # pgTAP: accounting integrity + tenant isolation
pnpm db:lint      # Supabase schema linter, warnings included
pnpm db:types     # regenerate types/database.types.ts and commit the result
```

A clean database built from the complete migration chain must produce exactly
the schema the application expects. If the app depends on a database object,
that object belongs in a migration — no undocumented SQL from anyone's
dashboard.

---

## Application

The Nuxt app is deployed independently of the database.

```bash
pnpm install --frozen-lockfile
pnpm build          # .output/
node .output/server/index.mjs
```

Required at runtime: `SUPABASE_URL` and `SUPABASE_KEY`. See
[environment.md](environment.md). The service role key must never be part of a
client bundle.

The committed CI workflow runs lint, strict type checking, the production
build, a clean local migration replay, all pgTAP tests, schema linting and the
Chromium end-to-end journeys on pull requests and pushes to `main` or `dev`.

---

## Branching

Work on a branch named `{type}/{short-title}` (`feat/`, `fix/`, `chore/`,
`docs/`, `refactor/`, `test/`) and open a pull request. Never commit directly to
the default branch.

---

## Storage

The `attachments` bucket is created by migration: private, 25 MiB limit,
restricted to PDF/PNG/JPEG/WebP, with tenant-scoped access policies. No manual
dashboard setup is required.

Object keys follow:

```
attachments/<organization_id>/<entity_type>/<entity_id>/<uuid>.<ext>
```

Files are served through signed URLs only.

---

## Backup and recovery

Supabase takes managed backups of the linked project. Two things to know before
relying on them:

1. **The ledger is the source of truth and nothing is cached from it.** There
   are no derived balance tables to rebuild after a restore.
2. **Verify a restore against the accounting invariant, not just row counts.**
   For each organization:

   ```sql
   select o.name, public.check_balance_sheet_integrity(o.id)
   from public.organizations o;
   ```

   Every row must report `"balanced": true`. A `false` after a restore means the
   restore is incomplete — treat it as a critical failure, not a rounding issue.
