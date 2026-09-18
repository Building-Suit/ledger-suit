# Accounting domain specification

Version 0.1 — proposal for accountant review, not approved accounting policy. Founder invariants are mandatory; design choices below require WP01 sign-off. [Decisions](../launch/DECISIONS.md) distinguish those categories.

## Shared ledger and money — ACCT-03

Transactions represent business events; transaction_entries are the sole authoritative balances. Wizards, manual journals, imports, recurring events, settlements, openings and reversals converge on the existing posting engine. Posted/reversed entries remain immutable; correct by linked reversal plus correcting journal. Drafts and commitments are excluded from official reports. Every posted journal has at least two positive minor-unit lines, exact base-currency debit = credit and exact transaction-currency equality when single currency. Retain bigint/numeric SQL conversion; define supported UI integer range explicitly. FX residual allocation currently changes the largest short-side line within the line-count tolerance: preserve history, obtain accountant approval before changing future allocation. A balanced journal does not by itself prove correct classification.

## Account master — ACCT-01/02

Keep five types: asset, liability, equity, revenue, expense. Current/non-current is statement classification, not a sixth type. Proposed fields: tenant-unique code (mandatory/auto-generation policy pending), Arabic name with optional English name, parent, type/subtype, financial classification, node kind, contra flag/effective normal side, currency, cash-flow mapping, description and archive state. Chart templates are optional and accountant-approved for services/trading/custom/empty. Do not clone Excel placeholders or create an account per customer by default.

- Group: no direct posting from any path; roll up descendant posted leaves once. Existing parents with direct history cannot be silently relabeled Group.
- Posting: ordinary manual/wizard entry allowed with capability, currency, lock and quota checks.
- Control: AR/AP and future subledger controls accept entries only through their matching subledger workflow. A proposed exceptional adjustment requires specific capability, mandatory counterparty/allocation, reason, linked reconciliation and audit; never permit an unexplained control total. Accountant must accept or reject this exception in DEC-003.
- Contra is independent of node kind. Accumulated depreciation is a credit-normal asset; sales returns a debit-normal revenue; drawings debit-normal equity. Presentation sign must come from financial classification, not blindly from the normal-side balance. Changing generated normal_balance alone would break current report algebra.
- Parent references must stay same-tenant, acyclic and classification-compatible. Concurrent reparenting needs serialization. Code uniqueness is case-insensitive within tenant. Archive preserves historical GL/report access while preventing new posting.

## Historical classification — ACCT-07

Current reports join current account master. Proposed effective-dated mappings or immutable reporting-version snapshots must preserve historical statement classifications; decide treatment of renamed/reparented accounts separately from monetary entries. Record before/after account totals and report versions. No automatic subtype, cash-flow section, normal-side or node-kind rewrite on used accounts. Unknown legacy mappings go to an exception queue, never guessed from name. Balance-bearing parents must retain their own posting representation or be migrated through an explicitly approved presentation mapping without moving immutable lines.

## Openings — ACCT-04

Single-account opening asks for debit/credit, amount, currency/rate and cutoff date and previews the actual journal. Bulk opening accepts validated opening TB data, preserving source row/duplicate keys and rejecting unbalanced import totals before posting. Existing post_opening_balance accepts signed normal-side amounts and can add OBE; a V2 adapter must translate explicit side correctly and show the OBE line rather than hide imbalance.

Year-start versus midyear modes need accountant policy for retained earnings, YTD revenue/expense and comparatives. Opening Balance Equity is temporary and must have an approved reconciliation/clearance before acceptance. Opening lock prevents duplicate cutover while later corrections remain auditable journals. Imports currently accept income/expense transactions, not opening TB. Single and bulk opening share the ledger; no authoritative opening_balance/current_balance column.

## Journal Center and vocabulary — ACCT-05/08/14

One center covers all sources with stable tenant/fiscal-year journal number policy (new requirement; do not mistake UUID/reference for approved numbering), accounting date, reference, description, source, status, debit/credit totals, actor and counterparty. Filters include period, account/type, transaction type, state, user, counterparty, amount, reference and tags; save views with tenant/owner visibility. Show lines without leaving context. Draft/approval semantics and number assignment/non-reuse require explicit policy; approvals remain optional only if advertised scope permits.

Account and counterparty drawers overlay the current journal/report. Preserve URL, selected period, filters, sorting, pagination, scroll and selected record; Back/Forward restores them. Tenant switch clears old records including in-flight requests. Account creation must immediately appear in the correct tree and dependent selectors; current invalidation exists, so reproduce before fixing.

| Workflow | User meaning | Journal |
|---|---|---|
| Cash expense | حساب المصروف / حساب الدفع | Dr Expense / Cr Cash or Bank |
| Cash revenue | حساب التحصيل / حساب الإيراد | Dr Cash or Bank / Cr Revenue |
| Credit sale | العميل / حساب الإيراد | Dr AR control with customer / Cr Revenue |
| Customer receipt | حساب التحصيل / العميل | Dr Cash or Bank / Cr AR control, allocate invoice |
| Supplier bill | المورد / المصروف أو الأصل | Dr Expense/Asset / Cr AP control with vendor |
| Supplier payment | المورد / حساب الدفع | Dr AP control / Cr Cash or Bank |
| Transfer | حساب التحويل منه / حساب التحويل إليه | Dr destination / Cr source, show fees separately |
| Manual journal | مدين / دائن | Explicit validated lines |

Do not mechanically swap From/To labels. Preserve workflows while exposing their accounting effect. Arabic terms: دليل الحسابات، طبيعة الحساب، قيد يومية، دفتر الأستاذ، ميزان المراجعة، قائمة المركز المالي، قيد عكسي، فترة محاسبية.

## Reporting — ACCT-06/07

Use debit-positive signed amounts internally for report algebra. For each account and period: O = sum(debit-credit before start); M = period debit-credit; C = O+M. TB shows max(O,0), max(-O,0), period debit, period credit, max(C,0), max(-C,0). Both opening and closing debit/credit totals balance; period movements balance separately. Rollups are presentation rows excluded from grand totals. Empty-period GL still shows opening and closing; deterministic line ordering. Archived accounts remain reportable.

P&L separates revenue, cost of sales/service, operating expenses, other/finance items and net profit according to approved mappings. Position separates current/non-current assets and liabilities, equity and unclosed profit; A=L+E. Contra subtracts from its corresponding section while keeping correct debit/credit display. Cash flow needs accountant-approved mixed-journal allocation and cash-to-cash exclusion; current dominant-counterpart heuristic is not proof of an accepted statement. Each figure drills to accounts → GL → journal → lines. CSV exports retain server permission/plan enforcement and spreadsheet-injection defenses. Period comparisons and optional Excel/PDF exports remain traceable scope with explicit priority.

## Subledgers, periods and modules

ACCT-09: AR/AP obligations carry counterparty, issue/due dates, original/open amounts and settlements. Allocation must not double-settle or exceed allowed amount without approved credit/advance handling. At every as-of date sum(customer balances)=AR control and sum(vendor balances)=AP control. Aging buckets use approved due-date boundaries (current, 1–30, 31–60, 61–90, >90); reversal unwinds allocation, not history. Existing commitments recognize income/expense on settlement and are not a full accrual subledger.

ACCT-10: Open/Soft Close/Hard Close and audited reopen require actor/reason/date and authorization. Existing books_locked_until plus books.override_lock is not that lifecycle. Serialize posting with lock changes; define whether privileged hard-close override is prohibited until reopen.

ACCT-11: bank statement import, match/unmatch, outstanding items, fees/adjustments through shared ledger, reconciliation statement and duplicate prevention. ACCT-12: asset register with cost/date/useful life/method/residual value, approved depreciation schedule, accumulated depreciation, impairment scope decision, sale/disposal gain/loss and journal links. Purchase wizard alone is insufficient.

ACCT-13: dimensions on lines (cost center/project/branch), allocation and rollup tests, not a substitute GL tree. Tax/VAT/withholding/eInvoice/eReceipt and inventory/COGS require target-activity and current legal/accountant decisions; no compliance claim. Trading workflows cannot launch without the inventory/accounting treatment they advertise. Multi-branch remains Coming Soon under the accepted commercial policy.

ACCT-15: corrections currently consume transaction quota and FX restrictions may block foreign-currency reversal after downgrade. Existing behavior is not changed by this proposal. Approve a safe controlled correction policy, concurrency/idempotency and abuse limits before implementation; do not invent a service-role bypass.
