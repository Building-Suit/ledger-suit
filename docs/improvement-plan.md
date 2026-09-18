# Post-launch improvement program

> **Historical record — not an active plan or current acceptance evidence.** Retained for provenance as of the WP00 audit on 2026-09-18. The canonical [launch master](launch/MASTER_LAUNCH_PLAN.md), [current status](launch/CURRENT_STATUS.md), [consolidated roadmap](launch/ROADMAP.md) and [Accounting V2 plan](accounting-v2/MASTER_PLAN.md) govern current work. Original task ordering, decisions and source text below are preserved; old completion claims and checkboxes do not establish current deployment, UAT or release readiness.

## Purpose

This program improves Ledger Suit's UI foundations and core workflows without weakening tenant isolation, server-authoritative permissions and quotas, accounting immutability, billing security, or existing launch behavior. PrimeVue is the behavioral and accessibility component foundation; Building Suit tokens, Tailwind classes, themes, typography, responsive behavior, and EN/AR direction remain the visual authority.

## Workflow

- Complete the steps in order, with one fresh branch and one pull request per step, always based on the latest merged `origin/dev`. Do not stack steps or commit directly to `dev` or `main`.
- Keep each change to the smallest complete implementation, add focused tests, and run focused local validation.
- ChatGPT independently reviews each pull request and exact-head CI before the next step begins. Codex does not merge or continue automatically.
- GitHub Actions owns the full regression matrix. Database changes are forward-only and generated database types must be committed exactly when contracts change.
- Preserve direct Supabase access where established and use Edge Functions only for justified secret or external-provider boundaries.

## Ordered steps

1. **PrimeVue + Nuxt UI foundation** — Install the official module in unstyled mode, retain SSR, hydration, themes, and RTL, and establish the shared component approach without broad migration.
2. **PrimeVue DataTable foundation + core tables** — Establish the common table pattern and convert Accounts, Transactions, and primary record lists.
3. **All remaining user-facing tables** — Complete customer-visible DataTable conversion while preserving permissions, actions, localization, and financial formatting.
4. **PrimeVue form system + floating-label foundation** — Create the shared field architecture and consistent validation, state, keyboard, and RTL behavior.
5. **Floating-label and form audit** — Migrate remaining applicable interactive fields without forcing floating labels where they are not meaningful.
6. **Reports ledger refresh** — Fix `/reports` ledger loading across navigation, refresh, tenant, locale, and filter changes.
7. **Attachment upload pipeline** — Use PrimeVue FileUpload and restore reliable, secure, quota-aware upload behavior.
8. **Controlled account subtype** — Make subtype selectable by account type and validate combinations server-side without destructive remapping.
9. **Create/edit field parity** — Share field definitions and represent all legally editable create fields in edit flows, explaining immutable fields.
10. **Tags + attachments during creation** — Add inline tags and safely staged attachments to applicable create flows.
11. **Downloadable CSV import template** — Generate an obvious template from the accepted import contract and validate the end-to-end CSV workflow.
12. **Organization + profile settings** — Expose actual onboarding data in separate PrimeVue settings, with email read-only and authoritative validation and auditing.
13. **Dashboard usage meters + localized quota UX** — Present the seven authoritative launch quotas and map quota errors to clear EN/AR messages.
14. **How It Works modal** — Fix the Categories CTA and align every card's content and action in a PrimeVue Dialog.
15. **Advanced roles & permissions** — Build page/action-oriented UX on the existing capability architecture and audit significant routes and actions.
16. **Role-aware notifications** — Extend the existing notification system with capability-aware recipients, localized content, deep links, read state, and tenant safety.
17. **English + Arabic language rewrite** — Apply reviewer-provided locale content without changing keys, nesting, interpolation, or pluralization contracts.
18. **Admin Panel + pricing/yearly discount/offers engine** — As the **final step**, add the server-authoritative platform-admin boundary, preserve and administer the current 32% yearly policy, implement safe promotional offers and auditable price resolution, verify Paymob mappings and signed snapshots, and build the PrimeVue admin UI. Do not start `/admin`, pricing infrastructure, or offer tables earlier.

PrimeVue DataTables begin in Step 2, form migration begins in Step 4, and the Admin Panel and all pricing/offer infrastructure remain exclusively Step 18.
