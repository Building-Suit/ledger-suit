# Production checklist

Status: NOT STARTED; deployment verification NOT VERIFIED. Accountable owner: Tareq. Historical operator sequence in [former checklist](../launch-deployment-checklist.md) is preserved for detail, not an independent active gate. Treat all remote data as valuable.

## Before promotion

- [ ] PROD-01 Map staging and production app origins to Supabase project refs from trusted owner/configuration evidence; record responsible operator and access. Do not choose by similar project name.
- [ ] PROD-02 Record actual migration history/checksums against intended chain; investigate drift and historical destructive migrations. No remote reset/db push/unversioned DDL. Repository code does not prove applied state.
- [ ] PROD-03 Record managed backup/PITR timestamp/retention; restore isolated copy, include storage/Auth and provider-event reconciliation; measure approved RPO/RTO. Record compatible previous app/Edge versions.
- [ ] PROD-04 Verify secret names/mode only: APP_BASE_URL, Paymob secret/public/HMAC/card integration and six plan mappings, Resend key/sender, platform Supabase variables. Never record values. Verify distinct online-card and MOTO settings, exact six amounts, frequency and calendar period semantics with provider evidence.
- [ ] PROD-05 Hosted OTP/confirmation template, SMTP/domain, redirects and email retry tested. Vault names ledger_suit_project_url and ledger_suit_service_role_key configured; cron authorization/schedules verified without exposing values.
- [ ] PROD-06 Verify five Edge deployments: paymob-checkout and send-invitation JWT on; paymob-webhook HMAC/metadata verification with JWT off; scheduled-notifications/storage-cleanup JWT off with their server-secret boundary verified. Version and smoke each.
- [ ] PROD-07 All RELEASE_CHECKLIST gates signed before promotion; preserve initiated checkout fulfillment and compatibility subscriptions. No automatic migration of ledger_suit/legacy_* customers.

## After authorized deployment

- [ ] PROD-08 App loads; login/OTP/company ownership and tenant switch work; no client secret leakage or unexpected errors.
- [ ] PROD-09 Fresh designated smoke tenant: post controlled journal, debit=credit, GL and TB reconcile, P&L loads, position balances, contra/group/period guards and cross-tenant denial hold. No modifications of real history to manufacture a result.
- [ ] PROD-10 Verify private 14-day Business-level trial (except Priority Support), no card at signup, expiry reads/writes, checkout exact selected paid plan, failure preserves valid trial, renewal/grace/cancel behavior and duplicate callbacks.
- [ ] PROD-11 Quota warnings and direct enforcement, CSV partial/retry, five report CSV exports, append-only audit visibility, attachment reservation/upload/finalize/delete and scheduled posting are verified.
- [ ] PROD-12 Trusted operator runs scripts/verify-launch-readiness.sql read-only on confirmed target, archives redacted aggregates, and compares independent accounting controls. Script alone does not sign off V2 or legal readiness.
- [ ] PROD-13 Observe error/failure/latency metrics, support inbox and payment queue; record go/no-go and rollback decision. Close only after accountant/release-owner reconciliation.

Containment/repair follows [Accounting rollback](../accounting-v2/ROLLBACK_PLAN.md). Disable new acquisition safely if necessary, retain verified webhook fulfillment, prefer forward schema repair and linked correcting journals. No broad restore without explicit recovery-point/data-preservation approval.
