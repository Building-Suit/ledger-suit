# UI-02A — Accounts table review evidence

2026-09-18. **READY FOR REVIEW**, Accounts slice only. DEC-010 authorizes this presentation work before WP01; UI-02 Transactions/records remain outstanding. No Accounting V2, deployment or accountant acceptance is implied.

## Reproduce

Install with the existing lockfile, start a **new disposable** local Supabase project on unused ports, then run the app with its URL/publishable key. Never reset an existing developer or remote database for this review. Run:

```sh
PLAYWRIGHT_PORT=3310 SUPABASE_URL=http://127.0.0.1:58321 MAILPIT_URL=http://127.0.0.1:58324 pnpm exec playwright test tests/e2e/accounts-table.spec.ts tests/e2e/core-finance.spec.ts
```

The UI tests use the repository's fake `owner@alpha.test` / `viewer@alpha.test` identities. Request fixtures cover a 1,003-account chart and delayed tenant responses. The create/edit/archive and selector refresh scenario uses real existing RPCs on the disposable database. No service-role browser access or production writes. The delayed-response fixture tests client isolation; it does not replace database RLS tests.

## Before and after

Baseline: WP00 product code, unchanged by merged PR #94 (`6fb152e`). Both pages used the same disposable Alpha Trading chart: four active EGP assets, one archived asset, and one account in each other type. No posted transactions; displayed balances are intentionally zero. Assets tab, archived off, search empty, ascending code order. Desktop 1440×1000; mobile 390×844. Before and after pairs use the same locale, theme and data. Synthetic browser-test rows are separate from these screenshots.

| View | Before | After |
|---|---|---|
| English / light / desktop | [Before](before-en-light-desktop.png) | [After](after-en-light-desktop.png) |
| English / dark / desktop | [Before](before-en-dark-desktop.png) | [After](after-en-dark-desktop.png) |
| Arabic / light / desktop | [Before](before-ar-light-desktop.png) | [After](after-ar-light-desktop.png) |
| Arabic / dark / desktop | [Before](before-ar-dark-desktop.png) | [After](after-ar-dark-desktop.png) |
| English / light / mobile | [Before](before-en-light-mobile.png) | [After](after-en-light-mobile.png) |
| English / dark / mobile | [Before](before-en-dark-mobile.png) | [After](after-en-dark-mobile.png) |
| Arabic / light / mobile | [Before](before-ar-light-mobile.png) | [After](after-ar-light-mobile.png) |
| Arabic / dark / mobile | [Before](before-ar-dark-mobile.png) | [After](after-ar-dark-mobile.png) |

Observed: old page overflowed the viewport at 390px in both locales/themes. New page stays within it; the five-tab strip and table scroll internally. Code/account headers support keyboard sorting with `aria-sort`, a visible focus ring and localized text. Subtypes are translated without changing stored enum values. Balances remain in organization base currency, as defined by `account_balances` (not the account's original currency).

## Interaction demo

1. [Search by code](demo-search-code.png): `1020` returns the operating bank; the group total is unchanged.
2. [Sort by name descending](demo-sort-name.png): uses PrimeVue sorting on the entire filtered dataset before slicing display pages.
3. [Save while hidden by a deliberate search](demo-saved-hidden.png): search `1020` stays in place; a localized action offers to show the new account.
4. [Reveal the new account](demo-created-visible.png): explicit action switches to its type and searches its name. No document reload. The demo account was archived afterwards in the disposable database.

For charts above 25 matching rows, previous/next controls page the **display**, while the count/search/sort cover the complete loaded chart. Saving in a larger list also offers the explicit reveal action, so the user can find a record on another display page.

## Query and accounting audit

- Existing API `max_rows` is 1,000; plan tiers do not prove all supported charts are smaller. Both Accounts balances and shared account selectors now fetch deterministic 500-row ranges ordered by code then unique ID. Exact counts support lower server caps; cancellation and organization snapshots discard stale responses. A failed later page displays an error/retry, never a partial chart or partial group total.
- Existing `create_account`, `update_account`, `archive_account` contracts are unchanged. Existing `org:account-balances` and `org:accounts` invalidation was retained. Baseline create-and-visible regression passed **before** this change, so no missing-invalidation bug is claimed.
- The reporting view sums **posted base_amount_minor**. MoneyText and existing group-total/parent-exclusion arithmetic are retained verbatim. Search does not feed the aggregate. RISK-003 (parent postings vs parent exclusion) and precision/archived-history risks remain open.
- No migrations, seed edits, generated types, dependencies, pricing, payment, quota, legal or reporting-policy changes. No remote SQL, deployment or merge.

## Verification

Local runtime: Node 26.8.1 / pnpm 10.33.0; CI uses Node 22 / pnpm 11.5.0. Isolated project `ledger-ui02a-disposable-20260918`, API 58321, DB 58322, mail 58324. Existing Ledger Suit and Shop Suit developer containers were not reset or stopped.

- Frozen-lockfile install, lint, typecheck and production build: PASS. Build without supplied runtime env emits the existing missing-Supabase-config warnings.
- Accounts tests + existing core finance navigation/workflows: **18/18 PASS**. The >1,000 test additionally checks shared-selector pagination; focused extension rerun: **1/1 PASS**.
- Unmodified baseline create-and-visible test: **1/1 PASS**.
- Screenshots: eight before/after pairs, plus four real interaction captures. Desktop/mobile, EN/AR, light/dark inspected. Keyboard sorting/focus and viewport containment also covered by automated browser tests.
- Full local Chromium E2E: **56/56 PASS**. PR CI results are recorded in [CURRENT_STATUS](../../launch/CURRENT_STATUS.md). PR CI runs the existing full application and database/Edge/E2E matrix. No test timeout was raised, test skipped, or RISK-014 closed to obtain a passing result.

Limits: browser Chromium only; no real accountant UAT, production parity or atomic cross-request snapshot under concurrent chart edits is claimed. Range reads use the existing API contracts; a concurrent edit may require refreshing. No new snapshot RPC is introduced by this presentation slice. All launch gates and WP01 decisions retain their prior pending states.
