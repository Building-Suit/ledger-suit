# Current state audit

Audit date: 2026-09-18. Audited branch origin/dev at **8de315838b0d6a23e0bf523813a29c9d9e8bd13d**. Work branch codex/wp00-planning-bootstrap in isolated worktree /home/tareq/Dev/ledger-suit-wp00. Original worktree /home/tareq/Dev/ledger-suit started clean on codex/paymob-contract-follow-up at 6802580. At handback it is clean on dev at 8de3158; its reflog shows a checkout and fast-forward pull during this session, outside the WP00 commands. WP00 did not modify or revert that concurrent progress. No AGENTS.md found in applicable ancestors or tracked tree. Existing canonical launch/accounting directories were absent at startup. All seven existing docs and README were inspected; old plans were reconciled with migration definitions, source and Git history.

Fetched origin read-only; main 154816171321ca08eb60dcfab89c51c073e613b4, stg 812d81fd3b5e71206ec26b48da01698a2dddbac1; gh pr list returned no open PRs. Remote state is a timestamped observation, not perpetual truth. Initial WP00 handback was a local documentation diff. On 2026-09-18 the founder explicitly authorized commit/push and a PR targeting dev; published as [PR #94](https://github.com/Building-Suit/ledger-suit/pull/94), initial documentation commit `01660c4`. See CURRENT_STATUS for publication evidence. No merge or deployment authorized. [Pinned source tree](https://github.com/Building-Suit/ledger-suit/tree/8de315838b0d6a23e0bf523813a29c9d9e8bd13d).

## Evidence model and limits

Code inspected ≠ fresh test passed ≠ deployed ≠ accountant approved. Test commands/results live in [TEST_PLAN](TEST_PLAN.md). All deployment and accountant-UAT evidence is NOT VERIFIED. Static inspection covered the complete ordered migration inventory and redefinition search, with detailed reading of accounting, authorization, quota/import/payment/report bodies and affected UI/tests. This is a planning audit, not exhaustive formal verification of every SQL path.

Connected Supabase list_projects returned Finance Suit (PG15) and Building Suit (PG17); neither was tied to this repository/environment by trusted evidence. No project guessed, no financial rows read, no remote queries/mutations. Tareq owns establishing Ledger Suit staging/production refs and applied migration state. Vercel deployment identity and Paymob environment were not established. Legal/tax compliance is reserved for current official research and qualified review in PH-04, not inferred from pages.

## Inputs inspected

Read local Ledger_Suit_Accounting_Improvement_Review_AR.docx via OOXML text, including proposed account tree/control/contra/opening/Journal Center/report/subledger/period requirements. It explicitly requests accountant review; it is not signed approval. Source location: /home/tareq/Downloads/. Excel سيستم محاسبى.xlsx inspected structurally via OOXML: MAIN, تكويد - ميزان مراجعه, Journal Entry Recording, تجار, عملاء, قائمة دخل[trailing space], المركز المالى[trailing space]. Labels include account codes/debit/credit/movement/report totals. Formula examples use AGGREGATE and sheet links; placeholders/pivots are not validated ledger/subledger data. No workbook recalculation or formula correctness claim, and no import performed.

Design sources found under Downloads/Building Suit Design System-handoff/building-suit-design-system/project/: tokens/colors.css, uploads/design-tokens.json and four UI/component/dark/light guides. Building Navy #16293B / Premium Gold #D89B42, theme-specific actions and RTL are reference constraints. The general guide explicitly targets mobile building management; Ledger Suit needs desktop accountant density/keyboard/navigation. Current app/assets/css/tokens.css and PrimeVue foundation retained. flutter_colors.dart and tailwind.colors.js were not found in searched Downloads/repository paths; no claim to have read them. External files are not committed; requirements/provenance here make the plan recoverable.

## Findings by requirement

| Requirement / area | Effective implementation and exposure | Test evidence / gap | Classification / dependency |
|---|---|---|---|
| ACCT-01 account hierarchy | accounts table has same-org parent FK, cycle trigger, unique lower(code), subtype/type check; create_account parent argument exists, update_account name/code only; accounts.vue form omits parent/normal-side/opening | 01/02/04/14 DB and core-finance browser tests cover portions, not V2 tree semantics | Confirmed V2 gap; WP02/03 |
| ACCT-02 Group/control/contra | normal_balance generated solely from type; no explicit node kind/contra override; require_account checks tenant/archive/type only | No V2 contra/group acceptance | Confirmed scope gap; DEC-003 |
| ACCT-03 engine | create_draft_transaction, post_transaction, app.create_and_post, adjustment/reversal; deferred balance/immutability triggers; row lock and tenant idempotency key | 01 integrity, 02 isolation, 04 hardening, 19 quota, 20 FX, 26 races | Shared engine present, keep; exact path coverage not universal |
| ACCT-04 openings | post_opening_balance accepts array and rate, balances through OBE system key; AddTransactionDialog has opening flow; empty chart means required OBE must exist | 01 opening and 20 FX tests; no accepted bulk opening-TB import/cutover lifecycle | Partial, WP04 |
| ACCT-05 journal center | transactions.vue searches/paginates via search_transactions; TransactionDetailDialog shows journal lines/reversal; saved_views table exists | Existing core-finance and acquisition journeys; no approved numbering/saved-view/context acceptance | Partial, WP05 |
| ACCT-06/07 reports | reporting migration defines account_balances/ledger_entries (security_invoker), TB/P&L/BS/CF/GL; reports.vue; authorized five CSV exports | 01 integrity and 22 exports + report-exports browser (mocked export response); no V2 six-column/classified fixture | Partial, WP06 |
| ACCT-08 navigation/freshness | accounts.vue save calls refreshNuxtData for both caches; useOrgData watches tenant; useTenant clears org: caches in Nuxt context | Existing account-create browser checks visible new row; selector/slow tenant race needs explicit test | User report not reproduced; RISK-004 |
| ACCT-09 subledgers | counterparties and commitment settlements exist; settle_commitment calls income/expense; no full invoice-allocation/aging-control contract found | 03 operational + 15 quota tests do not prove accrual AR/AP | Confirmed scope gap; WP07 |
| ACCT-10 periods | books_locked_until and books.override_lock in assert_books_open; no complete period close/reopen UX | Lock assertions exist; close/post race and workflow UAT pending | Partial, WP08 |
| ACCT-11/12 bank/assets | cash/bank accounts and record_asset_purchase present; no bank-match/reconciliation or depreciation/disposal/register lifecycle found | Asset purchase core checks not lifecycle acceptance | Scope decision WP01, then WP09 |
| ACCT-13 dimensions/tax/inventory | entry.dimensions JSON and inventory subtype are foundations, not modules | No activity-specific module/UAT evidence | DEC-007; WP10 |
| ACCT-14 labels/wizards | record_income/expense/transfer/asset/liability/contribution/withdrawal and manual adjustment share engine | Existing core tests; accountant terminology approval pending | Preserve journals, change labels only with meaning, WP05 |
| ACCT-15 correction restrictions | every new posted reversal consumes transaction quota; currency guards cover accounts/transactions/entries/commitments/recurring | 19/20/26 cover limits and FX boundaries, not approved correction exception | Policy conflict candidate; DEC-005 |

## Specific code implications to investigate

1. Accounts group total excludes any account that is a parent, while account_balances sums only that account's own entries and backend permits posting to parents. This combination can omit parent-held balances from UI totals. It does not prove double-counting in SQL reports. Reproduce a parent with own posting plus child before proposing repair.
2. guard_account_changes prevents type changes with history and protects system subtype, but ordinary subtype/cash_flow_section can change through granted direct account UPDATE under capability/RLS. Current P&L/CF join present account fields; a historical reclassification risk exists even without mutating ledger lines. Determine desired immutable mapping policy and reproduce with a non-system account.
3. report_general_ledger calls require_account, which rejects archived accounts. Readable-history contract needs a dedicated archived GL fixture; no production failure claimed.
4. report_trial_balance has only as-of accumulated debit/credit, not opening/period/closing. report_balance_sheet groups at five-type level. report_cash_flow attributes a journal's net liquid movement to the largest non-liquid counterpart section. create_account does not set cash_flow_section, leaving operating default; review asset/loan setup and mixed journals explicitly.
5. SQL bigint/numeric precision is strong, but app Number conversions and JSON serialization need safe-integer boundary tests. Do not describe frontend math as arbitrary-precision throughout.
6. post_transaction locks draft state; idempotent sequential replay is distinct from two simultaneous first inserts with the same key. Test retry outcome and no duplicate entries. Also test stale draft posting after account archival and concurrent hierarchy/period changes.
7. Historical 20260908120000 TRUNCATE is a confirmed migration hazard, not evidence of production loss. Later migrations do not undo deleted history. Never replay into an existing valuable environment without approved preservation planning.

## Security and operations

RLS and composite FKs defend tenant references; accounts RLS is forced by 20260907123339. Public report views use invoker security; controlled posting functions use fixed empty search_path, capability checks and restricted grants. app is not exposed by local PostgREST config. Security-definer is not proof of safety: inspect deployed owners/grants and direct paths. Accounts still grant authenticated insert/update, so V2 guards must cover direct table writes, not only UI RPCs. Service-context checks include the app.bypass_authz session GUC as well as service-role JWT; some helpers have authenticated EXECUTE for policies, but no ordinary HTTP client path may be allowed to set trusted session state. Live grants/session access need separate review; audit_logs mutation is rejected and audit actors derive from auth context.

Storage uses 20260911205305 reservation/commit/abort/delete lifecycle; quotas include live reservations, private tenant-prefixed keys, cleanup workers and expiry. Audit visibility 90/365/1095 days is not physical deletion; private compatibility plan remains unlimited. useTenant clears org caches, but delayed response races remain a test obligation.

All posting sources retain shared ledger: direct manual/wizard, opening, reversal, adjustment, commitment settlement/auto conversion, recurring occurrence/scheduler and CSV confirm. Later monthly quota/FX triggers protect table boundaries; concurrency hardening takes quota locks before feature locks for import and physical plan changes. 26_launch_plan_hardening uses dblink sessions, so concurrency coverage exists; do not claim every accounting race is covered.

Catalog migration stores six accepted EGP prices; private trial final override is 20260913225446, followed only by trial-aware plan-change wrapper. Checkout context resolves database plan/price and signed provider metadata; service-only fulfillment deduplicates provider events. Webhook addInterval uses JavaScript UTC month/year changes; provider frequency uses a separate heuristic. Month-end/leap-year/renewal/cancellation must be verified with provider contract. Payment confirmation tests use mocked delivery; actual Resend/SMTP and callback-after-email-failure replay remain external checks. Public legal/contact pages are present, not legal approval.

## Fresh browser finding

TEST-10 full run: 45 passed, one invitation loading timeout (acquisition.spec.ts:49, expected heading absent after 5s). TEST-10R unchanged focused rerun passed. This is an observed test instability, not a diagnosed product root cause or a fully green suite. Keep RISK-014 open; no runtime/test repair made.

## Migration order and effective-definition evidence

The inventory below covers every committed migration in lexical execution order. Filename describes scope; a later replacement and ALTER/SET SCHEMA can change the effective object. Do not infer deployed schema from this list.

| Order | Migration |
|---|---|
| 1 | [20260830115900_verify_deployment_pipeline](../../supabase/migrations/20260830115900_verify_deployment_pipeline.sql) |
| 2 | [20260830120000_extensions_and_shared](../../supabase/migrations/20260830120000_extensions_and_shared.sql) |
| 3 | [20260830120500_profiles](../../supabase/migrations/20260830120500_profiles.sql) |
| 4 | [20260830121000_organizations](../../supabase/migrations/20260830121000_organizations.sql) |
| 5 | [20260830121500_organization_members](../../supabase/migrations/20260830121500_organization_members.sql) |
| 6 | [20260830122000_authorization_helpers](../../supabase/migrations/20260830122000_authorization_helpers.sql) |
| 7 | [20260830122500_accounting_types](../../supabase/migrations/20260830122500_accounting_types.sql) |
| 8 | [20260830123000_accounts](../../supabase/migrations/20260830123000_accounts.sql) |
| 9 | [20260830123500_categories](../../supabase/migrations/20260830123500_categories.sql) |
| 10 | [20260830124000_counterparties](../../supabase/migrations/20260830124000_counterparties.sql) |
| 11 | [20260830124500_transactions](../../supabase/migrations/20260830124500_transactions.sql) |
| 12 | [20260830125000_transaction_entries](../../supabase/migrations/20260830125000_transaction_entries.sql) |
| 13 | [20260830125500_audit_logs](../../supabase/migrations/20260830125500_audit_logs.sql) |
| 14 | [20260830130000_posting_engine](../../supabase/migrations/20260830130000_posting_engine.sql) |
| 15 | [20260830130500_transaction_flows](../../supabase/migrations/20260830130500_transaction_flows.sql) |
| 16 | [20260830131000_default_chart_of_accounts](../../supabase/migrations/20260830131000_default_chart_of_accounts.sql) |
| 17 | [20260830131500_tags_and_saved_views](../../supabase/migrations/20260830131500_tags_and_saved_views.sql) |
| 18 | [20260830132000_attachments](../../supabase/migrations/20260830132000_attachments.sql) |
| 19 | [20260830132500_notifications](../../supabase/migrations/20260830132500_notifications.sql) |
| 20 | [20260830133000_subscriptions](../../supabase/migrations/20260830133000_subscriptions.sql) |
| 21 | [20260830133500_rls_policies](../../supabase/migrations/20260830133500_rls_policies.sql) |
| 22 | [20260830134000_reporting](../../supabase/migrations/20260830134000_reporting.sql) |
| 23 | [20260830150000_transaction_queries](../../supabase/migrations/20260830150000_transaction_queries.sql) |
| 24 | [20260831090000_commitments](../../supabase/migrations/20260831090000_commitments.sql) |
| 25 | [20260831090500_commitment_functions](../../supabase/migrations/20260831090500_commitment_functions.sql) |
| 26 | [20260831091000_recurring_rules](../../supabase/migrations/20260831091000_recurring_rules.sql) |
| 27 | [20260831091500_recurring_functions](../../supabase/migrations/20260831091500_recurring_functions.sql) |
| 28 | [20260831092000_phase3_rls_and_reminders](../../supabase/migrations/20260831092000_phase3_rls_and_reminders.sql) |
| 29 | [20260831095604_phase1_to_phase3_hardening](../../supabase/migrations/20260831095604_phase1_to_phase3_hardening.sql) |
| 30 | [20260831095606_operational_workflows](../../supabase/migrations/20260831095606_operational_workflows.sql) |
| 31 | [20260831131512_phase4_stripe_subscription](../../supabase/migrations/20260831131512_phase4_stripe_subscription.sql) |
| 32 | [20260901135311_signup_onboarding](../../supabase/migrations/20260901135311_signup_onboarding.sql) |
| 33 | [20260907123339_harden_account_tenant_isolation](../../supabase/migrations/20260907123339_harden_account_tenant_isolation.sql) |
| 34 | [20260908055432_workspace_access_management](../../supabase/migrations/20260908055432_workspace_access_management.sql) |
| 35 | [20260908120000_user_managed_chart_of_accounts](../../supabase/migrations/20260908120000_user_managed_chart_of_accounts.sql) |
| 36 | [20260908120853_enforce_unique_legal_business_name](../../supabase/migrations/20260908120853_enforce_unique_legal_business_name.sql) |
| 37 | [20260908152800_onboarding_availability_checks](../../supabase/migrations/20260908152800_onboarding_availability_checks.sql) |
| 38 | [20260908160000_update_preview_invitation](../../supabase/migrations/20260908160000_update_preview_invitation.sql) |
| 39 | [20260908170000_custom_roles](../../supabase/migrations/20260908170000_custom_roles.sql) |
| 40 | [20260909063239_editable_system_roles](../../supabase/migrations/20260909063239_editable_system_roles.sql) |
| 41 | [20260909123128_persist_signup_onboarding](../../supabase/migrations/20260909123128_persist_signup_onboarding.sql) |
| 42 | [20260909130826_resume_saved_signup](../../supabase/migrations/20260909130826_resume_saved_signup.sql) |
| 43 | [20260909135009_start_cardless_trial_on_registration](../../supabase/migrations/20260909135009_start_cardless_trial_on_registration.sql) |
| 44 | [20260909165536_support_cardless_signup](../../supabase/migrations/20260909165536_support_cardless_signup.sql) |
| 45 | [20260909180357_restore_currency_reference_data](../../supabase/migrations/20260909180357_restore_currency_reference_data.sql) |
| 46 | [20260909200000_limit_owned_organizations_by_plan](../../supabase/migrations/20260909200000_limit_owned_organizations_by_plan.sql) |
| 47 | [20260909210000_paymob_billing](../../supabase/migrations/20260909210000_paymob_billing.sql) |
| 48 | [20260911090000_launch_plan_catalog](../../supabase/migrations/20260911090000_launch_plan_catalog.sql) |
| 49 | [20260911093000_plan_quota_engine](../../supabase/migrations/20260911093000_plan_quota_engine.sql) |
| 50 | [20260911100000_subscription_readable_history](../../supabase/migrations/20260911100000_subscription_readable_history.sql) |
| 51 | [20260911110000_member_seat_quota](../../supabase/migrations/20260911110000_member_seat_quota.sql) |
| 52 | [20260911124345_account_quota_enforcement](../../supabase/migrations/20260911124345_account_quota_enforcement.sql) |
| 53 | [20260911131925_counterparty_quota_enforcement](../../supabase/migrations/20260911131925_counterparty_quota_enforcement.sql) |
| 54 | [20260911195634_recurring_rule_quota_enforcement](../../supabase/migrations/20260911195634_recurring_rule_quota_enforcement.sql) |
| 55 | [20260911201132_custom_role_quota_enforcement](../../supabase/migrations/20260911201132_custom_role_quota_enforcement.sql) |
| 56 | [20260911205305_aggregate_attachment_storage_quota](../../supabase/migrations/20260911205305_aggregate_attachment_storage_quota.sql) |
| 57 | [20260912094117_monthly_posted_transaction_quota](../../supabase/migrations/20260912094117_monthly_posted_transaction_quota.sql) |
| 58 | [20260912102128_business_multi_currency_enforcement](../../supabase/migrations/20260912102128_business_multi_currency_enforcement.sql) |
| 59 | [20260912110717_csv_import_backend](../../supabase/migrations/20260912110717_csv_import_backend.sql) |
| 60 | [20260912180913_financial_report_csv_exports](../../supabase/migrations/20260912180913_financial_report_csv_exports.sql) |
| 61 | [20260912184018_audit_history_visibility_window](../../supabase/migrations/20260912184018_audit_history_visibility_window.sql) |
| 62 | [20260913105458_plan_aware_paymob_checkout](../../supabase/migrations/20260913105458_plan_aware_paymob_checkout.sql) |
| 63 | [20260913164343_plan_change_safety](../../supabase/migrations/20260913164343_plan_change_safety.sql) |
| 64 | [20260913171823_launch_plan_concurrency_hardening](../../supabase/migrations/20260913171823_launch_plan_concurrency_hardening.sql) |
| 65 | [20260913225446_business_level_trial](../../supabase/migrations/20260913225446_business_level_trial.sql) |
| 66 | [20260913231456_distinguish_trial_plan_change](../../supabase/migrations/20260913231456_distinguish_trial_plan_change.sql) |

### Effective definition chains

Full-chain search found these defining replacements; later grants/triggers are applied in addition. Report RPCs and account normal_balance remain defined by their original migrations, with view security reasserted later.

| Symbol | Definition chain (last is effective body) | Additional effective constraint |
|---|---|---|
| `app.guard_account_changes` | 20260830123000:138 | See full migration inventory for grants and callers |
| `app.guard_account_hierarchy` | 20260830123000:214 | See full migration inventory for grants and callers |
| `public.create_account` | 20260831095606:3 → 20260908120000:98 | Plan quota/FX table triggers still apply |
| `public.update_account` | 20260831095606:43 | See full migration inventory for grants and callers |
| `app.require_account` | 20260830130000:44 | See full migration inventory for grants and callers |
| `app.normalize_journal_lines` | 20260830130000:191 | See full migration inventory for grants and callers |
| `public.post_transaction` | 20260830130000:426 | Plan quota/FX table triggers still apply |
| `app.create_and_post` | 20260830130000:496 | Plan quota/FX table triggers still apply |
| `public.reverse_transaction` | 20260830130000:661 | Plan quota/FX table triggers still apply |
| `public.post_opening_balance` | 20260830130500:584 | Plan quota/FX table triggers still apply |
| `app.fill_entry_from_transaction` | 20260830125000:81 | See full migration inventory for grants and callers |
| `app.guard_transaction_entry` | 20260830125000:153 | See full migration inventory for grants and callers |
| `app.assert_books_open` | 20260830122000:335 | See full migration inventory for grants and callers |
| `public.report_trial_balance` | 20260830134000:91 | See full migration inventory for grants and callers |
| `public.report_general_ledger` | 20260830134000:385 | See full migration inventory for grants and callers |
| `app.start_default_subscription` | 20260830133000:246 → 20260831131512:99 → 20260909135009:13 → 20260913225446:43 | See full migration inventory for grants and callers |
| `app.subscription_access_state` | 20260831131512:125 → 20260909135009:39 → 20260911100000:5 | See full migration inventory for grants and callers |
| `app.capability_available` | 20260831131512:183 → 20260909135009:69 → 20260911100000:38 | See full migration inventory for grants and callers |
| `public.my_capabilities` | 20260830122000:364 → 20260831131512:215 → 20260909135009:86 → 20260911100000:59 | See full migration inventory for grants and callers |
| `app.plan_quota_usage` | 20260911093000:154 → 20260911205305:45 → 20260912094117:192 | See full migration inventory for grants and callers |
| `app.assert_plan_feature` | 20260911093000:236 → 20260913171823:90 | See full migration inventory for grants and callers |
| `public.confirm_csv_import_batch` | 20260912110717:521 → 20260913171823:128 | See full migration inventory for grants and callers |
| `public.plan_change_impact` | 20260913164343:5 → 20260913231456:18 | 20260913164343 body moved from public to app by 20260913231456; public wrapper is final |
| `public.apply_paymob_subscription_event` | 20260909210000:58 → 20260913105458:79 | See full migration inventory for grants and callers |
| `public.create_organization` | 20260830131000:161 → 20260908120000:15 → 20260908120853:10 | See full migration inventory for grants and callers |
