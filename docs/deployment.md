# Deployment

## Database

The intended repository workflow uses linked Supabase deployment to apply
committed migrations. WP00 did not verify the actual target, connection, applied
versions or deployment automation. Repository migrations describe intended schema,
not proof of the production schema. Before promotion use
[PRODUCTION_CHECKLIST](launch/PRODUCTION_CHECKLIST.md) to establish target identity,
applied history and backup/restore evidence. In particular, historical
`20260908120000_user_managed_chart_of_accounts.sql` contains destructive TRUNCATE;
never apply a pending copy to valuable data without a reviewed preservation plan.

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
pnpm db:reset     # ONLY a newly created disposable LOCAL database, then seed
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
cardless 14-day subscription on the private `trial` plan. The trial grants the
Business product limits and capabilities except Priority Support, requires no
paid-plan selection, and becomes read-only at expiry. A verified Paymob
checkout for Solo, Starter, or Business restores write access.

### Phase 4 services

The repository contains five Supabase Edge Functions under
`supabase/functions/`: Paymob checkout, the Paymob webhook, scheduled Resend
delivery, team invitation email, and orphaned-storage cleanup. Deploy them
through the repository's connected Supabase workflow; do not paste function
code or database DDL into the dashboard.

The final operator sequence, six-plan comparison, rollback gate, verification
queries, and production smoke matrix are in
[launch-deployment-checklist.md](launch-deployment-checklist.md).

External provider configuration is necessarily separate from database schema:

1. Ask Paymob to enable a MIGS MOTO integration for recurring deductions. Keep
   it distinct from the existing Test online/VPC Integration ID `5902990`.
2. With `PAYMOB_API_KEY` and `PAYMOB_MOTO_INTEGRATION_ID` in the ignored local
   `.env`, provision the six launch plan/interval combinations using:
   `pnpm paymob:provision-plans -- --webhook-url=https://<project-ref>.supabase.co/functions/v1/paymob-webhook`.
3. Add the Edge runtime secrets listed in [environment.md](environment.md),
   including the six plan IDs printed by the provisioning command.
4. Set the Paymob processed callback URL to
   `https://<project-ref>.supabase.co/functions/v1/paymob-webhook`. The checkout
   function also supplies this URL per Intention.
5. Verify the Resend sender domain used by `RESEND_FROM_EMAIL`.
6. Store the two scheduler values in Supabase Vault using the exact names in
   the environment guide. The versioned Cron job detects them automatically.

The same plans are reused for every organization. Each organization completes a
distinct Intention and receives a distinct Paymob subscription, so payment
failure affects only that organization's access.

The production checkout catalog is:

| Plan | Monthly | Annual | Checkout status |
|---|---:|---:|---|
| Solo | EGP 399 | EGP 3,255.84 | purchasable |
| Starter | EGP 599 | EGP 4,887.84 | purchasable |
| Business | EGP 1,099 | EGP 8,967.84 | purchasable |
| Scale | — | — | Coming Soon; not purchasable |

Annual prices are monthly price × 12 × 0.68. Before enabling checkout, confirm
all six Paymob plan IDs are configured as Edge Function secrets, each provider
amount matches this table, and both Test and Live environments use identifiers
from their own Paymob mode. The private `trial` plan has no price or provider
mapping. Existing `ledger_suit` and `legacy_*` subscriptions are not migrated
by this deployment and continue through their existing compatibility contracts.

In-app plan changes are intentionally preflight-only. Billing managers on Solo,
Starter, or Business can use
`plan_change_impact(organization_id, target_plan_key, target_interval)` to see
all quota, feature, and audit-window consequences without mutating the
subscription. The checked-in Paymob contract does not establish a verified
plan-change operation, so the Billing page hands the request to an
administrator and keeps the current plan active. Do not update the database or
claim a completed change until Paymob confirms a supported production process
and a matching verified fulfillment boundary is implemented. This restriction
also avoids preempting the separately approved Step 21 `ledger_suit` migration.
The RPC rejects `ledger_suit`, `legacy_*`, and other compatibility plans with
`LEGACY_PLAN_TRANSITION_NOT_APPROVED`; their Billing view remains informational.

The central quota and feature engines are enforced at the implemented shared
resource-write boundaries. Organization-scoped advisory locks serialize quota-
and feature-gated writes with physical plan transitions, so a concurrent
downgrade cannot leave forbidden post-transition state. The engines require no
environment variables or provider configuration. Public usage functions are
safe for organization members; raw plan resolution, assertions, and lock
helpers remain private to trusted database code.

After migration, a smoke check can confirm the seven-row usage contract for an
organization while signed in as one of its members:

```sql
select *
from public.subscription_usage_summary('<organization-id>');
```

Deployed migrations are forward-only. Correct a deployed schema or enforcement
problem with a new reviewed migration; never revert migration history. To stop
new sales safely, disable acquisition and mark launch plans non-purchasable
without deleting catalog or subscription history. Restore a backup only to
recover from confirmed data corruption, then rerun the accounting-integrity and
provider-event idempotency checks before reopening writes. The complete rollback
sequence is maintained in the final launch checklist.

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

Managed backup availability, retention and restore access for the actual target
are NOT VERIFIED in WP00. Record and rehearse them before relying on recovery.
Two accounting checks to include:

1. **The ledger is the source of truth and nothing is cached from it.** There
   are no derived balance tables to rebuild after a restore.
2. **Verify a restore against the accounting invariant, not just row counts.**
   For each organization:

   ```sql
   select o.name, public.check_balance_sheet_integrity(o.id)
   from public.organizations o;
   ```

   Every row must report `"balanced": true`. A false result requires investigation
   and blocks reopening; it does not uniquely diagnose an incomplete restore.
   Compare independent journal/GL/report controls as well as storage objects,
   Auth ownership and provider events; aggregate equality alone is insufficient.
