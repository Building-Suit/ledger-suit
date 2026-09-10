# Launch plans and entitlements: audit and execution plan

Status: implementation plan

Audited branch: `origin/dev`

Audited commit: `60d3d5f9e82985337165b15216ea482b794ecd62`

Audit date: 2026-09-10

## 1. Executive summary

Ledger Suit has a strong tenant-safe accounting core, a provider-agnostic
subscription schema, centralized feature/limit lookup functions, a cardless
14-day trial, database-authoritative subscription write gating, and a working
Paymob subscription integration. The launch-plan work should extend these
foundations rather than replace them.

The commercial implementation is not launch-ready yet. The current product has
one public, active, unlimited `ledger_suit` plan. Checkout accepts only an
organization and billing interval, Paymob amounts and plan identifiers are
selected from one monthly/yearly pair of environment variables, and Paymob
webhooks always attach the legacy plan. None of the launch quotas is enforced.
The public page advertises EGP 600 monthly or EGP 4,800 yearly rather than the
agreed Solo, Starter, and Business catalog.

The safest path is incremental:

1. preserve the legacy plan and all existing subscription/provider identifiers;
2. add the launch catalog without moving customers;
3. add a shared, concurrency-safe quota foundation;
4. enforce one resource at a time through focused pull requests;
5. complete gated product features;
6. change checkout only after the plans it sells are enforced; and
7. migrate existing subscriptions only under an approved transition policy.

No launch migration should delete or rewrite accounting history.

## 2. Validated baseline

The latest `origin/dev` was replayed in an isolated worktree. The following
checks pass before launch work begins:

| Check | Result |
|---|---:|
| `pnpm lint` | pass |
| `pnpm typecheck` | pass |
| `pnpm build` | pass |
| `pnpm db:reset` | pass; all migrations replay cleanly |
| `pnpm db:test` | pass; 158 pgTAP assertions across 9 files |
| `pnpm db:lint` | pass; no schema warnings |
| `pnpm test:e2e` | pass; 22 Chromium tests |

The first database reset can spend roughly one minute initializing and
restarting local containers. A test command started before reset finishes sees
an incomplete schema; validation jobs must wait for reset completion.

## 3. Current-state audit

### 3.1 Plans, entitlements, and subscription access

| Area | Current state | Launch gap |
|---|---|---|
| Plan schema | `subscription_plans`, `subscription_plan_prices`, `subscription_entitlements`, and one subscription per organization exist. | There is no explicit purchasable flag. Public/active alone cannot cleanly represent an active preview-only Scale plan. |
| Catalog | Old `free`, `starter`, and `business` rows exist but are inactive/private. One public active `ledger_suit` plan is used. | Solo is absent; old prices/entitlements differ from the launch matrix; Scale is absent; the legacy plan is unlimited. |
| Prices | Old unused prices exist in the database. The live legacy plan has no active catalog price rows. | Add the six EGP launch prices. Do not expose provider identifiers in a client-readable catalog. |
| Entitlement lookup | `can_use_feature(org, key)` and `get_limit(org, key)` are centralized and tenant checked. | They are lookup functions, not enforcement. `get_limit` also folds subscription write access into the result, so internal quota evaluation needs a separate plan-limit primitive. |
| Subscription state | Trialing/active/grace writes are allowed; lapsed subscriptions retain data and billing access. | After trial expiry, current capability filtering removes product reads as well as writes, despite architecture copy that says financial history remains readable. The launch requirement is readable history plus blocked writes. |
| Trials | Organization creation starts a cardless 14-day trial on `ledger_suit`. | Trial plan/limits after the launch catalog are not specified. An older `complete_account_onboarding_with_plan` RPC remains deployed but unused after cardless-signup repairs. |
| Owned organizations | A trigger enforces one active owned organization using `max_owned_organizations` and an advisory lock. | The launch matrix does not price this resource. Preserve one owned organization for all launch plans unless product direction changes. |

The existing `ledger_suit` entitlement set is unlimited for members,
transactions, storage, recurring rules, multi-currency, reports, imports,
exports, audit history, and API access. It does not yet contain account,
counterparty, custom-role, core-report, priority-support, branch, or advanced
analytics keys.

### 3.2 Checkout and payment-provider boundary

- The browser invokes `paymob-checkout` with `{ organizationId, interval }`.
- The database authorizes billing management and returns organization/customer
  context, but it does not resolve a plan or commercial price.
- The Edge Function selects a single Paymob plan ID and amount from
  `PAYMOB_MONTHLY_*` or `PAYMOB_YEARLY_*` environment variables.
- The client cannot currently submit an arbitrary amount, which is good, but it
  also cannot choose Solo, Starter, or Business.
- The webhook validates Paymob HMACs, records idempotent billing events, and
  preserves an opaque Paymob subscription ID.
- Every successful callback assigns `ledger_suit`; callback metadata contains
  interval but no authoritative plan key or provider-plan mapping.
- The database model is mostly provider agnostic. Provider-specific
  configuration remains in Edge Functions/environment variables, while opaque
  provider identifiers are stored in billing tables.
- There is no implemented in-app upgrade, downgrade, cancellation, or provider
  plan-change flow.

### 3.3 Members and invitations

- Active/suspended memberships and pending/accepted/revoked/expired invitations
  exist.
- Invitation creation and acceptance use controlled RPCs. Pending invitation
  email uniqueness prevents duplicate pending invites for the same address.
- Member activation/status changes use a controlled RPC.
- No seat count is checked. Concurrent invitations for different emails can
  exceed any proposed limit.
- Pending invitations do not currently reserve capacity.

Launch rule: count active members plus unexpired pending invitations. Suspended
members do not consume an active seat. A pending invitation reserves a seat
until accepted, revoked, or expired. Acceptance must re-check under the same
organization-scoped lock so a stale invitation cannot exceed quota.

### 3.4 Roles

- Five built-in roles exist, and their workspace-specific capability sets can
  be edited.
- Organization-created custom roles use `organization_roles`; system roles are
  not stored there.
- Custom-role create/update/delete operations use controlled RPCs and preserve
  member assignments.
- No custom-role quota is enforced.

Launch rule: count every organization-created custom role. Built-in role
overrides do not count. Downgrades never remove roles or invalidate assignments;
only creation is blocked while usage is at or above the plan limit.

### 3.5 Accounts

- Accounts are created, updated, and archived through controlled RPCs.
- New workspaces start with an empty user-managed chart of accounts.
- Revenue/expense account creation may also create or reactivate a matching
  category, but that category is not another account.
- Archived accounts retain history and can remain visible.
- No account quota is enforced.

Launch rule: count all account rows, including archived accounts. There is no
hard delete path for normal users, and archiving must not create quota capacity.

### 3.6 Counterparties

- Counterparties are tenant-scoped and may be archived.
- Creation currently uses direct PostgREST insert authorized by RLS, not a
  controlled creation RPC.
- No counterparty quota or creation audit entry exists.

Launch rule: count all counterparty rows, including archived rows. Move creation
behind a controlled RPC (and retain a database trigger as defense in depth if
direct insert remains grantable) so quota, locking, validation, and audit share
one server-authoritative path.

### 3.7 Recurring rules

- Rules support active, paused, completed, and failed states.
- Creation and state changes use controlled RPCs; occurrences and transaction
  posting are idempotent.
- The scheduler locks rule rows, and recurring-generated transactions use the
  ordinary posting engine.
- No recurring-rule quota is enforced.

Launch rule: active, paused, and failed rules count because each can be resumed
or retried. Completed rules do not count because they cannot generate another
occurrence. A completed rule must not be made active when doing so would exceed
quota.

### 3.8 Transactions

- `transactions` represent customer-visible business events;
  `transaction_entries` are double-entry ledger lines.
- Clients cannot write transaction or entry tables directly. Controlled RPCs
  create drafts, validate journals, post, reverse, and void.
- Product flows, recurring occurrences, and commitment conversions all converge
  on the posting engine. Idempotency keys are unique per organization.
- Reversals create a distinct posted transaction. Drafts may be voided. Failed
  calls roll back atomically.
- No monthly quota or usage bucket exists.

Launch rule: consume quota when a business transaction first becomes posted,
using `posted_at`, never the editable accounting date and never ledger-line
count. Drafts, voids, and rolled-back failures consume nothing. Recurring and
imported transactions count exactly like manual transactions. Reversals count
as posted business events. Idempotent retries return the original transaction
and consume no second unit. Historical rows are never removed.

The usage month should be represented by explicit immutable bucket boundaries,
not recalculated from mutable provider state. The recommended policy is a
workspace-timezone calendar month because it stays understandable across
monthly and annual billing. If commercial billing-month anchoring is required
instead, approve that before the transaction-quota step.

### 3.9 Attachments and storage

- Attachment objects are private and tenant-prefixed. Storage policies check
  membership/capabilities.
- Metadata enforces a 25 MiB per-file cap and four MIME types.
- The browser uploads the object first, then inserts metadata; it attempts to
  remove the object if metadata insertion fails.
- Aggregate usage is not measured. Concurrent uploads are not serialized.
- A browser/network failure between object upload and metadata insert can leave
  an orphan object, and deleting the object before metadata can leave stale
  metadata if the second operation fails.

Launch implementation needs a reservation/commit/abort protocol. Reserve bytes
under an organization lock before upload, authorize the exact object key through
the reservation, then commit metadata or expire/clean the reservation and
object. Usage must include committed metadata plus live reservations so
concurrent uploads cannot overbook storage. Existing per-file checks stay.

### 3.10 Multi-currency

- The accounting core already stores organization base currency, account
  currency, transaction/entry currency, exchange rates, and immutable base
  amounts. Reports aggregate base amounts correctly.
- Posting functions accept non-base currencies/exchange rates, and account
  creation accepts any active currency at the RPC boundary.
- The current account UI sends base currency and transaction forms display base
  currency, but direct RPC calls can create non-base-currency activity.
- Commitments, recurring templates, transfers, adjustments, opening balances,
  and future imports are alternate paths that must be covered.
- The legacy plan currently enables multi-currency without limit.

Launch enforcement must be database-authoritative. Solo and Starter may read
pre-existing foreign-currency history but cannot create or reactivate a
non-base-currency account, transaction, entry, commitment, recurring template,
or imported row. Business may. Existing foreign-currency rows must not be
rewritten during plan changes.

### 3.11 Imports

- `imports.create` exists as a capability, `imports` exists as an entitlement
  key, `import` exists as a transaction source/attachment entity type, and
  idempotency was designed with imports in mind.
- There is no import table, parser, preview, mapping workflow, posting service,
  page, or test. Imports are scaffolded, not customer-usable.

The honest launch scope should be CSV transaction import only: staged upload,
parse, preview/mapping, row validation, deterministic duplicate keys, explicit
confirmation, recoverable batch posting, row-level results, audit records, and
tenant/plan enforcement. Solo must be rejected server-side before staging and
again before posting.

### 3.12 Exports and reports

- The database and UI implement dashboard balances, Trial Balance, Profit &
  Loss, Balance Sheet, Cash Flow, and General Ledger.
- These reports are protected by normal report-read capability, not a plan
  entitlement, which aligns with keeping core reports available to all plans.
- Only Profit & Loss and Balance Sheet have CSV buttons. CSV serialization is
  client-side after an authorized report RPC.
- `reports.export` and `exports.create` capabilities exist, but there is no
  organization-data export workflow and no plan-entitlement check on report CSV.

Launch copy should say **Export financial reports to CSV**. Complete CSV export
for all five report views and enforce `exports` server-side through an export
RPC or signed server response. Do not claim full organization-data export.

### 3.13 Audit history

- `audit_logs` is append-only and tenant-readable with `audit.read`.
- There is no customer-facing audit-log page in the application.
- There is no retention/visibility enforcement or deletion job. The legacy
  entitlement is unlimited.

For launch, interpret the entitlement as an **audit history visibility window**
of 90/365/1095 days. Keep all audit records physically append-only until legal,
security, support, and backup requirements approve deletion. Apply the window in
a tenant-safe RPC/view and explain it accurately in pricing copy.

### 3.14 Branches, analytics, API, support, and plan previews

- `transaction_entries.dimensions` preserves a future foundation for branch,
  project, and cost-center attribution. There is no branch domain model or
  branch-aware accounting.
- Existing core reports are complete; there is no separate advanced analytics
  product.
- `api_access` is only an entitlement key. There are no customer API keys,
  scopes, revocation, rate limits, versioned contract, or public docs.
- There is no support workflow. Priority support can remain an entitlement and
  operational promise without a technical queue or SLA.
- Scale and Enterprise are not represented in the live UI.

Launch UI must mark Multi-branch accounting, Advanced Analytics & Reporting,
and Developer API as Coming Soon. Scale may be a non-purchasable preview.
Enterprise should be a separate Contact us / Coming Soon block, not an ordinary
subscription plan, and no unverified SLA or infrastructure claim should appear.

### 3.15 Localization, generated types, and tests

- The app uses English/Arabic JSON locales, RTL-aware logical CSS, localized
  dates, and centralized money formatting.
- Current billing and public pricing text is localized but hard-coded around
  the single EGP 600 / EGP 4,800 plan.
- Generated database types include the subscription tables/RPCs and are checked
  by application typecheck, but must be regenerated after each schema-changing
  step.
- CI runs lint, typecheck, build, clean database replay, pgTAP, database lint,
  and Chromium E2E.
- Existing tests cover accounting integrity, tenant isolation, recurring
  idempotency, subscription expiry/activation, signup, workspace access, roles,
  billing navigation, and core workflows. They do not cover the launch catalog,
  resource quotas, quota races, import/export entitlements, multi-currency plan
  restrictions, usage meters, downgrade behavior, or launch pricing.

## 4. Shared implementation rules

### 4.1 Catalog and plan resolution

- Add an explicit `is_purchasable` attribute (or equivalently named invariant)
  so public visibility is independent of checkout eligibility.
- Keep `ledger_suit` private and active while any subscription references it.
  Do not delete it and do not reuse its key for a launch plan.
- Seed `solo`, `starter`, `business`, and preview-only `scale` idempotently.
  Enterprise should remain presentation/contact data, not a fabricated plan.
- Store commercial amounts in `subscription_plan_prices`. Resolve provider
  configuration only on the server. Expose a safe catalog projection/RPC that
  omits provider mapping fields.
- Checkout resolves `(plan key, interval, EGP)` to one active purchasable plan
  and its server-side provider configuration. The browser never supplies an
  amount or provider price/plan ID.
- Webhook metadata and persistence must bind the provider subscription back to
  the resolved plan, not merely trust a client-supplied key.

### 4.2 Quota and concurrency model

- Keep public, tenant-checked `can_use_feature`, `get_limit`, and usage-summary
  APIs for UI use.
- Add private plan-limit and assertion helpers for trusted triggers/RPCs. They
  must not depend on client membership and must distinguish subscription access
  from plan limit.
- Serialize quota-increasing writes with transaction-scoped advisory locks
  derived from organization ID plus a stable resource discriminator. Recount
  under the lock before the write. The existing owned-organization trigger is a
  useful precedent.
- Put enforcement at the lowest shared database boundary that covers direct
  PostgREST, RPC, Edge Function, scheduler, and service paths. UI preflight is
  informative only.
- Missing entitlements on the private legacy plan remain unlimited during the
  transition; launch plans must have every required entitlement explicitly.
- Return stable error prefixes such as `PLAN_ACCOUNT_LIMIT_REACHED` and map
  them to localized messages and upgrade actions.
- Usage APIs report the same counting predicate used by enforcement.
- At/above-limit resources remain readable. Only writes that increase usage are
  blocked. Updates, archival, safe suspension/revocation, and accounting
  corrections remain possible according to the per-resource rule.

### 4.3 Launch entitlement matrix

| Key | Solo | Starter | Business |
|---|---:|---:|---:|
| `max_members` | 1 | 3 | 10 |
| `max_monthly_transactions` | 500 | 2,500 | 10,000 |
| `max_storage_bytes` | 1,073,741,824 | 5,368,709,120 | 21,474,836,480 |
| `max_accounts` | 30 | 100 | 300 |
| `max_counterparties` | 100 | 1,000 | 5,000 |
| `max_recurring_rules` | 5 | 25 | 100 |
| `max_custom_roles` | 0 | 3 | 10 |
| `audit_log_retention_days` | 90 | 365 | 1,095 |
| `multi_currency` | false | false | true |
| `imports` | false | true | true |
| `exports` | true | true | true |
| `core_reports` | true | true | true |
| `priority_support` | false | false | true |
| `branches` | false | false | false |
| `advanced_analytics` | false | false | false |
| `api_access` | false | false | false |
| `max_owned_organizations` | 1 | 1 | 1 |

Storage values use binary gigabytes because the existing storage limit is in
bytes and the UI can label them as GB consistently.

### 4.4 Launch pricing formula

Monthly prices remain EGP 399 for Solo, EGP 599 for Starter, and EGP 1,099 for
Business. Every annual price is calculated from its monthly price with a 32%
discount on twelve monthly payments:

```text
annual price = monthly price × 12 × 0.68
```

| Plan | Monthly | Annual before discount | 32% discount | Final annual price |
|---|---:|---:|---:|---:|
| Solo | EGP 399 | EGP 4,788 | EGP 1,532.16 | EGP 3,255.84 |
| Starter | EGP 599 | EGP 7,188 | EGP 2,300.16 | EGP 4,887.84 |
| Business | EGP 1,099 | EGP 13,188 | EGP 4,220.16 | EGP 8,967.84 |

The catalog stores these as integer minor-unit amounts: `325584`, `488784`,
and `896784`. For reference, a plan priced at EGP 600 monthly produces EGP
4,896 annually under the same formula. The formula is authoritative if a
monthly price changes; annual amounts must not be independently hard-coded.

## 5. Business decisions required before customer migration

These decisions cannot be inferred safely from the repository. They do not
block adding a dormant launch catalog or building enforcement, but they block
moving existing subscriptions and enabling multi-plan checkout in production.

1. **Existing paid `ledger_suit` customers:** choose whether each customer is
   mapped to Solo, Starter, or Business; retained indefinitely on a private
   grandfathered unlimited plan; or retained for a time-limited transition.
   The recommended safe default is grandfathering until an explicit customer
   mapping is approved.
2. **Existing trial organizations:** choose whether current trials remain
   unlimited until checkout, adopt one launch plan during the remaining trial,
   or select a plan before continuing. The recommended least-disruptive option
   is to keep current trials on the legacy plan and require plan selection at
   checkout.
3. **New trial experience:** choose whether a new workspace selects an intended
   plan at signup or receives a Business-feature trial and selects at checkout.
   This affects when plan limits and Business-only multi-currency apply.
4. **Already over-limit organizations:** approve grandfathering or ordinary
   downgrade behavior per organization. In either case no data is deleted. An
   ordinary mapping immediately blocks only usage-increasing actions.
5. **Transaction usage month:** confirm the recommended organization-timezone
   calendar month or request billing-anniversary buckets. The former is clearer
   for annual plans and operational support.

Before the catalog migration is deployed, take a read-only production snapshot
of plan/subscription/provider status and per-resource usage. Provider IDs and
billing dates must be preserved. Rollback is achieved by leaving subscriptions
on/reactivating the private legacy plan and disabling launch-plan purchase; it
must not require reversing accounting data.

## 6. Numbered execution plan

Each numbered item is one focused branch and one pull request targeting `dev`.
Every PR must be squash-merged into `dev` before the next step starts. The agent
does not merge the PR; it stops for review and waits for confirmation. When the
user approves moving on, the agent first verifies that the prior PR is merged,
fetches the updated remote, confirms the squash commit is present in
`origin/dev`, and creates the next feature branch from that exact latest
`origin/dev` state. Stacked implementation PRs are not used. This keeps every
new branch and validation run based on all previously accepted launch work.
Branch names are suggestions and may be adjusted to repository convention.

### Step 1 — Current-state audit and launch execution plan

Branch: `codex/launch-readiness-audit`

- Version this audit, quota semantics, migration decision gate, validation
  baseline, and independently reviewable PR sequence.
- No production schema or runtime behavior changes.
- Validate Markdown scope plus the full existing baseline.

### Step 2 — Launch catalog schema and dormant plan rows

Branch: `feat/launch-plan-catalog`

- Add explicit checkout eligibility to plans and constraints that prevent an
  inactive/non-purchasable plan from being selected.
- Seed Solo, Starter, Business, and preview-only Scale with exact prices and
  entitlements; keep Enterprise out of checkout data.
- Keep `ledger_suit` active/private and all current subscriptions untouched.
- Add a safe catalog RPC/projection without provider identifiers; tighten direct
  catalog table access where needed.
- Add pgTAP coverage for prices, entitlements, public visibility, and
  non-purchasability; regenerate database types and document rollback.

### Step 3 — Central quota and usage engine

Branch: `feat/plan-quota-engine`

- Separate private raw plan resolution from subscription write access.
- Add standardized feature/quota assertions, stable error codes, advisory-lock
  key strategy, and tenant-safe usage summary contracts.
- Preserve `can_use_feature`/`get_limit` compatibility for existing callers.
- Test missing/zero/unlimited limits, cross-tenant access, lapsed subscription
  separation, downgrade-over-limit behavior, and concurrent assertion helpers.

### Step 4 — Subscription expiry readable-history correction

Branch: `fix/subscription-read-only-access`

- Align capability filtering with the stated read-only contract: retain product
  reads and billing management after expiry while blocking mutations.
- Prove reports, transactions, accounts, and attachments metadata remain
  readable and all representative writes remain blocked.
- Update architecture, localized UI copy, pgTAP, and E2E coverage.

### Step 5 — Member and invitation seat quota

Branch: `feat/member-quota-enforcement`

- Enforce active members plus unexpired pending invitations under an
  organization-scoped lock in invitation creation, acceptance, renewal, and
  suspended-to-active transitions.
- Allow revocation/suspension/removal while over limit and preserve all members
  on downgrade.
- Add exact Solo/Starter/Business boundary tests and a true concurrent-session
  race test.

### Step 6 — Account quota

Branch: `feat/account-quota-enforcement`

- Enforce all account rows, including archived accounts, at the controlled
  account-creation boundary with defense-in-depth database enforcement.
- Ensure automatic category creation does not affect account usage.
- Test limits, concurrency, archive non-bypass, tenant isolation, and downgrade
  readability.

### Step 7 — Counterparty controlled creation and quota

Branch: `feat/counterparty-quota-enforcement`

- Add an audited creation RPC, update the UI to use it, and remove unnecessary
  direct insert authority if compatible with existing paths.
- Count archived counterparties and serialize concurrent creation.
- Test limits, concurrency, archive non-bypass, stable errors, and tenant
  isolation.

### Step 8 — Recurring-rule quota

Branch: `feat/recurring-quota-enforcement`

- Count active, paused, and failed rules; exclude completed rules.
- Enforce on creation and completed-to-live reactivation under a lock.
- Preserve occurrences/generated transactions and allow status changes that
  reduce usage.
- Test all state transitions, concurrency, scheduler compatibility, and
  downgrade behavior.

### Step 9 — Custom-role quota

Branch: `feat/custom-role-quota-enforcement`

- Count only `organization_roles`, not system-role overrides.
- Enforce zero/three/ten creation limits under a lock.
- Preserve member/invitation assignments and allow safe role deletion while
  over limit.
- Add pgTAP and team-page E2E coverage.

### Step 10 — Aggregate attachment storage quota

Branch: `feat/storage-quota-enforcement`

- Add storage reservations with expiration, exact key/size/MIME binding, and
  reserve/commit/abort/cleanup operations.
- Include committed bytes plus live reservations in usage while holding the
  organization storage lock.
- Update upload/delete ordering so failed operations are recoverable and orphan
  objects/reservations are cleaned.
- Retain the 25 MiB per-file rule.
- Test concurrent reservations, tenant isolation, over-limit downgrade,
  metadata failure cleanup, orphan cleanup, and idempotent abort/commit.

### Step 11 — Monthly posted-transaction quota

Branch: `feat/transaction-quota-enforcement`

- Add immutable monthly usage buckets under the approved month policy.
- Enforce at the shared transition to `posted` so manual flows, adjustments,
  reversals, recurring occurrences, commitment conversions, and future imports
  cannot bypass it.
- Count one posted business transaction, not ledger entries; drafts/voids/
  failures do not count; idempotent retries do not double-count.
- Test period rollover, backdating, all posting sources, exact boundaries,
  rollback, idempotency, concurrency, and downgrade safety.

### Step 12 — Business-only multi-currency enforcement

Branch: `feat/business-multi-currency`

- Add a private assertion shared by account, transaction, entry, commitment,
  recurring, adjustment, opening-balance, transfer, and import paths.
- Solo/Starter writes must use organization base currency; Business may use the
  existing exchange-rate engine.
- Keep existing non-base records readable and immutable after downgrade.
- Expose currency controls only for Business and localize upgrade messaging.
- Test direct RPC/API bypasses and every alternate posting path.

### Step 13 — CSV import staging and validation backend

Branch: `feat/csv-import-backend`

- Add tenant-scoped import batches/rows, server-side Starter/Business
  entitlement checks, schema/mapping validation, deterministic duplicate keys,
  row-level errors, and audited confirmation.
- Reuse ordinary posting and transaction quota paths.
- Define recoverable batch semantics: invalid rows never post; confirmed valid
  rows have deterministic outcomes and retries cannot duplicate them.
- Test Solo rejection, malformed data, tenant isolation, quota exhaustion,
  partial/retry behavior, and multi-currency restriction.

### Step 14 — Customer CSV import workflow

Branch: `feat/csv-import-ui`

- Add localized upload, preview, mapping, validation, confirmation, progress,
  and result-summary UI for the supported transaction CSV format.
- Hide/upgrade-gate the entry point for Solo while retaining server authority.
- Add LTR/RTL and E2E coverage for successful, invalid, duplicate, and
  entitlement-blocked imports.

### Step 15 — Honest financial-report CSV exports

Branch: `feat/report-csv-exports`

- Define the sold feature as **Export financial reports to CSV**.
- Add Trial Balance, Cash Flow, and General Ledger CSV alongside existing P&L
  and Balance Sheet.
- Enforce the `exports` entitlement on the server and keep report viewing on
  `core_reports` for every launch plan.
- Test all five exports, permission/tenant isolation, localization-safe data,
  and entitlement behavior. Do not imply full organization-data export.

### Step 16 — Audit-history visibility window

Branch: `feat/audit-history-window`

- Add a tenant-safe audit-history query applying 90/365/1095-day visibility
  without physically deleting append-only security records.
- Add a localized audit-history UI for authorized users and explain the window
  accurately.
- Test boundary timestamps, tenant isolation, role permission, downgrade
  visibility, and immutable underlying records.

### Step 17 — Plan-aware Paymob checkout contract

Branch: `feat/plan-aware-checkout`

- Change the request to `{ organizationId, planKey, interval }`.
- Resolve active/public/purchasable plan, exact database amount, and server-only
  Paymob plan mapping. Reject Solo/Starter/Business misconfiguration, arbitrary
  amounts, Scale, Enterprise, inactive plans, and unsupported intervals.
- Bind plan identity to signed/verifiable provider metadata and update webhooks
  to assign the resolved plan while preserving provider subscription IDs.
- Add Edge Function/unit/pgTAP tests and a six-price production setup checklist.
- Do not enable existing-customer migration until Section 5 decisions are
  approved.

### Step 18 — Launch pricing, plan selection, and Coming Soon UI

Branch: `feat/launch-pricing-ui`

- Replace single-plan pricing on public, subscribe, and billing surfaces with
  localized Solo/Starter/Business cards and monthly/yearly switching.
- Display annual prices from the 32%-discount formula: EGP 3,255.84 for Solo,
  EGP 4,887.84 for Starter, and EGP 8,967.84 for Business.
- Mark Starter Most Popular; represent included/not included accurately.
- Add Scale as disabled Coming Soon and Enterprise as separate Contact us /
  Coming Soon with no checkout path.
- Present Multi-branch accounting, Advanced Analytics & Reporting, and
  Developer API as future functionality, not paid inclusions.
- Show core reports for all, imports for Starter/Business, Business-only
  multi-currency and priority support, and exact prices.
- Add responsive, accessibility, RTL, and checkout-selection E2E coverage.

### Step 19 — Usage meters and localized quota errors

Branch: `feat/usage-quota-ux`

- Add billing/workspace usage meters for all seven quotas with 80%, 95%, and
  reached states.
- Centralize stable database error parsing and English/Arabic messages.
- Show current usage, plan, next-plan allowance, and focused upgrade action at
  each creation surface.
- Use locale-aware EGP, number, date, and byte formatting and verify RTL.

### Step 20 — Upgrade/downgrade preflight and safe transitions

Branch: `feat/plan-change-safety`

- Add a plan-change impact RPC comparing current usage/features with the target
  plan, without mutating data.
- Show member/account/role/storage/etc. consequences and which future actions
  will be blocked.
- Implement provider plan changes only to the extent Paymob's verified
  production contract supports them; otherwise provide an operational/admin
  handoff rather than fabricate instant changes.
- Test no-deletion guarantees, over-limit reads, feature downgrade behavior,
  rollback, and provider-event idempotency.

### Step 21 — Approved legacy subscription migration

Branch: `feat/legacy-plan-transition`

- Implement only the approved mappings from Section 5, backed by a preflight
  report and explicit per-organization policy.
- Preserve Paymob/legacy provider subscription IDs, interval, period dates,
  billing events, and payment history.
- Leave unresolved customers on private `ledger_suit`.
- Add migration dry-run queries, post-migration verification, rollback SQL, and
  tests for paid, trial, lapsed, over-limit, and foreign-currency organizations.

### Step 22 — Launch security, concurrency, and regression hardening

Branch: `test/launch-plan-hardening`

- Add cross-resource concurrent-session tests proving no quota race.
- Exercise direct REST/RPC/Edge Function bypass attempts, stale clients,
  scheduler paths, import paths, and plan-change races.
- Expand end-to-end coverage across Solo, Starter, Business, Scale/Enterprise
  rejection, expiry read-only behavior, and upgrade/downgrade warnings.
- Run the full CI matrix and regenerate/compare database types.

### Step 23 — Launch readiness verification and deployment checklist

Branch: `docs/launch-deployment-checklist`

- Produce the final entitlement/catalog verification query set, Paymob six-plan
  setup and callback checklist, Supabase secrets/Vault/migration steps, deployed
  Edge Function list, environment variables, backup/rollback procedure, and
  production smoke tests.
- Verify pricing copy against actual provider configuration and backend
  entitlements.
- Record outstanding Coming Soon work without presenting it as launch scope.
- Run full lint, typecheck, build, clean database replay, pgTAP, database lint,
  and E2E, and attach results to the PR.

## 7. Final launch verification criteria

Launch approval requires evidence that:

- only Solo, Starter, and Business reach checkout;
- all six EGP prices match both catalog and Paymob configuration, with annual
  prices derived from monthly price × 12 × 0.68;
- Scale and Enterprise cannot be purchased through UI, RPC, direct Edge
  Function calls, or altered request bodies;
- every resource quota is server-authoritative and concurrency-safe;
- Business-only multi-currency and Starter/Business imports cover every write
  path;
- core reports remain available to all three plans and the export claim matches
  the five delivered CSV reports;
- quota and subscription-expiry states preserve readable accounting history;
- downgrade and legacy migration delete nothing;
- public copy, billing state, entitlements, provider metadata, generated types,
  documentation, and tests agree; and
- the production checklist has named owners for every manual Paymob, Supabase,
  deployment, rollback, and smoke-test action.
