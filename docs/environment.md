# Environment variables

Copy `.env.example` to `.env` and fill it in. `.env` is gitignored; only
`.env.example` is committed, and it must never contain a real secret.

## Application

| Variable | Required | Where it runs | Notes |
|---|---|---|---|
| `SUPABASE_URL` | yes | client + server | Project API URL. Local: `http://127.0.0.1:54321` |
| `SUPABASE_KEY` | yes | client + server | Publishable (anon) key. Safe in the browser — every table it can reach is behind RLS |
| `SUPABASE_SERVICE_KEY` | no | **server only** | Optional Nuxt server key. Never import it into anything the bundler can reach |
| `APP_BASE_URL` | yes in deployed environments | build/server + Edge Functions | Public HTTPS application origin used for checkout returns and invitation links |

`@nuxtjs/supabase` reads `SUPABASE_URL` and `SUPABASE_KEY` by convention.

### About the service role key

It bypasses row level security completely. Rules:

- server-side only — Nitro server routes, edge functions, background jobs
- never referenced from `app/`
- never logged, never committed, never sent to an analytics or error tracker
- rotate it if it is ever printed anywhere

## Phase 4 Edge Function secrets

Configure these in Supabase's Edge Function secret store. They are server-only
and must never be prefixed with `NUXT_PUBLIC_` or exposed to browser code.

| Variable | Purpose |
|---|---|
| `STRIPE_SECRET_KEY` | Stripe server API authentication |
| `STRIPE_WEBHOOK_SECRET` | Verifies the raw Stripe webhook body |
| `STRIPE_MONTHLY_PRICE_ID` | Monthly price for the one Ledger Suit product |
| `STRIPE_YEARLY_PRICE_ID` | Yearly price for the same product |
| `RESEND_API_KEY` | Sends invitation and operational notification emails |
| `RESEND_FROM_EMAIL` | Verified sender, for example `Ledger Suit <billing@example.com>` |
| `APP_BASE_URL` | Checkout/portal return URL and email-link origin |

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are supplied
to deployed Supabase Edge Functions by the platform. The service role key is
used only by the verified Stripe webhook and scheduled email worker.

The actual subscription amount and currency live in Stripe Price objects. The
application deliberately does not duplicate or guess them; Checkout displays
the authoritative amount before confirmation.

## Supabase Vault scheduler secrets

The email Cron job reads two values from Supabase Vault:

- `ledger_suit_project_url` — the Supabase project URL, without a trailing slash
- `ledger_suit_service_role_key` — the server-only service role key

These are deployment secrets, not schema objects. The migration creates the
Cron job itself; until both secrets exist, its query safely performs no HTTP
request.

## Local development

`supabase start` prints the local URL and keys. The values already in
`.env.example` are the Supabase CLI's fixed local development keys — they are
public knowledge and only work against a local stack.

Docker must be running. The local stack also provides:

| Service | URL |
|---|---|
| Studio | http://127.0.0.1:54323 |
| Postgres | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |
| Mailpit (test inbox) | http://127.0.0.1:54324 |
