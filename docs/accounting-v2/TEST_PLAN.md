# Test plan and evidence

Evidence date: 2026-09-18. Owner: implementation engineer; independent reviewer and accountant sign-off required separately. This WP runs existing baseline only, adds no product test code and repairs no runtime defects.

## Fresh WP00 baseline

Audited source 8de315838b0d6a23e0bf523813a29c9d9e8bd13d; Linux local environment: Node v26.8.1, pnpm 10.33.0, Deno 2.7.10, Supabase CLI 2.116.0, Docker 29.7.2. CI specifies Node 22 / pnpm 11.5.0; local success is not an exact CI-runtime rerun. Lockfile install unchanged. No production credentials/environment used. Nuxt warns missing Supabase URL/key for typecheck/build without runtime env; build still passed, not a deployed connectivity check.

Database isolation: new /tmp/ledger-wp00-disposable-20260918 copy of committed supabase/{migrations,tests,templates,functions,seed.sql,config.toml}, no remote link. Unique project_id ledger-wp00-disposable-20260918, API/DB/Studio/Mailpit 57321/57322/57323/57324, analytics 57327. Existing ledger-suit and shop-suit containers/data untouched. Initial start failed for missing copied functions, then analytics port collision; copied required functions and changed only disposable config port. Successful clean start and explicit --local reset followed. These were harness setup errors, not product defects. Never reuse this reset command against an existing developer/linked DB.

| Evidence ID | Exact command (worktree unless stated) | Fresh result |
|---|---|---|
| TEST-01 | `pnpm install --frozen-lockfile` | PASS, no dependency/lockfile edits |
| TEST-02 | `pnpm lint` | PASS |
| TEST-03 | `pnpm typecheck` | PASS, missing runtime env warnings |
| TEST-04 | `pnpm build` | PASS, Nuxt production output generated locally |
| TEST-05 | `deno test --no-lock --allow-env supabase/functions/_shared/*_test.ts` | PASS: 9 tests |
| TEST-06 | `pnpm exec supabase start --workdir /tmp/ledger-wp00-disposable-20260918` then `pnpm exec supabase db reset --local --workdir /tmp/ledger-wp00-disposable-20260918` | PASS, 66 migrations and committed fake seed replayed |
| TEST-07 | `pnpm exec supabase test db --local --workdir /tmp/ledger-wp00-disposable-20260918` | PASS: 678 assertions, 27 files |
| TEST-08 | `pnpm exec supabase db lint --local --level warning --workdir /tmp/ledger-wp00-disposable-20260918` | PASS: no schema errors |
| TEST-09 | `pnpm exec supabase gen types typescript --local --workdir /tmp/ledger-wp00-disposable-20260918 > /tmp/ledger-wp00-database.types.ts` then `diff -u types/database.types.ts /tmp/ledger-wp00-database.types.ts` | PASS: no drift; tracked types never overwritten |
| TEST-10 | `pnpm exec playwright install chromium`; `SUPABASE_URL=http://127.0.0.1:57321 MAILPIT_URL=http://127.0.0.1:57324 PLAYWRIGHT_PORT=3310 pnpm test:e2e` | FAILED full run: 45 passed, 1 invitation loading timeout at acquisition.spec.ts:49 (5 seconds). Focused unchanged rerun PASS: 1/1; see TEST-10R below |
| TEST-11 | Document path/link/ID/dependency checks plus `git diff --check` and diff/status inspection | PASS: 18 exact canonical paths, 145 internal file links and defined ID ranges checked; 15 golden fixture arithmetic verified; 25 Markdown files only (18 new/7 updated); whitespace clean; complete patch applies to audited base |

Local raw logs are /tmp/ledger-wp00-{lint,typecheck,build,deno,db-reset,db-test,db-lint,e2e}.log and types.diff. They are temporary, not permanent release artifacts; durable command/result summaries are this file. No start/status credential log is a deliverable.

NOT RUN: hosted database migration parity/grants, deployed app/Edge smoke, real Paymob/Resend/SMTP lifecycle, populated-data restore rehearsal, 15 V2 golden scenarios and accountant UAT. Blocker: no established target/provider/restore evidence or approved V2 implementation/signature. Owners: Tareq for target/provider/restore, engineer for V2 fixtures, named accountant pending for UAT. Required commands/checks: confirmed-target read-only migration metadata + scripts/verify-launch-readiness.sql; exact release CI; approved sandbox callback matrix; isolated restore and independent reconciliation. Do not substitute local seed replay for populated-data safety.

### TEST-10R invitation recheck

Command: `SUPABASE_URL=http://127.0.0.1:57321 MAILPIT_URL=http://127.0.0.1:57324 PLAYWRIGHT_PORT=3310 pnpm test:e2e tests/e2e/acquisition.spec.ts --grep 'an invited user'`. Result: PASS 1/1 (19.1s total; test 7.8s), same source/environment and no runtime/test edits. Full run remains recorded as FAILED, not relabeled 46/46 green. First failure snapshot showed Loading… before invitation heading; root cause NOT VERIFIED. RISK-014 retains the instability for a later focused investigation/exact-CI-runtime check. Original run otherwise included a passing account-create visibility test; dependent selector freshness is still unproven.

## Historical CI, inspected read-only

Both runs below target the audited SHA and were created 2026-09-14. Their application and database-and-e2e jobs and individual lint/typecheck/build/Edge/reset/pgTAP/lint/type-drift/Chromium steps report success. These are historical CI evidence, not runs triggered by WP00 or production verification:

- [Run 34850913614](https://github.com/Building-Suit/ledger-suit/actions/runs/34850913614)
- [Run 34850879669](https://github.com/Building-Suit/ledger-suit/actions/runs/34850879669)

## Existing coverage boundaries

DB 01 accounting integrity, 02 tenant isolation, 03 commitments/recurring, 04 hardening, 05 billing, 06–09 onboarding/access/roles/persistence, 10–20 catalog/quotas/expiry/storage/FX, 21 imports, 22 exports, 23 audit visibility, 24 checkout, 25 plan preflight, 26 dblink concurrency, 27 private trial. Read corresponding files in supabase/tests; assertion counts alone do not prove V2 requirements.

Playwright uses real seeded local Supabase login/core operations and also explicit page.route mocks: pricing mocks paymob-checkout and subscription state; report-exports mocks account/export responses; acquisition mocks access/capabilities and delayed transaction data; core-finance mocks role error; other quota/trial/plan-change tests use mocked API states. Therefore browser success does not prove provider integration or all server-side semantics. Deno security/contract/confirmation tests are local unit contracts, not sent emails or charges. No hosted customer data accessed.

## Golden fixtures — design expectations, NOT EXECUTED / NOT APPROVED

All amounts below are EGP major units for human readability; multiply by 100 for bigint minor-unit assertions. Each scenario uses its own fresh organization, Africa/Cairo timezone, base EGP, active entitled access, open books, no tax/FX unless specified. Period 2026-02-01…2026-02-28; starting fixture is posted on 2026-01-31, scenario on 2026-02-10. Default starting journal Dr Cash 10000 / Cr Capital 10000. Reset fixture between scenarios. Different opening fixtures are explicit below.

Use exact account IDs/types (Cash/Bank/AR/Equipment assets; AP/Loan liabilities; Capital/OBE equity; Drawings debit-normal contra equity; AccumDep credit-normal contra asset; Revenue revenue; Expense/DepExpense expenses). AR/AP lines require CUST-A/VEND-A allocation once approved control policy exists. Golden cases describe target accounting even when the current wizard lacks that workflow.

TB tuple for each account = (opening Dr, opening Cr; period Dr, period Cr; closing Dr, closing Cr). GL opening is debit-positive O; add actual line debits and subtract credits in listed order to obtain running/closing C. Listed ending debit/credit balances and per-account tuples are independent arithmetic from fixture inputs, never copied from report RPC output. P&L is period revenue minus expense; equity includes current period profit and drawings. All unchanged account movements are zero. V2 tests must assert exact per-account values, not only grand totals.

### GOLD-01 / UAT-01 — Capital contribution

Input/action: record_owner_contribution; additional capital 5000.

Opening fixture: Dr Cash 10000, Cr Capital 10000.

Expected journal lines: Dr Cash 5000; Cr Capital 5000. GL running path: Cash 10000→15000; Capital -10000→-15000.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 5000 | 0 | 15000 | 0 |
| Capital | 0 | 10000 | 0 | 5000 | 0 | 15000 |
| Total | 10000 | 10000 | 5000 | 5000 | 15000 | 15000 |

Expected P&L net profit: 0. Financial position: Assets 15000 = Liabilities 0 + Equity including profit 15000. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-02 / UAT-02 — Cash expense

Input/action: record_expense; rent 600.

Opening fixture: Dr Cash 10000, Cr Capital 10000.

Expected journal lines: Dr Expense 600; Cr Cash 600. GL running path: Expense 0→600; Cash 10000→9400.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 0 | 600 | 9400 | 0 |
| Capital | 0 | 10000 | 0 | 0 | 0 | 10000 |
| Expense | 0 | 0 | 600 | 0 | 600 | 0 |
| Total | 10000 | 10000 | 600 | 600 | 10000 | 10000 |

Expected P&L net profit: -600. Financial position: Assets 9400 = Liabilities 0 + Equity including profit 9400. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-03 / UAT-03 — Cash revenue

Input/action: record_income; revenue 900.

Opening fixture: Dr Cash 10000, Cr Capital 10000.

Expected journal lines: Dr Cash 900; Cr Revenue 900. GL running path: Cash 10000→10900; Revenue 0→-900.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 900 | 0 | 10900 | 0 |
| Capital | 0 | 10000 | 0 | 0 | 0 | 10000 |
| Revenue | 0 | 0 | 0 | 900 | 0 | 900 |
| Total | 10000 | 10000 | 900 | 900 | 10900 | 10900 |

Expected P&L net profit: 900. Financial position: Assets 10900 = Liabilities 0 + Equity including profit 10900. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-04 / UAT-04 — Credit sale

Input/action: V2 sale CUST-A, due Feb 20; 2000.

Opening fixture: Dr Cash 10000, Cr Capital 10000.

Expected journal lines: Dr AR 2000; Cr Revenue 2000. GL running path: AR 0→2000; Revenue 0→-2000.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 0 | 0 | 10000 | 0 |
| Capital | 0 | 10000 | 0 | 0 | 0 | 10000 |
| AR | 0 | 0 | 2000 | 0 | 2000 | 0 |
| Revenue | 0 | 0 | 0 | 2000 | 0 | 2000 |
| Total | 10000 | 10000 | 2000 | 2000 | 12000 | 12000 |

Expected P&L net profit: 2000. Financial position: Assets 12000 = Liabilities 0 + Equity including profit 12000. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-05 / UAT-05 — Customer collection

Input/action: Opening AR CUST-A 2000; collect/allocate 1200, remaining 800.

Opening fixture: Dr Cash 10000, Dr AR 2000, Cr Capital 12000.

Expected journal lines: Dr Cash 1200; Cr AR 1200. GL running path: Cash 10000→11200; AR 2000→800.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 1200 | 0 | 11200 | 0 |
| AR | 2000 | 0 | 0 | 1200 | 800 | 0 |
| Capital | 0 | 12000 | 0 | 0 | 0 | 12000 |
| Total | 12000 | 12000 | 1200 | 1200 | 12000 | 12000 |

Expected P&L net profit: 0. Financial position: Assets 12000 = Liabilities 0 + Equity including profit 12000. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-06 / UAT-06 — Supplier bill

Input/action: V2 bill VEND-A, due Feb 20; expense 1000.

Opening fixture: Dr Cash 10000, Cr Capital 10000.

Expected journal lines: Dr Expense 1000; Cr AP 1000. GL running path: Expense 0→1000; AP 0→-1000.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 0 | 0 | 10000 | 0 |
| Capital | 0 | 10000 | 0 | 0 | 0 | 10000 |
| Expense | 0 | 0 | 1000 | 0 | 1000 | 0 |
| AP | 0 | 0 | 0 | 1000 | 0 | 1000 |
| Total | 10000 | 10000 | 1000 | 1000 | 11000 | 11000 |

Expected P&L net profit: -1000. Financial position: Assets 10000 = Liabilities 1000 + Equity including profit 9000. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-07 / UAT-07 — Supplier payment

Input/action: Opening AP VEND-A 1000; pay/allocate 700, remaining 300.

Opening fixture: Dr Cash 10000, Cr AP 1000, Cr Capital 9000.

Expected journal lines: Dr AP 700; Cr Cash 700. GL running path: AP -1000→-300; Cash 10000→9300.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 0 | 700 | 9300 | 0 |
| AP | 0 | 1000 | 700 | 0 | 0 | 300 |
| Capital | 0 | 9000 | 0 | 0 | 0 | 9000 |
| Total | 10000 | 10000 | 700 | 700 | 9300 | 9300 |

Expected P&L net profit: 0. Financial position: Assets 9300 = Liabilities 300 + Equity including profit 9000. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-08 / UAT-08 — Transfer

Input/action: record_transfer; cash to bank 3000, no fees.

Opening fixture: Dr Cash 10000, Cr Capital 10000.

Expected journal lines: Dr Bank 3000; Cr Cash 3000. GL running path: Bank 0→3000; Cash 10000→7000.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 0 | 3000 | 7000 | 0 |
| Capital | 0 | 10000 | 0 | 0 | 0 | 10000 |
| Bank | 0 | 0 | 3000 | 0 | 3000 | 0 |
| Total | 10000 | 10000 | 3000 | 3000 | 10000 | 10000 |

Expected P&L net profit: 0. Financial position: Assets 10000 = Liabilities 0 + Equity including profit 10000. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-09 / UAT-09 — Asset purchase

Input/action: record_asset_purchase; equipment paid 4000.

Opening fixture: Dr Cash 10000, Cr Capital 10000.

Expected journal lines: Dr Equipment 4000; Cr Cash 4000. GL running path: Equipment 0→4000; Cash 10000→6000.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 0 | 4000 | 6000 | 0 |
| Capital | 0 | 10000 | 0 | 0 | 0 | 10000 |
| Equipment | 0 | 0 | 4000 | 0 | 4000 | 0 |
| Total | 10000 | 10000 | 4000 | 4000 | 10000 | 10000 |

Expected P&L net profit: 0. Financial position: Assets 10000 = Liabilities 0 + Equity including profit 10000. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-10 / UAT-10 — Loan

Input/action: record_liability_created; cash loan 5000.

Opening fixture: Dr Cash 10000, Cr Capital 10000.

Expected journal lines: Dr Cash 5000; Cr Loan 5000. GL running path: Cash 10000→15000; Loan 0→-5000.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 5000 | 0 | 15000 | 0 |
| Capital | 0 | 10000 | 0 | 0 | 0 | 10000 |
| Loan | 0 | 0 | 0 | 5000 | 0 | 5000 |
| Total | 10000 | 10000 | 5000 | 5000 | 15000 | 15000 |

Expected P&L net profit: 0. Financial position: Assets 15000 = Liabilities 5000 + Equity including profit 10000. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-11 / UAT-11 — Owner withdrawal

Input/action: record_owner_withdrawal; 800, not expense.

Opening fixture: Dr Cash 10000, Cr Capital 10000.

Expected journal lines: Dr Drawings 800; Cr Cash 800. GL running path: Drawings 0→800; Cash 10000→9200.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 0 | 800 | 9200 | 0 |
| Capital | 0 | 10000 | 0 | 0 | 0 | 10000 |
| Drawings | 0 | 0 | 800 | 0 | 800 | 0 |
| Total | 10000 | 10000 | 800 | 800 | 10000 | 10000 |

Expected P&L net profit: 0. Financial position: Assets 9200 = Liabilities 0 + Equity including profit 9200. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-12 / UAT-12 — Depreciation

Input/action: Equipment opening 6000, zero residual, 12 equal monthly charges; one month 500.

Opening fixture: Dr Cash 10000, Dr Equipment 6000, Cr Capital 16000.

Expected journal lines: Dr DepExpense 500; Cr AccumDep 500. GL running path: DepExpense 0→500; AccumDep 0→-500.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 0 | 0 | 10000 | 0 |
| Equipment | 6000 | 0 | 0 | 0 | 6000 | 0 |
| Capital | 0 | 16000 | 0 | 0 | 0 | 16000 |
| DepExpense | 0 | 0 | 500 | 0 | 500 | 0 |
| AccumDep | 0 | 0 | 0 | 500 | 0 | 500 |
| Total | 16000 | 16000 | 500 | 500 | 16500 | 16500 |

Expected P&L net profit: -500. Financial position: Assets 15500 = Liabilities 0 + Equity including profit 15500. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-13 / UAT-13 — Opening balance

Input/action: Empty organization; cutoff Feb 1, CUST-A AR and VEND-A AP; explicit OBE 8500.

Opening fixture: none.

Expected journal lines: Dr Cash 8000; Dr AR 2000; Cr AP 1500; Cr OBE 8500. GL running path: Cash 0→8000; AR 0→2000; AP 0→-1500; OBE 0→-8500.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 0 | 0 | 8000 | 0 | 8000 | 0 |
| AR | 0 | 0 | 2000 | 0 | 2000 | 0 |
| AP | 0 | 0 | 0 | 1500 | 0 | 1500 |
| OBE | 0 | 0 | 0 | 8500 | 0 | 8500 |
| Total | 0 | 0 | 10000 | 10000 | 10000 | 10000 |

Expected P&L net profit: 0. Financial position: Assets 10000 = Liabilities 1500 + Equity including profit 8500. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-14 / UAT-14 — Reversal

Input/action: Feb 10 expense 300 then Feb 11 reverse with reason/link; 2 distinct journals.

Opening fixture: Dr Cash 10000, Cr Capital 10000.

Expected journal lines: Dr Expense 300; Cr Cash 300; Dr Cash 300; Cr Expense 300. GL running path: Expense 0→300→0; Cash 10000→9700→10000; original immutable.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 300 | 300 | 10000 | 0 |
| Capital | 0 | 10000 | 0 | 0 | 0 | 10000 |
| Expense | 0 | 0 | 300 | 300 | 0 | 0 |
| Total | 10000 | 10000 | 600 | 600 | 10000 | 10000 |

Expected P&L net profit: 0. Financial position: Assets 10000 = Liabilities 0 + Equity including profit 10000. Verification: NOT VERIFIED; accountant acceptance pending.

### GOLD-15 / UAT-15 — Period locking

Input/action: Lock through Feb 28; non-override actor attempts Dr Expense 100 / Cr Cash 100; reject BOOKS_LOCKED atomically.

Opening fixture: Dr Cash 10000, Cr Capital 10000.

Expected journal lines: none; attempted journal rejected. GL running path: Cash stays 10000; Capital stays -10000; no new entries/quota consumption.

| Account | Opening Dr | Opening Cr | Period Dr | Period Cr | Closing Dr | Closing Cr |
|---|---:|---:|---:|---:|---:|---:|
| Cash | 10000 | 0 | 0 | 0 | 10000 | 0 |
| Capital | 0 | 10000 | 0 | 0 | 0 | 10000 |
| Total | 10000 | 10000 | 0 | 0 | 10000 | 10000 |

Expected P&L net profit: 0. Financial position: Assets 10000 = Liabilities 0 + Equity including profit 10000. Verification: NOT VERIFIED; accountant acceptance pending.

## Required extensions around every golden fixture

- Tenant A/B and viewer/data-entry/accountant roles: deny foreign account/counterparty/import/report/storage references at RPC and direct table boundaries; revoked/expired access cannot mutate; allowed historical reads remain.
- Retry same idempotency key sequentially and concurrently; exactly one journal and one quota unit; different payload same key produces explicit conflict or original-result policy, never ambiguous silent financial change. Concurrent reversal double-click must link at most one authorized reversal.
- Two sessions: final quota slot, post same draft, close versus post, archive/reparent versus post, subscription downgrade versus FX/import/recurring/storage. Inspect final ledger and audit, not only returned error. Existing dblink tests are a foundation.
- Immutability: attempts to insert/update/delete lines or change posted financial fields fail, including privileged supported test paths; no correction by mutation. Group posting denied in every source; control posting reconciles allocation.
- Precision: EGP two decimals, JPY zero, KWD three, negative/zero/overflow input, 0.5-minor FX boundaries and accepted residual limit; no report tolerance concealing imbalance; UI safe-integer limits and CSV round-trip.
- Reports: empty-period openings, inclusive date/timezone boundaries, archived accounts, parent with own historic lines, deep rollups, contra normal-side versus statement signs, subtype/CF historical mapping, cross-year profit/closing, mixed CF journal and cash transfer. Independent fixtures for all exports with injection strings.
- Opening: duplicate rows/batch, invalid account/currency/side, cutover lock and year-start/midyear, OBE reconciliation; no partial unauthorized opening; quota failure rolls back or follows documented batch recovery.
- AR/AP: partial/overpayment/advance/cancellation/reversed allocation and aging at due-date/30/60/90 boundaries; reconcile counterparties to control totals.
- Navigation: account create appears without reload in same tab and dependent selectors; filter/tenant mismatch, slow response and errors captured; report→account→journal→back preserves URL/filter/sort/page/scroll/period in both directions and EN/AR themes.

WP implementing a feature adds focused regression tests there; WP00 only specifies them. Accountant fixture approval and actual executed evidence remain separate fields.

The disposable WP00 stack was stopped and its task-created data volumes removed after verification. Existing developer stacks were left running. No remote email or payment was sent; OTP exercises used the isolated local Mailpit inbox.
