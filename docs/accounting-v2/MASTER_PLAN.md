# Accounting V2 master plan

Canonical accounting implementation plan. WP00 evidence date: 2026-09-18. Current work is documentation only, READY FOR REVIEW; independent review is pending. Overall phase and commercial dependencies belong to [Launch](../launch/MASTER_LAUNCH_PLAN.md).

## Operating contract

At every startup read the launch master, CURRENT_STATUS, DECISIONS, OPEN_RISKS, this plan, domain spec and traceability matrix; inspect current Git/code before selecting work. Preserve unrelated work; fresh isolated branch from latest origin/dev; one reviewed WP at a time. Do not merge, deploy, or continue automatically. Run relevant tests and update all affected planning documents in the same WP. Source code, test execution, deployment and accountant acceptance are separate evidence dimensions.

Founder invariants DEC-001 apply throughout. Existing UI program UI-01–UI-18 remains ordered, with admin/pricing/offers exclusively UI-18. Accounting dependencies are reconciled in [ROADMAP](../launch/ROADMAP.md), not used to silently cancel UI tasks.

## Work packages

| WP | Objective / requirements | Priority / status | Dependencies | Deliverable and acceptance | Verification / human review |
|---|---|---|---|---|---|
| WP00 | Permanent evidence and plans, all requirements | P0 / READY FOR REVIEW | Audited dev | 18 canonical files, provenance, risks, one next WP; docs only | Document links/diff + baseline; independent ChatGPT review pending |
| WP01 | Lock accounting specification and launch scope, ACCT-01–ACCT-15 | P0 / NOT STARTED | Independent WP00 acceptance | Signed decisions, mapping policy, golden fixtures, explicit scope for bank/assets/dimensions/tax/inventory | Accountant + founder; review arithmetic and historical preservation |
| WP02 | Account master contracts and preservation, ACCT-01,02,03 | P0 / NOT STARTED | WP01 signed accounting decisions | Additive node/contra/classification contract, reviewed backfill, all posting boundaries deny groups | DB direct/RPC/tenant/race tests, reconciliation; accountant + independent code review |
| WP03 | Account tree and optional templates, ACCT-01,02,08 | P0 / NOT STARTED | WP02; applicable ordered UI prerequisites | Parent/normal-side/classification exposure, archive rules, tree rollups, optional service/trading/empty templates | EN/AR create/edit/selector/tenant/navigation; accountant usability |
| WP04 | Opening and cutover, ACCT-04 | P0 / NOT STARTED | WP03 | Single and bulk preview/validation/import, opening journal, cutover lock, correction links | Golden 13/14, malformed/retry/quota/FX/midyear; accountant sign-off |
| WP05 | Journal Center and contextual navigation, ACCT-05,08,14 | P0 / NOT STARTED | WP04; UI table/form prerequisites | Number/source/lines/filters/saved views; account/counterparty drawers; URL/history/scroll; precise labels | All golden posting paths, browser back/forward, permissions; accountant review |
| WP06 | Reports V2, ACCT-06,07 | P0 / NOT STARTED | WP05 | Six-column TB, GL opening/closing, classified P&L/position, cash flow, trace/export, comparisons | Independent fixtures + aggregation/archival/contra tests; accountant reconciliation |
| WP07 | AR/AP control and subledgers, ACCT-09 | P0 / NOT STARTED | WP06; signed control policy | Obligations, due dates, allocations, statements, aging reconcile to controls | Golden 4–7, partial/excess/reversed settlement, tenant tests; accountant |
| WP08 | Period lifecycle and correction safety, ACCT-10,15 | P0 / NOT STARTED | WP07; DEC-005/006 | Open/soft/hard close, audited reopen, correction/quota/FX policy | Golden 14/15, concurrency with lock/close; accountant + security |
| WP09 | Bank reconciliation and fixed assets, ACCT-11,12 | P1 / NOT STARTED | WP08; explicit WP01 scope decision | Bank statement matching/outstanding items; asset register/acquisition/depreciation/disposal | Statement reconciliation, no double posting, depreciation/disposal fixtures; accountant |
| WP10 | Conditional dimensions/tax/inventory, ACCT-13 | P1 / NOT STARTED | WP01 scope decision; WP08, affected modules | Approved activity-dependent scope or explicit dated deferral with marketing exclusions | Dimension totals, inventory/COGS or applicable tax tests; current official research and qualified human review |
| WP11 | Accounting release evidence, all ACCT | P0 / NOT STARTED | WP02–WP10 required scope | Fresh full suite, migration rehearsal, signed UAT, no unresolved blocking accounting risk | Independent reviewer and accountant; feeds G1/G2/G3/G4 |

Dependencies describe sequencing, not authorization to start all packages. If WP01 changes module timing, record a superseding decision before editing this table.

## WP00 acceptance checklist

- [x] Separate audited code from runtime and human evidence.
- [x] Canonical paths, risk/decision/requirement IDs and prior-plan reconciliation recorded.
- [x] Accounting invariants, migration/rollback design and 15 golden fixtures documented.
- [ ] Independent review accepts WP00; only then mark COMPLETED.

## Exact next work package: WP01

Objective: obtain an accountant-reviewed Accounting Specification v1.0 before schema design is implemented. Relevant files: ACCOUNTING_DOMAIN_SPEC.md, ACCOUNTANT_UAT.md, TEST_PLAN.md, SCHEMA_MIGRATION_PLAN.md, TRACEABILITY_MATRIX.md and launch DECISIONS.md/ROADMAP.md/CURRENT_STATUS.md. Use CURRENT_STATE_AUDIT.md evidence; retain the review DOCX as a proposal.

Tasks: resolve DEC-003–DEC-007; sign group/control/contra and historical classification policy; approve opening year-start versus midyear treatment and OBE clearing; choose correction entitlement policy; freeze bank/assets/dimensions/tax/inventory scope and Arabic labels; reproduce RISK-004 with the actual failing path if possible; assign named accountant and reviewers. Do not implement schema/UI during this decision package.

Acceptance: each decision has approver/date/evidence or remains explicitly unresolved; no schema package proceeds with unresolved accounting policy. Recalculate all 15 fixture expectations independently, review direct posting and migration preflight cases, validate links and dependency consistency. No claim that an accountant approved until a human actually signs. First implementation package after WP01 is WP02.
