# Current status

Evidence refreshed 2026-09-18. Read this first, then MASTER_LAUNCH_PLAN, DECISIONS, OPEN_RISKS and accounting MASTER_PLAN/ACCOUNTING_DOMAIN_SPEC/TRACEABILITY_MATRIX.

## Current stage and work package

Current major phase: **PH-01 — Evidence and accounting design**, IN PROGRESS.
Only active WP: **WP00 — Audit and permanent planning bootstrap**, READY FOR REVIEW pending independent ChatGPT review. Last completed canonical WP: none accepted yet. Historical merged features are not Accounting V2 acceptance.

## What is working and what is being implemented

Code contains shared double-entry posting, immutable ledger guards, account hierarchy primitives, GL/TB/P&L/position/cash-flow reports, tenant permissions, imports/exports, quotas and private 14-day Business-level trial. Fresh local DB/Edge/application checks are recorded below. Deployed behavior and accountant approval remain NOT VERIFIED.

This WP implements documentation only: 18 canonical planning files and reconciliation of former plans. No product feature, migration, seed, dependency, provider, deployment or production data change. Original worktree remains untouched.

## Blockers and risks

Independent WP00 review; named accountant and signed domain/scope decisions; verified staging/production identity, applied migrations, backup/restore and provider configuration are outstanding. Critical hazards: historical TRUNCATE migration and unverified recoverability (RISK-001/009). Browser baseline has unresolved invitation loading instability (RISK-014). High accounting gaps: group/control/contra, historical mapping, six-column/classified reports, full AR/AP/period workflows and correction quota/FX policy. Account freshness report remains an investigation: both cache refreshes already exist. See OPEN_RISKS for owners/evidence confidence.

## Next work package

**WP01 only**: accountant/founder design and advertised-scope sign-off after independent WP00 acceptance. Freeze classification/contra/control/history, opening/midyear, periods/numbering, correction policy and bank/assets/dimensions/tax/inventory scope. Acceptance and exact files/tests are in accounting MASTER_PLAN. No next package started. First subsequent implementation is WP02.

## Latest verification

- Audited origin/dev: `8de315838b0d6a23e0bf523813a29c9d9e8bd13d`; latest feature PR #91 (already represented in dev history). main `1548161`; stg `812d81f`. Open PRs: none when checked.
- Work branch: `codex/wp00-planning-bootstrap`; isolated `/home/tareq/Dev/ledger-suit-wp00`. WP00 implementation commit: `01660c4`. Published with founder authorization on 2026-09-18 as [PR #94](https://github.com/Building-Suit/ledger-suit/pull/94) targeting `dev`; independent review pending. PR publication does not mark WP00 COMPLETED.
- Fresh 2026-09-18 local Linux: lint/typecheck/build PASS; Deno 9/9 PASS; isolated local replay of 66 migrations PASS; pgTAP 678 assertions/27 files PASS; DB lint PASS; generated types no drift. Node 26.8.1/pnpm 10.33.0 differs from CI Node22/pnpm11.5.0.
- Chromium full run FAILED (45 pass/1 invitation loading timeout); unchanged focused recheck PASS 1/1. RISK-014 remains open; no all-green full-run claim. Golden V2/UAT NOT RUN. Runtime/build warnings and test limitations recorded there.
- Historical exact-SHA CI: [34850913614](https://github.com/Building-Suit/ledger-suit/actions/runs/34850913614) and [34850879669](https://github.com/Building-Suit/ledger-suit/actions/runs/34850879669), 2026-09-14; application and database/e2e jobs succeeded. Not a production check.
- Migrations modified: none. Remote migrations/app/functions/provider/restore: NOT VERIFIED. No live financial rows accessed.

## Launch control board

G1 Accounting, G2 Technical/recovery, G3 Security, G4 UX, G5 Commercial, G6 Legal, G7 Support and G8 Beta: **all NOT VERIFIED**. Public launch/ads not approved. Missing evidence is not a demonstrated gate failure; fresh baseline failures, if any, are separately recorded. Marketing claims and scope must remain bounded by accepted evidence.
