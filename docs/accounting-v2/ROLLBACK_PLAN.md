# Accounting rollback and recovery plan

No rollback performed in WP00. Accountable owner: Tareq. Execution requires a reviewed target/environment-specific runbook; this document authorizes no production operation.

## Before release

Record previous app/Edge versions, schema compatibility matrix, backup/PITR reference and retention, storage-object recovery coverage, provider event position, approved RPO/RTO and rollback decision deadline. Restore into an isolated non-production target and measure recovery time. Reconcile independent journal/GL/TB/statement/subledger controls plus attachment existence and Auth ownership. A backup listing is not a restore rehearsal.

## Trigger and containment

Unbalanced journals, cross-tenant exposure, silently changed history or unexplained report differences stop accounting writes and release promotion. Tareq declares incident and assigns engineer/security/accountant owners. Preserve audit/log evidence without customer payloads. Disable affected acquisition/checkout if needed via reviewed operational mechanism; continue verified callbacks for already initiated payments. Never delete catalog/event history to stop sales.

## Recovery order

1. Determine scope and exact first bad version using redacted aggregate evidence.
2. Roll app/Edge back only to versions compatible with additive database contracts and payment snapshots. Keep working read-only history.
3. For schema behavior, prefer reviewed forward repair migration; never rewrite applied migration files.
4. For erroneous posted accounting, accountant authorizes linked reversal/correcting journals in an open period. An app rollback or reverted schema cannot repair immutable financial history.
5. Restore only for confirmed corruption with explicit data owner approval and known recovery point. Reconcile post-backup writes, queued imports, provider callbacks and emails before reopening; no duplicate financial/provider events.
6. Verify balance by journal and tenant, GL/TB/position, counterparty controls, RLS/storage, retries, period locks, expiry reads and current payment state. Accountant and release owner sign the reopen decision.

Stop if backup coverage, target identity, recovery point or old-app compatibility is unproven. For the destructive historical chart migration, use the preflight blocker in [SCHEMA_MIGRATION_PLAN](SCHEMA_MIGRATION_PLAN.md); do not replay it against valuable data. Retain incident record, affected requirements, root cause and regression evidence in OPEN_RISKS and POST_LAUNCH_PLAN.
