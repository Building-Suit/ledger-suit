# Ledger Suit public launch master plan

Canonical overall plan; Accounting V2 details live in [its master](../accounting-v2/MASTER_PLAN.md). Last evidence refresh: 2026-09-18. Development Complete ≠ Product Ready ≠ Launch Ready.

## Product goal

Ledger Suit is Public Launch Ready only when an accountant can use it for real daily work with reconciled, traceable accounting; the service is stable and tenant-safe; users onboard without developer assistance; subscriptions and payments work end to end; support and legally reviewed policies are available; real accountant beta feedback is resolved; truthful marketing and analytics are ready; and production deployment/recovery are verified. Paid advertising starts only after all eight gates pass and the founder approves release.

## Current phase

Exactly one current major phase: **PH-01 — Evidence and accounting design** (IN PROGRESS). Exactly one active work package: **WP00** (READY FOR REVIEW). No canonical work package has yet been independently accepted as COMPLETED. Historical merged changes remain evidence, not V2 acceptance.

## Phases

| ID / name | Priority / status | Dependencies | Requirements / tasks | Acceptance criteria | Required tests | Human review | Deliverables |
|---|---|---|---|---|---|---|---|
| PH-01 Evidence and accounting design | P0 / IN PROGRESS | Audited repository | WP00 then WP01: reconcile plans and approve accounting/scope | Independent WP00 acceptance; signed domain decisions and fixture arithmetic | Docs consistency, baseline matrix, fixture review | ChatGPT independent reviewer; founder; accountant | 18 canonical documents, signed specification |
| PH-02 Accounting V2 | P0 / NOT STARTED | PH-01 | WP02–WP11 per accounting master | Required ACCT scope implemented, reconciled, migrated safely, UAT signed | Golden 15, DB/security/concurrency, EN/AR browser, migration/restore | Accountant and independent technical/security reviewers | Accounting V2 evidence and release candidate |
| PH-03 Product readiness | P0 / NOT STARTED | PH-02; ordered UI prerequisites in ROADMAP | LAUNCH-01/02/05; onboarding, demo/help, UX, performance, observability | Advertised end-to-end journeys usable and monitored | OTP→company→chart→opening→posting→reports; permissions/theme/RTL/large data; incident exercise | Product/accountant/support | PRODUCT_READINESS evidence, help/demo/monitoring |
| PH-04 Commercial legal and operations | P0 / NOT STARTED | PH-03; accepted pricing preserved throughout | LAUNCH-03/04/06/09; Paymob, policies, support, backups | Six prices/provider mode verified; lifecycle/renewal verified; legal approval and restore proved | Payment success/fail/retry/expiry/cancel; restore; support escalation | Founder, billing operator, legal/security | Provider/legal/runbook evidence |
| PH-05 Accountant beta | P0 / NOT STARTED | PH-04; safe beta entry gates | LAUNCH-07; invited accountant/SME sessions and feedback | Real usage, no unresolved P0 or workflow-blocking P1; signed retests | Full UAT + actual beta task observations | Accountants/product owner | BETA_FEEDBACK and UAT sign-offs |
| PH-06 Public launch | P0 / NOT STARTED | PH-05; G1–G8 VERIFIED | LAUNCH-08/09; positioning, landing/demo, approved release, small ad experiment | Stable production, truthful claims, measured activation/conversion, founder go | Production smoke, tracking verification, rollback readiness | Founder release approval | Release record, launch assets and measurement |
| PH-07 Post-launch operation | P1 / NOT STARTED | PH-06 | LAUNCH-10; reliability, retention, feedback, approved deferred scope | Incidents triaged, metrics reviewed, improvements evidence-led | Recovery drills, regression and funnel checks | Founder/support/accountant as applicable | POST_LAUNCH_PLAN records |

Phases are dependency groups, not permission to postpone a safety defect. Accounting UI may need existing UI foundation work within PH-02; preserve UI order and record an explicit reviewed sequencing amendment before changing it. No separate competing UI master.

## Launch control board

| Gate | Area | Verification | Evidence missing to open gate | Owner |
|---|---|---|---|---|
| G1 | Accounting and reports | NOT VERIFIED | V2 scope, independent reconciliation, signed UAT, no open blocking accounting risks | Accountant + engineer |
| G2 | Technical and recovery | NOT VERIFIED | Full current baseline, migration/restore rehearsal, deployed stability | Tareq + engineer |
| G3 | Security | NOT VERIFIED | Effective live RLS/grants/storage, isolation, no open Critical/High security issue | Security reviewer |
| G4 | UX | NOT VERIFIED | Full accountant onboarding and daily-work EN/AR usability acceptance | Product + accountant |
| G5 | Commercial | NOT VERIFIED | Real provider six-plan mapping, renewal/expiry/callback lifecycle | Tareq |
| G6 | Legal | NOT VERIFIED | Current official research and qualified policy/disclosure approval | Legal reviewer + founder |
| G7 | Support | NOT VERIFIED | Staffed channels, bug/security/billing/accounting routing and incident drill | Support owner to be named |
| G8 | Beta | NOT VERIFIED | Real accountant usage and resolved critical feedback | Founder + beta accountants |

NOT VERIFIED is missing evidence, not FAILED. Gate status is independent of development/WP status. No gate is green from page existence or historical CI.

## Review and completion

- [x] WP00 produced reviewable documentation and baseline evidence.
- [ ] Independent WP00 review accepted.
- [ ] WP01 accountant/founder decisions signed.
- [ ] G1–G8 verified for exact release/environment.
- [ ] Founder authorizes public launch/ads.

Read [CURRENT_STATUS](CURRENT_STATUS.md) first; then DECISIONS, OPEN_RISKS, ROADMAP and accounting traceability. Update them in every work package. No automatic merge, promotion or next package.
