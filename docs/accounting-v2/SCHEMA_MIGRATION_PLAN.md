# Schema and migration plan

Planning only; WP00 adds no migrations. Dependency: signed WP01 domain decisions, then WP02. Owner: implementation engineer; accountable release/data owner: Tareq; human accounting reviewer: to be named.

## Preflight and historical hazards

Inventory all 66 committed migrations and actual target applied versions/checksums separately. The 20260908120000 user-managed-chart migration contains TRUNCATE ... CASCADE of accounts, transactions, categories, commitments and recurring rules. Do not apply a missing historical destructive migration to a populated target. Do not edit that historical file or mark it applied to bypass work. Escalate a reviewed preservation/baseline transition plan, backed by isolated rehearsal and explicit owner approval. No assumption that remote data is disposable.

Before any V2 backfill, collect aggregate counts and hashes under authorized access: journals/entries by tenant/status/currency; debit/credit sums by account/date; parent cycles/depth; parents with own postings; orphan/cross-tenant references; null/duplicate codes; changed subtypes/CF mappings; system-key availability (especially OBE); current subscriptions/quotas and generated types. Report only redacted aggregates. Freeze reviewed mapping input with accountant signature and backup reference.

## Proposed additive sequence

| Stage | Change proposed | Compatibility and reconciliation |
|---|---|---|
| M1 | Add account node/classification/contra metadata and reporting mapping/version structure | Preserve existing RPC signatures and legacy generated normal_balance during transition; no destructive cast/replacement before consumers audited |
| M2 | Backfill only reviewed classifications | Used parent remains explicitly unresolved if Group would discard own entries; record exceptions; compare exact per-account ledger hashes and historical reports |
| M3 | Add controlled account APIs and shared posting guards | Cover direct REST, manual, adjustment, opening, reversal, import, scheduler and privileged paths; audit grants/search_path; old clients cannot bypass Group/control policy |
| M4 | Add V2 report RPCs alongside V1 | Prove trial balance identity, contra signs and historical mapping; avoid replacing V1 return contracts until app consumers migrate |
| M5 | Opening batch/cutover state and numbered journal metadata | Unique tenant keys; atomic confirmation, cutoff/close locks, retry guarantees; accounting data still only in entries |
| M6 | Subledger/period/reconciliation/assets per approved scope | Same-tenant composite FKs and RLS, exact control reconciliation, immutable settlement/depreciation links, deterministic lock order |
| M7 | Switch reviewed app consumers; later retire obsolete contracts | Only after old/new app compatibility and accountant UAT; no retirement in same release as first additive schema |

Future migration names must be generated when work is authorized; these M IDs are planning stages, not fabricated migration files. No new balance source. No silent historical classification restatement. Legacy code/type changes need explicit compatibility adapters and generated-type regeneration at their implementing WP.

## Rehearsal and cutover

Use a newly created local disposable project for clean replay, never an existing developer DB; use an authorized isolated restored copy for populated-data rehearsal. Test interrupted backfill, partial failure, lock contention, large charts and rollback-compatible old app. Compare before/after journal/line identities and amounts, GL opening/movement/closing, six-column TB, P&L/position/CF, subledger controls and audit continuity. Zero unexplained deltas is required, not just equal grand totals. Validate storage objects separately from SQL backup.

Freeze cutover date/mode, mapping revision, app/function SHAs and migration set. Stop writes for the approved window if needed; preserve pending payment callbacks and import jobs. Apply through the repository deployment workflow only after target identity and applied history are proven. Record actual applied versions and smoke/reconciliation evidence. Read-only history must remain available during quota/expiry transitions. See [ROLLBACK_PLAN](ROLLBACK_PLAN.md).
