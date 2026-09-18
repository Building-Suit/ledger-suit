# Consolidated roadmap and provenance

One active overall master: [MASTER_LAUNCH_PLAN](MASTER_LAUNCH_PLAN.md). Accounting sequence: [MASTER_PLAN](../accounting-v2/MASTER_PLAN.md). WP00 → WP01 (decision/sign-off) → WP02 (first implementation). No package starts automatically.

## Accounting priority and advertised scope

Must Have: ACCT-01–10 and ACCT-14/15 because correct chart, opening, journals, traceable reports, AR/AP and periods are required accountant workflows. ACCT-11 bank reconciliation and ACCT-12 asset lifecycle remain committed P1 scope, provisional Must Have until WP01 approves target-activity-specific acceptance or explicit deferral. ACCT-13 dimensions/tax/inventory is Should Have or Later only after DEC-007; becomes Must Have whenever required for advertised activity or legal obligations. Optional templates are retained; adoption is optional for the user, not removal from the roadmap. Comparisons and optional Excel/PDF are Should Have unless a required workflow depends on them. No tax/compliance assertion in this audit.

## Original 18-step UI program

[Original source](../improvement-plan.md) is historical provenance. Preserve UI ordering: each UI-n depends on all preceding UI steps being independently reviewed, even when accounting packages interleave. Table below records acceptance conservatively; code overlap is not task completion. Accounting schema can follow its own signed dependency path; a UI sequencing conflict must be resolved by explicit founder/reviewer decision, never by starting UI-18 early.

| ID | Requirement | Evidence / status | Accounting or launch integration |
|---|---|---|---|
| UI-01 | PrimeVue foundation | Merged code evidence: 8e01f8f (#87); no independent V2 acceptance | WP03/05 foundation |
| UI-02 | DataTable foundation and core tables | NOT STARTED; current accounts/transactions use native tables | WP03/05 |
| UI-03 | Remaining tables | NOT STARTED | WP05/06 |
| UI-04 | Form system and floating-label foundation | NOT STARTED; existing FloatingField is not proof of full program | WP03/04 |
| UI-05 | Floating-label audit | NOT STARTED | WP03/05 |
| UI-06 | Reports ledger refresh | NOT STARTED; reproduce current behavior | WP06, RISK-012 |
| UI-07 | Attachment pipeline | NOT STARTED UI work; reservation backend already exists | WP05, LAUNCH-02 |
| UI-08 | Controlled subtype | NOT STARTED program acceptance; current select and SQL type check exist | WP03 |
| UI-09 | Create/edit parity | NOT STARTED; update_account accepts name/code only | WP03 |
| UI-10 | Create tags and attachments | NOT STARTED | WP05 |
| UI-11 | CSV template | NOT STARTED program acceptance; transaction imports already exist | WP04/LAUNCH-01 |
| UI-12 | Organization/profile settings | NOT STARTED | LAUNCH-01 |
| UI-13 | Usage meters and quota UX | NOT STARTED program acceptance; existing meters preserved | LAUNCH-03 |
| UI-14 | How It Works modal | NOT STARTED | LAUNCH-01/06 |
| UI-15 | Advanced roles/permissions UX | NOT STARTED; existing capability architecture preserved | LAUNCH-02 |
| UI-16 | Role-aware notifications | NOT STARTED; existing notifications preserved | LAUNCH-05 |
| UI-17 | EN/AR content rewrite | NOT STARTED; preserve keys/interpolation and obtain supplied locale review | WP05/LAUNCH-01 |
| UI-18 | Admin/pricing/yearly offers engine | NOT STARTED; exclusively final UI step after all 17 predecessors | Later; DEC-002 |

## Original 23 commercial steps

[Original 2026-09-10 audit](../launch-readiness-plan.md), SHA 60d3d5f9, is historical; old missing-quota/import and 600/4800 pricing narratives are superseded by audited code. Rows below are code/history evidence only; current deployment/UAT is NOT VERIFIED for every row. They are retained requirements feeding LAUNCH-03 and G5, not another active execution list.

| Legacy step | Scope | Audited evidence | Current disposition |
|---|---|---|---|
| COM-01 | Current-state audit and execution plan | `docs/launch-readiness-plan.md; 60d3d5f9 snapshot` | Code or document present; production acceptance NOT VERIFIED |
| COM-02 | Catalog | `20260911090000_launch_plan_catalog.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-03 | Quota engine | `20260911093000_plan_quota_engine.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-04 | Readable expiry history | `20260911100000_subscription_readable_history.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-05 | Members | `20260911110000_member_seat_quota.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-06 | Accounts | `20260911124345_account_quota_enforcement.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-07 | Counterparties | `20260911131925_counterparty_quota_enforcement.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-08 | Recurring | `20260911195634_recurring_rule_quota_enforcement.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-09 | Custom roles | `20260911201132_custom_role_quota_enforcement.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-10 | Storage | `20260911205305_aggregate_attachment_storage_quota.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-11 | Monthly transactions | `20260912094117_monthly_posted_transaction_quota.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-12 | Multi-currency | `20260912102128_business_multi_currency_enforcement.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-13 | CSV backend | `20260912110717_csv_import_backend.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-14 | CSV UI | `app/pages/imports.vue; commit 3f59e0c #76` | Code or document present; production acceptance NOT VERIFIED |
| COM-15 | Report CSV exports | `20260912180913_financial_report_csv_exports.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-16 | Audit visibility | `20260912184018_audit_history_visibility_window.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-17 | Plan-aware checkout | `20260913105458_plan_aware_paymob_checkout.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-18 | Pricing UI | `app/components/BillingCheckout.vue; e67f456 #81` | Code or document present; production acceptance NOT VERIFIED |
| COM-19 | Usage UX | `app/components/UsageMeters.vue; 713c40c #82` | Code or document present; production acceptance NOT VERIFIED |
| COM-20 | Plan-change safety | `20260913231456_distinguish_trial_plan_change.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-21 | Legacy transition | `Deferred by prior policy; no mapping authorized` | NOT STARTED / explicitly deferred, requires separate approved customer mapping |
| COM-22 | Security/concurrency | `20260913171823_launch_plan_concurrency_hardening.sql` | Code or document present; production acceptance NOT VERIFIED |
| COM-23 | Deployment checklist | `scripts/verify-launch-readiness.sql; d8ebc30 #85` | Code or document present; production acceptance NOT VERIFIED |

The historical new-trial narrative is superseded by DEC-002/private trial (20260913225446), not an instruction to rewrite old subscribers; COM-04 readable history remains preserved. COM-20 remains read-only impact and manual handoff. COM-23 original disposable-data assumption is withdrawn by DEC-009. Preserve approved private compatibility plan, subscription/provider IDs and no-delete downgrade policy. Resolve historical transaction calendar-month decision against implemented immutable workspace-timezone buckets; billing-anniversary change would require new decision/migration, not reinterpretation.

## Document reconciliation

architecture.md is corrected for private trial, plan-aware checkout, immutable usage buckets and reserved upload bytes. deployment.md distinguishes intended deployment workflow from actual applied state and managed-backup evidence. README historical test counts are labeled historical. phase-1-to-3-status.md remains a dated implementation record. Former improvement/readiness/deployment checklists retain their text for provenance with prominent historical notices linking here; their old checkboxes are not active gates.
