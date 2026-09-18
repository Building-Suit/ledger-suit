# Release checklist

Status: NOT STARTED; all gates NOT VERIFIED. This checklist is the active release authority; former launch-deployment-checklist.md is historical operational provenance. Tareq is accountable release owner. No release is authorized by WP00.

- [ ] REL-01 Freeze candidate SHA/PR, independent reviewer and target environment; reconcile CURRENT_STATUS and traceability with actual merge state.
- [ ] REL-02 ACCT required scope and all 15 golden scenarios pass against independently calculated expected values; signed ACCOUNTANT_UAT; no unresolved P0 or blocking High/Critical accounting/security risk.
- [ ] REL-03 Fresh lint/typecheck/build, Edge contracts, clean migration replay, pgTAP, DB lint, generated-type drift and Chromium E2E for exact candidate; mocks distinguished from provider integration.
- [ ] REL-04 Populated-data migration and restore rehearsed; old-app/schema compatibility; known backups/storage coverage and approved rollback criteria. Stop for pending historical TRUNCATE on valuable target.
- [ ] REL-05 Tenant isolation/direct RPC/REST/storage, role revocation, cache switching, retries and posting/close/quota races accepted.
- [ ] REL-06 Onboarding, template/opening, main postings, journal/report drill-down and read-only expiry usable in English/Arabic, desktop/mobile and both themes; help/demo accepted.
- [ ] REL-07 Paymob six prices/modes/card/MOTO, signed snapshots, duplicate/out-of-order/failure/renewal/cancellation, confirmations and preserved compatibility IDs verified. Manual plan-change handoff is honest.
- [ ] REL-08 Current legal/disclosure review, support routing/incident drill and observability/analytics evidence attached.
- [ ] REL-09 Real accountant beta completed; blocking feedback closed and independently retested.
- [ ] REL-10 G1–G8 VERIFIED with evidence timestamp/environment and named approvers; founder go/no-go signed; proceed through PRODUCTION_CHECKLIST only after authorization.

Release evidence record must include operator, UTC time, source/deployed SHA, app/Edge versions, migration IDs, command/result/artifact, UAT signer, backup/restore reference, open risks and go/no-go. Do not include secrets, full provider payloads or customer financial rows. Missing evidence keeps a gate NOT VERIFIED, not silently checked.
