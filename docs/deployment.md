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

Public acquisition routes are `/` and `/signup`; the authenticated product
starts at `/dashboard`. Before publishing signup, configure the hosted Supabase
Auth confirmation template and Resend SMTP described in the environment guide.
Signup verifies the six-digit OTP, creates the tenant atomically, and starts a
cardless trial. When it expires, a signed Paymob callback restores paid access.

### Phase 4 services

The repository contains four Supabase Edge Functions under
`supabase/functions/`: Paymob checkout, the Paymob webhook, scheduled Resend
delivery, and team invitation email. Deploy them
through the repository's connected Supabase workflow; do not paste function
code or database DDL into the dashboard.

External provider configuration is necessarily separate from database schema:

1. Ask Paymob to enable a MIGS MOTO integration for recurring deductions. Keep
   it distinct from the existing Test online/VPC Integration ID `5902990`.
2. With `PAYMOB_API_KEY` and `PAYMOB_MOTO_INTEGRATION_ID` in the ignored local
   `.env`, provision the 30-day and 360-day plans using:
   `pnpm paymob:provision-plans -- --webhook-url=https://<project-ref>.supabase.co/functions/v1/paymob-webhook`.
3. Add the Edge runtime secrets listed in [environment.md](environment.md),
   including the two plan IDs printed by the provisioning command.
4. Set the Paymob processed callback URL to
   `https://<project-ref>.supabase.co/functions/v1/paymob-webhook`. The checkout
   function also supplies this URL per Intention.
5. Verify the Resend sender domain used by `RESEND_FROM_EMAIL`.
6. Store the two scheduler values in Supabase Vault using the exact names in
   the environment guide. The versioned Cron job detects them automatically.

The same plans are reused for every organization. Each organization completes a
distinct Intention and receives a distinct Paymob subscription, so payment
failure affects only that organization's access.

The current application configuration is:

- monthly subscription: EGP 600
- yearly subscription: EGP 4,800
- application origin: `https://ledger-suit.vercel.app`
- Resend sender: `notification@building-suit.com`

The database also contains a dormant launch catalog. It does not change the
current Paymob integration or move any subscription:

| Plan | Monthly | Annual | Checkout status |
|---|---:|---:|---|
| Solo | EGP 399 | EGP 3,255.84 | cataloged for later activation |
| Starter | EGP 599 | EGP 4,887.84 | cataloged for later activation |
| Business | EGP 1,099 | EGP 8,967.84 | cataloged for later activation |
| Scale | — | — | Coming Soon; not purchasable |

Annual prices are monthly price × 12 × 0.68. Do not provision or enable the six
launch Paymob plans during this catalog-only step. The plan-aware checkout step
will introduce server-side provider mappings and its own production checklist.
The existing two-plan provisioning command remains for the active compatibility
path until that cutover.

The central quota engine is also dormant with respect to product writes until
each resource-specific enforcement migration connects its lowest shared write
boundary. It requires no environment variables or provider configuration. The
public usage functions are safe for organization members; raw plan resolution,
assertions, and advisory-lock helpers remain private to trusted database code.

After migration, a smoke check can confirm the seven-row usage contract for an
organization while signed in as one of its members:

```sql
select *
from public.subscription_usage_summary('<organization-id>');
```

Rollback is achieved by reverting the migration before dependent enforcement
steps are deployed. Once later migrations call these helpers, roll them back in
reverse order first. This migration changes no subscriptions, plan prices,
provider identifiers, or accounting rows.

If the dormant catalog must be withdrawn before checkout activation, set
`is_purchasable = false` and `is_public = false` for `solo`, `starter`,
`business`, and `scale`. Leave their rows and the renamed `legacy_*` rows in
place; deleting or renaming catalog records is unnecessary and makes later
forward migration harder. The private active `ledger_suit` plan remains the
runtime fallback throughout, so this rollback does not change subscriptions,
provider IDs, trials, or accounting access.

These identifiers are sandbox-only. Create a separate live catalog and webhook
when production billing is approved; never reuse test-mode identifiers in live
configuration.

No remote migration command is needed. The linked Git workflow applies the
schema migration; Paymob and Resend credentials remain external secrets by
design.

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
