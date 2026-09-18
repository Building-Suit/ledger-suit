# Decisions register

Evidence date 2026-09-18. No new accountant approval recorded. Status here classifies authority, not WP completion. Superseded narratives remain in historical source files; no accepted policy is silently reversed.

## DEC-001 — Founder accounting and execution invariants

Date: 2026-09-18. Status: FOUNDER-MANDATED.
Context: WP00 bootstrap and Appendix A. Decision: one shared ledger; balanced/immutable posted entries; ledger-derived balances; openings as journals; no Group posting; correct contra semantics; tenant isolation; preserve history and unrelated work; independent review and accountant approval before accounting schema changes. Reason: recoverable, trustworthy financial records. Consequences: WP00 documentation only, READY FOR REVIEW, no merge/deploy/next implementation. Affected areas: every ACCT requirement, all release gates.

## DEC-002 — Preserve accepted commercial and UI policies

Date: existing policy, reaffirmed 2026-09-18. Status: EXISTING ACCEPTED DECISION (repository evidence).
Context: migrations 20260911090000, 20260913225446, 20260913231456; historical UI program. Decision: Solo/Starter/Business monthly EGP 399/599/1099; annual monthly × 12 × 0.68 = 3255.84/4887.84/8967.84. Private 14-day trial with Business product limits except Priority Support, no paid plan/card at signup. Expired history remains readable. Preserve private compatibility plans and provider IDs; old commercial Step 21 remains deferred, not completed. Plan changes are preflight/manual handoff, not automated provider mutation. PrimeVue unstyled + Building Suit design tokens/RTL retained; UI-18 exclusively owns admin/pricing/offers after UI-01–17. Reason: preserve approved progress. Consequences: provider mapping/billing interval still need live verification; no historical-price restoration. Affected: LAUNCH-03/04, UI program.
Supersession: private trial replaces the older new-signup ledger_suit trial narrative only; it does not authorize migrating existing compatibility subscriptions.

## DEC-003 — Group, control, contra and historical classifications

Date: 2026-09-18. Status: PROPOSED — accountant/founder approval pending in WP01.
Context: generated normal balance, mutable master/report joins and direct parent postings exist. Decision proposed: separate node kind, contra and statement mapping; deny Group posting everywhere; subledger-controlled AR/AP, exceptional adjustment only with approved reconciliation; preserve historical classification with effective dates/report versions. Reason: correct signs and totals without restating history. Consequences: no automatic parent→Group mapping; reviewed exceptions and V1 compatibility required. Affected: ACCT-01/02/07/09, WP02/06/07. Alternatives to decide: prohibit all manual Control adjustments versus specific permission with allocation; effective dating versus report snapshot versioning.

## DEC-004 — Opening and cutover policy

Date: 2026-09-18. Status: PROPOSED — accountant approval pending.
Context: existing opening RPC balances against OBE; no accepted bulk cutover workflow. Decision proposed: explicit side/date/rate, validated balanced bulk TB, cutoff lock, source/retry keys, year-start or midyear mode, reconciled OBE clearance. Reason: avoid double-imported history and misleading YTD profit. Consequences: confirm which historical/YTD balances are carried and who signs cutover; do not treat OBE as a silent plug. Affected: ACCT-04, WP04.

## DEC-005 — Safe corrections under commercial limits

Date: 2026-09-18. Status: PROPOSED — founder/accountant approval pending.
Context: reversals consume monthly quota; FX table guards apply after downgrade, and expiry blocks writes. Decision required: controlled correction exception or documented support/entitlement recovery path, with abuse limits and immutable audit. Reason: users must be able to correct financial errors without deleting history. Consequences: retain current policy until reviewed replacement; no ad-hoc bypass. Affected: ACCT-15, LAUNCH-03, WP08. This decision does not supersede existing quota counting yet.

## DEC-006 — Period locks and journal identity

Date: 2026-09-18. Status: PROPOSED — accountant approval pending.
Context: books_locked_until plus privileged override is present; full lifecycle and fiscal-year journal sequence are not established. Decision required: numbering allocation/non-reuse, optional approval flow, soft/hard close and reasoned reopen, lock/posting serialization. Reason: auditable accounting operations. Consequences: define hard-close override behavior before new tables/RPCs; retain original journal links on correction. Affected: ACCT-05/10/14, WP05/08.

## DEC-007 — Advertised activity and module scope

Date: 2026-09-18. Status: PROPOSED — founder/accountant approval pending.
Context: review requires bank reconciliation, fixed assets, dimensions and optional tax/inventory. Decision required: first target business activities and minimum bank/assets workflows; dimensions and compliance module timing. Reason: scope must match real accountant usage and public claims. Consequences: bank/assets remain in committed roadmap; no silent deferral. Inventory/COGS becomes Must Have if trading is advertised; tax obligations require current official research and human review. Multi-branch/advanced analytics/developer API remain accepted Coming Soon. Affected: ACCT-11/12/13, LAUNCH-08, WP09/10.

## DEC-008 — Canonical planning and prior-plan consolidation

Date: 2026-09-18. Status: FOUNDER-MANDATED canonical structure; sequencing proposals pending independent review.
Context: several historical plans described different snapshots. Decision: launch master is overall authority, Accounting V2 master owns accounting details; ROADMAP maps all 18 UI and 23 commercial steps, with original files historical provenance only. Reason: new sessions must recover one state. Consequences: only PH-01 and WP00 current; no old completion statement grants launch readiness. Affected: all docs. Supersedes the active-plan designation of launch-readiness-plan.md and improvement-plan.md, preserving their requirements and order.

## DEC-009 — Remote evidence and valuable data

Date: 2026-09-18. Status: FOUNDER-MANDATED preservation; operational verification pending.
Context: deployment docs claimed linked auto-apply and disposable data; connected Supabase project list did not establish the Ledger Suit target. Decision: treat every remote target as valuable until owner proves identity and data status; repository migrations are intended schema, not applied evidence. Reason: historical TRUNCATE and unverified backups. Consequences: no remote SQL or guessed project ID in WP00; Tareq supplies environment mapping, applied versions and restore evidence for release. Affected: RISK-001/009, LAUNCH-02/09.
