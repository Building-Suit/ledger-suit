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

### Signup OTP and Auth email delivery

The guided signup requires email confirmation. Supabase sends a six-digit code,
the in-app verification screen exchanges it for an authenticated session, and
only then can the workspace RPC run. The committed local
configuration uses:

- `enable_confirmations = true`
- six-digit OTPs with a 60-minute expiry
- a 60-second resend interval
- `supabase/templates/confirmation.html` as the branded code template

Hosted Auth settings and email templates are external provider configuration;
database migrations do not alter them. In the hosted project:

1. Keep **Confirm email** enabled under Authentication → Sign In / Providers →
   Email.
2. Set the Confirm signup subject to
   `{{ .Token }} is your Ledger Suit verification code`.
3. Copy the committed confirmation template into the hosted Confirm signup
   template so the message exposes `{{ .Token }}` rather than only a link.
4. Configure Supabase Auth custom SMTP with Resend (`smtp.resend.com`, port
   `465`, username `resend`, and the Resend API key as the password). Use
   `noreply@building-suit.com` as the Auth sender; operational notifications
   continue to use `notification@building-suit.com`.

The app never stores the signup password in session storage. It preserves only
the pending business form and countdown timestamps so an accidental refresh can
return to OTP verification.

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
| `PAYMOB_BASE_URL` | Regional Paymob API origin; Egypt defaults to `https://accept.paymob.com` |
| `PAYMOB_SECRET_KEY` | Server-side secret key used to create payment Intentions |
| `PAYMOB_PUBLIC_KEY` | Public key included in the Unified Checkout URL |
| `PAYMOB_HMAC_SECRET` | Verifies Paymob transaction callbacks with HMAC-SHA512 |
| `PAYMOB_CARD_INTEGRATION_ID` | Test-mode online 3DS/VPC integration (`5902990` for the current Paymob account) used for the first subscription transaction |
| `PAYMOB_MONTHLY_PLAN_ID` | Paymob subscription plan configured for 30-day deductions |
| `PAYMOB_YEARLY_PLAN_ID` | Paymob subscription plan configured for 360-day deductions |
| `PAYMOB_MONTHLY_AMOUNT_CENTS` | Monthly charge in the currency's smallest unit (`60000` for EGP 600) |
| `PAYMOB_YEARLY_AMOUNT_CENTS` | Yearly charge in the currency's smallest unit (`480000` for EGP 4,800) |
| `RESEND_API_KEY` | Sends invitation and operational notification emails |
| `RESEND_FROM_EMAIL` | Verified sender: `notification@building-suit.com` |
| `APP_BASE_URL` | Checkout return URL and email-link origin |

Secret and public keys are mode-specific. Copy the Test values while the app is
in Paymob Test mode, and replace them together with the Integration ID when
moving to Live mode. The Egypt API origin is the same in both modes.

Two additional values are used only while provisioning plans from a trusted
developer machine; the deployed Edge Functions do not read them:

| Variable | Purpose |
|---|---|
| `PAYMOB_API_KEY` | Generates the temporary Bearer token used by Paymob's subscription-plan API; Paymob uses the same API key in Test and Live modes |
| `PAYMOB_MOTO_INTEGRATION_ID` | MIGS MOTO integration used by Paymob for automatic, customer-not-present renewal deductions |

Do not substitute the online card Integration ID for the MOTO Integration ID.
The online ID handles the customer's initial 3DS checkout; MOTO handles later
automatic deductions.

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are supplied
to deployed Supabase Edge Functions by the platform. The service role key is
used only by the verified Paymob webhook and scheduled email worker.

The Paymob account needs two subscription plans with `use_transaction_amount`
enabled: EGP 600 every 30 days and EGP 4,800 every 360 days. The amount secrets
must match those plans. The UI displays the configured product amounts and
Unified Checkout confirms them before payment.

Once Paymob enables MOTO, put `PAYMOB_API_KEY`,
`PAYMOB_MOTO_INTEGRATION_ID`, and the two amount variables in the ignored local
`.env`, then provision or safely reuse the plans:

```bash
pnpm paymob:provision-plans -- \
  --webhook-url=https://<project-ref>.supabase.co/functions/v1/paymob-webhook
```

The command refuses to duplicate a named plan whose settings differ and prints
the resulting `PAYMOB_MONTHLY_PLAN_ID` and `PAYMOB_YEARLY_PLAN_ID`. Add those
two IDs to Supabase Edge Function Secrets. `PAYMOB_API_KEY` and
`PAYMOB_MOTO_INTEGRATION_ID` do not need to remain in the deployed runtime.

The plans are shared, but each organization creates a distinct Paymob
subscription. The organization UUID and billing interval are copied into the
Intention extras and unique reference so the signed callback activates exactly
one workspace.

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
