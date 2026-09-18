# Launch deployment checklist

> **Historical record — not an active plan or current acceptance evidence.** Retained for provenance as of the WP00 audit on 2026-09-18. The canonical [launch master](launch/MASTER_LAUNCH_PLAN.md), [current status](launch/CURRENT_STATUS.md), [consolidated roadmap](launch/ROADMAP.md) and [Accounting V2 plan](accounting-v2/MASTER_PLAN.md) govern current work. Original task ordering, decisions and source text below are preserved; old completion claims and checkboxes do not establish current deployment, UAT or release readiness.

This records the former operational checklist for the Solo, Starter, and Business launch.
The earlier disposable-test-data assertion is NOT VERIFIED at the WP00 audit;
treat all remote data as valuable (DEC-009). Step 21 compatibility subscription
migration remains intentionally deferred. Do not map `ledger_suit` or `legacy_*`
subscriptions. Active gates are now [RELEASE_CHECKLIST](launch/RELEASE_CHECKLIST.md)
and [PRODUCTION_CHECKLIST](launch/PRODUCTION_CHECKLIST.md).

> **Approved new-trial policy.** Current signup creates a cardless 14-day trial
> on the dedicated private `trial` plan, without paid-plan selection. It grants
> Business product capabilities and limits except Priority Support. Skipping
> Step 21 still applies only to existing `ledger_suit` and `legacy_*`
> compatibility subscriptions, which remain unchanged.

## Ownership and evidence

Tareq is the accountable owner for this pre-launch deployment. Record the
operator, UTC timestamp, environment, command output or dashboard screenshot,
and rollback decision in PR #85 (or the release ticket that replaces it).

| Area | Accountable owner | Required evidence |
|---|---|---|
| Paymob catalog and callbacks | Tareq | Six plan IDs, amount/frequency comparison, signed callback result |
| Supabase migrations, secrets, Vault, backup | Tareq | Backup reference, migration status, secret-name checks, SQL verification output |
| App and Edge Function deployment | Tareq | Deployment URLs/versions and function list |
| Production smoke tests | Tareq | Completed EN/AR smoke table with organization IDs redacted |
| Rollback decision and execution | Tareq | Decision time, reason, commands/actions taken, integrity result |

No secret value, customer email, access token, full provider payload, or service
role key belongs in the evidence.

## 1. Release inputs

- [ ] Freeze the commit SHA being promoted from `dev`.
- [ ] Confirm CI is green for lint, typecheck, build, clean migration replay,
  Edge contract tests, pgTAP, database lint, generated-type drift, and Chromium
  E2E.
- [ ] Confirm the application origin and Supabase project reference identify the
  same target environment.
- [ ] Verify new signup provisions exactly one private `trial` subscription for
  14 days with no paid plan, price, provider, interval, or card requirement.
  Do not infer that `ledger_suit` means the new trial or any launch plan.
- [ ] Confirm this is still a pre-launch/test-data deployment. If real customer
  data now exists, stop and add a reviewed data-preservation plan before any
  reset, restore, or catalog correction.
- [ ] Confirm Scale, Enterprise, multi-branch accounting, Advanced Analytics &
  Reporting, and Developer API remain Coming Soon and outside launch scope.

## 2. Backup and rollback gate

- [ ] Record the latest successful Supabase managed-backup/PITR timestamp and
  retention in the project dashboard.
- [ ] Take a logical schema-and-data backup if the target environment is not
  covered by a restorable managed backup.
- [ ] Test restore access in a non-production project and run the accounting
  integrity query from `scripts/verify-launch-readiness.sql` against it.
- [ ] Record the previous app deployment and Edge Function versions that can be
  promoted during rollback.
- [ ] Assign a go/no-go decision time before checkout is exposed.

Rollback order:

1. Disable acquisition without deleting catalog history: set launch plan
   `is_purchasable = false`, then hide checkout entry points or promote the
   previous app deployment.
2. Keep the Paymob webhook deployed while any initiated payment can still
   complete. A verified checkout snapshot must remain fulfillable even if its
   catalog price is later inactive.
3. Roll back Edge Functions and the app to recorded versions only when their
   database contracts remain compatible.
4. Database migrations are forward-only after deployment. Repair with a new
   migration; do not delete migration history or paste unversioned DDL.
5. Restore a backup only for confirmed data corruption, then rerun balance-sheet
   integrity and provider-event idempotency checks before reopening writes.

## 3. Supabase deployment

- [ ] Confirm all committed migrations appear in the linked deployment history;
  do not run `db push` manually against production.
- [ ] Configure these Edge Function secrets together for the target mode:
  `APP_BASE_URL`, `PAYMOB_BASE_URL`, `PAYMOB_SECRET_KEY`, `PAYMOB_PUBLIC_KEY`,
  `PAYMOB_HMAC_SECRET`, `PAYMOB_CARD_INTEGRATION_ID`, the six
  `PAYMOB_<PLAN>_<INTERVAL>_PLAN_ID` values, `RESEND_API_KEY`, and
  `RESEND_FROM_EMAIL`.
- [ ] Confirm platform-provided `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
  `SUPABASE_SERVICE_ROLE_KEY` are available to Edge Functions. Never copy the
  service role key into the browser/app environment.
- [ ] Add Vault entries `ledger_suit_project_url` and
  `ledger_suit_service_role_key`; verify both scheduled jobs can read them
  without exposing their values.
- [ ] Deploy exactly these five functions and verify JWT configuration:

| Edge Function | JWT verification | Invocation |
|---|---|---|
| `paymob-checkout` | on | Authenticated Billing UI |
| `paymob-webhook` | off | Paymob; request is HMAC/metadata verified |
| `send-invitation` | on | Authenticated team management |
| `scheduled-notifications` | off | Vault-authenticated Cron request |
| `storage-cleanup` | off | Vault-authenticated Cron request |

- [ ] Verify `ledger-suit-notification-email` and `ledger-suit-storage-cleanup` are
  active with their committed schedules.
- [ ] Run the read-only verification set as a trusted operator:

  ```bash
  psql "$PRODUCTION_DATABASE_URL" \
    -v ON_ERROR_STOP=1 \
    -f scripts/verify-launch-readiness.sql
  ```

  Every row in the first result set must show `passed = true`. The compatibility
  subscription summary is informational because Step 21 was skipped. Every
  organization must report `unbalanced_journals = 0`.

## 4. Paymob six-plan setup

- [ ] Confirm separate online 3DS/VPC and MIGS MOTO integrations are enabled.
  Never substitute one integration ID for the other.
- [ ] Use credentials from the target Paymob mode and provision/reuse the shared
  plans:

  ```bash
  pnpm paymob:provision-plans -- \
    --webhook-url=https://<project-ref>.supabase.co/functions/v1/paymob-webhook
  ```

- [ ] Compare the provider response and six printed IDs with this exact matrix:

| Plan | Frequency | Provider amount | Database amount | Annual effective monthly |
|---|---:|---:|---:|---:|
| Solo monthly | 30 days | EGP 399.00 | 39,900 minor | EGP 399.00 |
| Solo yearly | 360 days | EGP 3,255.84 | 325,584 minor | EGP 271.32 |
| Starter monthly | 30 days | EGP 599.00 | 59,900 minor | EGP 599.00 |
| Starter yearly | 360 days | EGP 4,887.84 | 488,784 minor | EGP 407.32 |
| Business monthly | 30 days | EGP 1,099.00 | 109,900 minor | EGP 1,099.00 |
| Business yearly | 360 days | EGP 8,967.84 | 896,784 minor | EGP 747.32 |

Annual charge = monthly × 12 × 0.68 (32% discount). The public Pricing and
Billing pages read these database amounts; they show the undiscounted annual
total, discount, annual payment, and effective monthly amount. Scale must show
Pricing coming soon with disabled checkout; Enterprise remains Contact us /
Coming Soon.

- [ ] Put the six mode-specific IDs into Edge Function secrets and redeploy
  `paymob-checkout` if any value changed.
- [ ] Configure the processed callback URL as
  `https://<project-ref>.supabase.co/functions/v1/paymob-webhook`.
- [ ] Confirm callback HMAC secret, charged EGP amount, signed organization,
  plan, interval, price ID, and amount snapshot are all verified before the
  trusted fulfillment RPC runs.
- [ ] Confirm a failed initial transaction preserves an unexpired trial and a
  later verified success creates/activates exactly one subscription.

## 5. Application deployment

- [ ] Configure app runtime values `SUPABASE_URL`, `SUPABASE_KEY`, and
  `APP_BASE_URL`; configure `SUPABASE_SERVICE_KEY` only if a server-only Nuxt
  path actually uses it.
- [ ] Confirm hosted Auth email confirmation, six-digit OTP template, Resend
  custom SMTP, allowed redirect URLs, and verified sender domains.
- [ ] Deploy the frozen app commit after the database and Edge Function
  contracts are available.
- [ ] Verify the deployed app reports no missing localization keys in English or
  Arabic and does not expose raw `ledger_suit` machine copy.

## 6. Production smoke tests

Use fresh smoke-test organizations and inert payment instruments. Do not edit
real financial history to manufacture a result.

| Test | Expected result | Done |
|---|---|---|
| Public Pricing, English and Arabic/RTL | Solo/Starter/Business exact prices; yearly switch and 32% presentation correct | [ ] |
| Scale and Enterprise | No checkout route; disabled Coming Soon / Contact us presentation | [ ] |
| New cardless trial | Signup assigns private `trial` for 14 days with no paid-plan selection or payment; Business product limits/features apply except Priority Support | [ ] |
| Trial expiry and conversion | Expiry preserves readable history and billing management while blocking writes; verified checkout activates the exact selected Solo/Starter/Business plan without restarting the trial | [ ] |
| Checkout success | Correct signed price snapshot creates/activates one subscription and returns to Billing | [ ] |
| Initial checkout failure | Trial plan/status/end date remain unchanged; failure is recorded | [ ] |
| Renewal failure and recovery | Grace/read-only lifecycle follows the existing provider callback contract | [ ] |
| Quota warning and hard limit | 80%, 95%, and reached states localize; direct/RPC bypass remains blocked | [ ] |
| CSV quota error | Import meter refreshes and localized transaction-limit error appears | [ ] |
| Audit history | Solo 90, Starter 365, Business 1095; `ledger_suit` remains unlimited | [ ] |
| Attachment lifecycle | Reserve/upload/finalize/delete works; direct metadata writes remain revoked | [ ] |
| Scheduler | Due recurring posting is idempotent and plan/quota enforcement applies | [ ] |
| Downgrade preflight | Gains/losses and audit-window direction display without deleting or mutating data | [ ] |
| Expired subscription | Financial history remains readable while writes are blocked | [ ] |
| Tenant isolation | A second organization cannot read or mutate the first organization's records | [ ] |
| Arabic invalid import row | RTL issue text is localized from stable error code | [ ] |

After smoke testing, rerun `scripts/verify-launch-readiness.sql`, archive the
redacted evidence, and record the final go/no-go decision.

## 7. Explicitly deferred work

The following are not launch claims and must stay labeled Coming Soon:

- Scale purchasing and high-volume/multi-location behavior;
- Enterprise purchasing and tailored deployment automation;
- multi-branch accounting;
- Advanced Analytics & Reporting beyond current core reports/exports;
- Developer API access;
- automatic Paymob plan changes (current flow is impact preflight plus manual
  handoff only); and
- migration of `ledger_suit` / `legacy_*` subscriptions to launch plans.

Do not enable an entitlement, expose checkout, or market these as delivered
until a separate reviewed implementation is merged.
