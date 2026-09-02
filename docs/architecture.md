# Architecture

How Ledger Suit stays correct: what enforces tenancy, what enforces accounting,
and where the boundaries sit.

---

## 1. The tenant boundary

```
auth.users → profiles → organization_members → organizations → financial data
```

`organizations.id` is the tenant key. Every tenant-owned table carries
`organization_id`, and it is immutable — a trigger rejects any attempt to move a
row between organizations.

**Membership is the only thing that grants access.** Knowing an organization's
UUID grants nothing. Every policy and every RPC resolves the caller from
`auth.uid()` and looks up an *active* membership.

### Cross-tenant references are impossible by construction

Every tenant table declares `unique (id, organization_id)`, and every reference
between them is a **composite** foreign key:

```sql
constraint transaction_entries_account_same_org
  foreign key (account_id, organization_id)
  references public.accounts (id, organization_id)
```

A transaction in Organization A physically cannot reference an account in
Organization B — the database refuses the row. This applies to categories,
counterparties, tags, attachments, the reversal chain and the ledger.

Attachment storage keys are constrained the same way:

```sql
constraint attachments_key_is_tenant_scoped check (
  storage_key like organization_id::text || '/%'
)
```

so a leaked object key from another tenant cannot be recorded, and the Storage
policies check membership of that first path segment.

---

## 2. Authorization: capabilities, not role checks

There are five roles (`owner`, `admin`, `accountant`, `data_entry`, `viewer`),
but nothing in the schema branches on a role name. Roles map to capabilities in
`public.role_capabilities`, and members can be granted or denied individual
capabilities on top of their role:

```
effective = role defaults + granted_capabilities − revoked_capabilities
```

Revocation always wins. Everything funnels through one predicate:

```sql
app.has_capability(organization_id, 'transactions.post')
```

used identically by RLS policies and by the posting RPCs. Adding a permission
means adding a row, not editing policies scattered across the schema.

`public.my_capabilities(org)` returns the caller's effective set so the UI can
hide what the user cannot do — while the database independently enforces it.

### Helper functions

All helpers live in the private `app` schema, which is **not** in PostgREST's
exposed-schema list, so no client can call them directly. They are
`SECURITY DEFINER` with `search_path = ''` and fully qualified identifiers.

One subtlety worth knowing: `app.is_service_context()` deliberately does **not**
test `current_user`. Inside a `SECURITY DEFINER` function `current_user` is the
function owner (`postgres`), so a `current_user` check would silently authorize
every capability test in the system. It tests the JWT role claim instead.

---

## 3. Money

Money is stored as **integer minor units** (`bigint`) plus an ISO currency code.
Never a float, never a rounded double.

```
amount_minor      bigint   -- 1500000
currency_code     char(3)  -- 'EGP'  → 15,000.00
```

The exponent is per currency (`public.currencies.minor_unit`): USD 2, JPY 0,
KWD 3. `app.convert_minor()` does conversions in `numeric`, never in binary
floating point. The frontend divides only at render time
(`app/utils/money.ts`).

Every ledger line stores both the transaction-currency amount and its
base-currency equivalent, so a mixed-currency book still aggregates correctly.

---

## 4. The ledger

`public.transaction_entries` is the single source of truth for every balance and
every report. There is **no stored balance column anywhere** — not on accounts,
not on organizations — so nothing can drift out of agreement with the ledger.

```
transactions          the business event ("paid February rent")
transaction_entries   its double-entry lines
```

A line has a `side` enum (`debit` | `credit`) and a strictly positive amount, so
a single line can never carry both a debit and a credit.

### Balance enforcement

A **deferred constraint trigger** checks, at commit time, that every posted
transaction:

- has at least two lines
- balances in the transaction currency (when all lines share one currency)
- balances in the base currency (always)

Deferred, so a multi-statement posting can build its lines one at a time and
still be rejected as a whole. It fires on every path into the database — RPC,
service role, or `psql`.

Cross-currency journals are converted line by line, which can leave a residual
of a few minor units. `app.normalize_journal_lines()` absorbs a residual no
larger than the line count into the largest line on the short side, and refuses
anything bigger as a genuine imbalance. It never writes the difference off to a
plug account.

### Immutability

Once a transaction is posted:

- its financial columns cannot be updated (`app.guard_transaction`)
- its ledger lines cannot be updated or deleted (`app.guard_transaction_entry`)
- **no new lines can be attached** (`app.fill_entry_from_transaction`)
- it cannot be deleted; only drafts can

There is no escape hatch — no GUC, no role check. The posting path stamps
`posted_at` on the lines *while the parent is still a draft* and flips the
transaction to `posted` last, precisely so this can stay absolute. The test
suite proves these hold against a superuser.

Corrections use the reversal chain:

```
original → reversal (mirrored lines) → corrected transaction
```

linked by `reverses_transaction_id`, `reversed_by_transaction_id` and
`correction_of_transaction_id`.

---

## 5. The posting engine

Clients hold `SELECT` on `transactions` and `transaction_entries` and nothing
else. Every write goes through a `SECURITY DEFINER` RPC.

Each one, in order:

1. resolves the caller from `auth.uid()`
2. `app.require_capability(org, …)`
3. `app.assert_books_open(org, date)`
4. validates that every referenced account belongs to the organization and is
   not archived
5. normalizes the journal lines and proves they balance
6. writes the transaction and its lines in one database transaction
7. appends an audit record

If any line fails, the whole posting rolls back. A partial journal cannot exist.

### Product-facing flows

The user never picks a debit or a credit. These functions derive the journal:

| RPC | Journal |
|---|---|
| `record_income` | Dr destination asset / Cr revenue |
| `record_expense` | Dr expense / Cr source asset or credit card |
| `record_transfer` | Dr destination / Cr source (+ fee lines) |
| `record_asset_purchase` | Dr asset / Cr payment account |
| `record_liability_created` | Dr asset / Cr liability |
| `record_liability_payment` | Dr liability + Dr interest + Dr fees / Cr asset |
| `record_owner_contribution` | Dr asset / Cr equity |
| `record_owner_withdrawal` | Dr owner drawings / Cr asset |
| `create_adjustment` | free-form lines, requires `transactions.adjust` |
| `post_opening_balance` | balanced journal against Opening Balance Equity |
| `reverse_transaction` | mirrored lines, links both records |

Categories are the friendly layer: "Rent" carries `default_account_id` pointing
at the Rent Expense account. Categories are not ledger accounts.

### Concurrency and idempotency

`post_transaction` takes a row lock and then re-checks status, so two clients
racing to post the same draft serialise and the loser gets
`INVALID_TRANSACTION_STATE`. Every flow accepts an `idempotency_key`, unique per
organization; a replay returns the original id instead of a duplicate posting.

---

## 6. Reporting

Reports read posted entries only — drafts, scheduled transactions and
commitments never reach an official report.

| Object | Purpose |
|---|---|
| `account_balances` (view) | Live balance per account, derived |
| `ledger_entries` (view) | Posted lines joined to transaction and account |
| `report_trial_balance` | Debits and credits per account |
| `report_profit_and_loss` | Revenue / cost of sales / operating expenses |
| `report_balance_sheet` | Assets, liabilities, equity + unclosed profit |
| `report_cash_flow` | Operating / investing / financing |
| `report_general_ledger` | One account, opening and running balance |
| `dashboard_summary` | Every dashboard KPI in one round trip |
| `check_balance_sheet_integrity` | Diagnostic: is `A = L + E`? |

Both views are declared `security_invoker = true`, so RLS still applies — a view
is not a way around the tenant boundary. All aggregation happens in SQL; the
browser never computes an authoritative figure.

---

## 7. Audit log

`public.audit_logs` is append-only: `INSERT`/`UPDATE`/`DELETE` are revoked from
client roles and a trigger rejects mutation outright. The only writer is
`app.write_audit()`, which resolves the actor from `auth.uid()` — never from an
argument — and snapshots the actor's email so the entry stays readable after the
profile is gone.

---

## 8. Subscription access

There is one public product: Ledger Suit, billed monthly or yearly through
Stripe. Creating an organization inserts a `suspended` subscription and does
**not** start access. Only a signature-verified Stripe event can attach the
provider subscription and begin the 14-day trial.

The central capability predicate applies subscription state after role and
member overrides. Read capabilities and `billing.manage` remain available;
every other mutation requires `trialing`, `active`, or a time-bounded payment
grace period. A lapsed organization therefore keeps its financial history but
cannot post, edit, invite, import, export, or run scheduled accounting writes.
This is a database rule, not a frontend redirect.

Entitlements are evaluated in exactly two places:

```sql
public.can_use_feature(organization_id, feature_key)
public.get_limit(organization_id, limit_key)   -- NULL = unlimited, 0 = denied
```

`billing_events` is unique on `(provider, provider_event_id)`, which is what
makes webhook processing idempotent no matter how often a provider retries.
The webhook verifies Stripe's HMAC over the untouched request body before it
calls the service-only database transition function.

Supabase Cron runs recurring transactions, commitment reminders, and automatic
commitment conversions every 15 minutes. It skips organizations without write
access. A second five-minute Cron invokes the Resend queue worker with URL and
credentials read from Supabase Vault; queue rows are claimed with
`FOR UPDATE SKIP LOCKED` and use notification IDs as Resend idempotency keys.

---

## 9. Acquisition and onboarding

`/` is public product information, `/signup` is the guided account journey, and
`/dashboard` is the authenticated application entry. Signup gathers the owner
profile, legal business details, country, currency, timezone, fiscal-year start,
and billing interval before creating anything.

`complete_account_onboarding(...)` then provisions the profile, organization,
owner membership, default categories, starter chart of accounts, audit entry,
and checkout-required subscription in one PostgreSQL transaction. If any seed
or validation fails, none of the workspace survives. The function resolves the
caller through `auth.uid()`, refuses replay for an existing active member, fixes
its `search_path`, and grants execution only to authenticated users.

Stripe Checkout is the final signup step. Until its signed webhook activates
the trial, the database removes write capabilities. A partially paid or
client-forged workspace therefore cannot enter normal use.

The authenticated shell exposes one global floating add control. Its drawer is
derived from the caller's capabilities and delegates to the existing controlled
transaction, account, commitment, recurring, counterparty, tag, and invitation
workflows; it is navigation, never a second write path.

---

## 10. Operational workflows

Commitments remain outside the ledger until settlement. Full and partial
settlements call the same income/expense posting functions as manual entries;
postponement and cancellation preserve audit history. Automatic conversion is
a controlled batch RPC that independently authorizes and validates each due
record.

Recurring rules store a validated posting template and materialize unique
occurrences. A unique `(rule_id, occurrence_date)` constraint and deterministic
posting key prevent duplicate journals. Failed occurrences record their error
and attempt count and can be retried without advancing or destroying the rule.

Counterparties and tags are lightweight tenant-scoped dimensions. Attachments
use a private bucket, tenant-prefixed object keys and signed URLs. Notifications
can only have their read state changed by the intended recipient through a
controlled function; clients cannot rewrite notification content or routing.

Organization invitations return a one-time token, store only its SHA-256 hash,
verify the signed-in user's email on acceptance, and create membership in the
same database transaction.

A suspended or cancelled subscription switches features off but never destroys
financial history.

---

## 11. Error codes

Domain errors are raised with a stable prefix so the API layer can map them to
safe user-facing messages:

```
TENANT_ACCESS_DENIED        INSUFFICIENT_PERMISSION
UNBALANCED_JOURNAL          INVALID_TRANSACTION_STATE
BOOKS_LOCKED                ACCOUNT_ARCHIVED
POSTED_RECORD_PROTECTED     SYSTEM_ACCOUNT_PROTECTED
INVALID_CURRENCY            INVALID_EXCHANGE_RATE
INVALID_AMOUNT              INVALID_ACCOUNT
MISSING_SYSTEM_ACCOUNT      LAST_OWNER_REQUIRED
ACCOUNT_HAS_LEDGER_HISTORY  TENANT_KEY_IMMUTABLE
```

`TENANT_ACCESS_DENIED` is returned identically for "no such record" and "record
belongs to another tenant", so responses cannot be used to probe for foreign
ids.

---

## 12. Deliberately built for what comes next

- `transaction_entries.dimensions jsonb` — branch, project, cost centre
- `transaction_status.pending_approval` — approval policies without reshaping
  the engine
- `organization_settings.books_locked_until` — period closing
- `attachments.entity_type` — reconciliation artefacts later
- `subscription_entitlements` — new plans are rows, not code

None of these are exposed in Phase 1; they exist so adding them later is not a
migration of live financial data.
