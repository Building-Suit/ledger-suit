# Current status

Evidence refreshed 2026-09-18. Read this first, then MASTER_LAUNCH_PLAN, DECISIONS, OPEN_RISKS and accounting MASTER_PLAN/ACCOUNTING_DOMAIN_SPEC/TRACEABILITY_MATRIX.

## Current stage and work package

Current major phase: **PH-01 — Evidence and accounting design**, IN PROGRESS.
Only active execution WP: **UI-02A — Accounts table**, READY FOR REVIEW (DEC-010). WP00 [PR #94](https://github.com/Building-Suit/ledger-suit/pull/94) merged on 2026-09-18 at `6fb152e`; separate independent review/signature is not recorded here. UI-02 is partial, and WP01 accounting sign-offs remain pending.

## What is working and what is being implemented

Code contains shared double-entry posting, immutable ledger guards, account hierarchy primitives, GL/TB/P&L/position/cash-flow reports, tenant permissions, imports/exports, quotas and private 14-day Business-level trial. Fresh local DB/Edge/application checks are recorded below. Deployed behavior and accountant approval remain NOT VERIFIED.

UI-02A implements Accounts presentation only: PrimeVue DataTable, name/code search/sort, complete existing-query paging, localized loading/error/empty states, preserved filters with explicit reveal after save, and tenant-switch guards. Existing balances, group aggregate semantics and RPC contracts remain unchanged. No migrations, seeds, generated types, provider/deployment or production data changes.

## Blockers and risks

Named accountant and signed domain/scope decisions; verified staging/production identity, applied migrations, backup/restore and provider configuration are outstanding. Critical hazards: historical TRUNCATE migration and unverified recoverability (RISK-001/009). Browser baseline has unresolved invitation loading instability (RISK-014). High accounting gaps: group/control/contra, historical mapping, six-column/classified reports, full AR/AP/period workflows and correction quota/FX policy. Account freshness report remains an investigation: both cache refreshes already exist. See OPEN_RISKS for owners/evidence confidence.

## Next work package

Finish and independently review UI-02A first; no automatic merge or next slice. **WP01 remains the next accounting package**: accountant/founder design and advertised-scope sign-off. DEC-010 authorizes only this presentation exception. UI-02 Transactions/records remain outstanding before UI-03; UI-18 stays last. No accounting/schema implementation before signed WP01 decisions.

## UI-02A verification — 2026-09-18

- Branch `codex/ui02a-accounts-table`, isolated `/home/tareq/Dev/ledger-suit-ui02a`, based on merged PR #94 / dev `6fb152e`. Published as [PR #96](https://github.com/Building-Suit/ledger-suit/pull/96) targeting `dev`; implementation/evidence commit `d05a63948873a1adad2b4c98c4a7a8f61a904f95`. Independent UI-02A review pending.
- Frozen install, lint, typecheck, build PASS; focused Accounts + existing finance tests **18/18 PASS**; extended large-chart shared-selector check **1/1 PASS**. Unmodified baseline account creation **1/1 PASS**; the reported generic stale-account defect was not reproduced.
- Browser-verified EN/AR, both themes, desktop/mobile, keyboard sorting, complete 1,003-account search/selector coverage, explicit saved-record reveal and delayed tenant response suppression. [Before/after and interaction captures](../evidence/ui02a/README.md).
- Full local Chromium E2E: **56/56 PASS**, including the earlier invitation scenario; exact-head PR CI pending. Existing RISK-014 remains open regardless of a subsequent green run; its earlier invitation timeout cause is not established.
- Only new disposable local project used (API58321/DB58322); existing developer DBs and remote environments untouched. No migration/seed/type/dependency changes. Financial aggregation unchanged, including open RISK-003.

## Historical WP00 verification

- Audited origin/dev: `8de315838b0d6a23e0bf523813a29c9d9e8bd13d`; latest feature PR #91 (already represented in dev history). main `1548161`; stg `812d81f`. Open PRs: none when checked.
- WP00 historical work branch: `codex/wp00-planning-bootstrap`; isolated `/home/tareq/Dev/ledger-suit-wp00`. WP00 implementation commit: `01660c4`. Published with founder authorization on 2026-09-18 as [PR #94](https://github.com/Building-Suit/ledger-suit/pull/94) targeting `dev`; independent review pending. PR publication does not mark WP00 COMPLETED.
- Fresh 2026-09-18 local Linux: lint/typecheck/build PASS; Deno 9/9 PASS; isolated local replay of 66 migrations PASS; pgTAP 678 assertions/27 files PASS; DB lint PASS; generated types no drift. Node 26.8.1/pnpm 10.33.0 differs from CI Node22/pnpm11.5.0.
- Chromium full run FAILED (45 pass/1 invitation loading timeout); unchanged focused recheck PASS 1/1. RISK-014 remains open; no all-green full-run claim. Golden V2/UAT NOT RUN. Runtime/build warnings and test limitations recorded there.
- Historical exact-SHA CI: [34850913614](https://github.com/Building-Suit/ledger-suit/actions/runs/34850913614) and [34850879669](https://github.com/Building-Suit/ledger-suit/actions/runs/34850879669), 2026-09-14; application and database/e2e jobs succeeded. Not a production check.
- Migrations modified: none. Remote migrations/app/functions/provider/restore: NOT VERIFIED. No live financial rows accessed.

## Launch control board

G1 Accounting, G2 Technical/recovery, G3 Security, G4 UX, G5 Commercial, G6 Legal, G7 Support and G8 Beta: **all NOT VERIFIED**. Public launch/ads not approved. Missing evidence is not a demonstrated gate failure; fresh baseline failures, if any, are separately recorded. Marketing claims and scope must remain bounded by accepted evidence.
