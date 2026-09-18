# Post-launch operating plan

Status: NOT STARTED; dependency PH-06 accepted release. Owner: Tareq until support/product owners are named. This is a plan, not evidence of deployed monitoring.

First day: review posting/report/payment/onboarding failure rates, tenant/security alarms and support feedback; compare production accounting aggregates with accepted smoke baseline. First week: daily triage and accountant follow-up; verify trial expiry/conversion and recurrence/renewal boundaries as they occur. Thereafter: weekly product/reliability review, monthly backup restore and access review cadence proposed for owner approval; record actual drill results and adjust cadence to agreed RPO/RTO.

| Metric group | Events / measures | Decision use |
|---|---|---|
| Acquisition | visitors, signups, campaign source | Small approved acquisition experiments, never scale without conversion evidence |
| Activation | company created, chart configured, first journal, first report | Identify onboarding steps where accountants stop |
| Conversion | trial started/expired, verified paid activation, trial→paid | Reconcile analytics with server billing state; no client-return success inference |
| Product | active organizations, journals created, reports opened | Required-workflow usefulness without collecting ledger contents |
| Reliability | posting/report/payment/RPC/client failures, latency and retries | Incident thresholds, release rollback/forward repair |
| Retention | returning users/organizations by cohort | Prioritize support and missing-workflow fixes |

Use minimal metadata and redacted correlation IDs; approve retention/consent before instrumentation. Assign alert routing and response expectations, then test with synthetic failures.

Support taxonomy: Bug → reproduce/engineer; Feature Request → scoped roadmap; Accounting Question → accountant; Billing Issue → billing operator/provider reconciliation; Security Issue → private security escalation. P0 accounting/data or tenant leak triggers incident containment, preservation, root cause, reviewed repair, regression and accountant reopening. Keep incident, risk, affected requirement and release links in the same record.

Deferred scope remains visible: UI-18 admin/pricing/offers only after UI-01–17; automated Paymob changes and legacy subscription mapping only after explicit approval; Scale/Enterprise purchase, multi-branch, advanced analytics and Developer API remain Coming Soon. Bank/assets/dimensions/tax/inventory follow DEC-007 and cannot be silently moved here from required launch scope.
