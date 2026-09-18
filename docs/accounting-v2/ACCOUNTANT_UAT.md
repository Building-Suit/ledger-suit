# Accountant acceptance testing

Status: NOT STARTED. Verification: NOT VERIFIED. No accountant has executed or signed this plan. The supplied DOCX is a review proposal. Named accountant, qualification/context and target activities: pending founder assignment in WP01.

Use [TEST_PLAN](TEST_PLAN.md) independent GOLD-01–15 fixtures. Record candidate SHA, environment, UTC date, tenant fixture ID (redacted), tester, expected/actual journal/GL/TB/P&L/position, evidence link, defects, retest and signed decision. Engineer test success cannot substitute for signature.

| UAT ID | Scenario | Expected evidence | Result / signer |
|---|---|---|---|
| UAT-01 | Capital contribution | GOLD-01 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-02 | Cash expense | GOLD-02 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-03 | Cash revenue | GOLD-03 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-04 | Credit sale | GOLD-04 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-05 | Customer collection | GOLD-05 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-06 | Supplier bill | GOLD-06 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-07 | Supplier payment | GOLD-07 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-08 | Transfer | GOLD-08 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-09 | Asset purchase | GOLD-09 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-10 | Loan | GOLD-10 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-11 | Owner withdrawal | GOLD-11 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-12 | Depreciation | GOLD-12 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-13 | Opening balance | GOLD-13 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-14 | Reversal | GOLD-14 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-15 | Period locking | GOLD-15 exact lines, per-account six-column TB, GL and statements | NOT VERIFIED / pending |
| UAT-16 | Chart hierarchy, codes, archive and contra | No group posting; control policy; correct accumulated depreciation/returns/drawings signs; historical GL | NOT VERIFIED / pending |
| UAT-17 | Single/bulk opening and midyear cutover | Preview, invalid rows, OBE clearance, duplicate/reversal/cutoff behavior | NOT VERIFIED / pending |
| UAT-18 | Journal Center and drill-down | Number/source/lines/filter/saved views; Arabic labels; account/counterparty drawers; Back/Forward/scroll | NOT VERIFIED / pending |
| UAT-19 | Classified reports and cash flow | Current/non-current, profit closure, mixed CF journal, no parent double count, CSV/optional export trace | NOT VERIFIED / pending |
| UAT-20 | AR/AP statements and aging | Invoice/settlement/due dates/partial/advance and control reconciliation | NOT VERIFIED / pending |
| UAT-21 | Bank reconciliation | Match/unmatch, duplicate statement line, fees, outstanding balance reconciled | NOT VERIFIED / pending scope |
| UAT-22 | Asset lifecycle | Acquisition, approved depreciation, disposal gain/loss and accumulated depreciation | NOT VERIFIED / pending scope |
| UAT-23 | Dimensions and activity-specific modules | Dimension sums, inventory/COGS/tax scope and required current professional review | NOT VERIFIED / pending scope |
| UAT-24 | Corrections at quota/expiry/downgrade | Approved recovery path preserves immutable history and control reconciliation | NOT VERIFIED / pending policy |

WP01 design sign-off must resolve chart codes/templates, five-type classifications, Group/Control policy and exceptions, contra defaults/signs, year-start versus midyear opening, Arabic labels, required reports/comparisons, AR/AP control versus per-counterparty GL exceptions, periods/numbering/approvals, dimensions and activity-specific tax/inventory. Also agree bank/assets launch scope. Each decision: approve / change / add, reason, signer, date and source evidence.

UAT execution approval is later than design sign-off. Any P0 accounting/data integrity issue blocks acceptance and release. Record P1 workflow blockers and P2/P3 disposition with owner; link every defect to OPEN_RISKS/BETA_FEEDBACK and affected requirement. A signed exclusion may mark a scenario NOT APPLICABLE only with explicit scope decision and truthful marketing; never use N/A to hide required workflows.
