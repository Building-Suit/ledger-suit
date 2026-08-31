# Environment variables

Copy `.env.example` to `.env` and fill it in. `.env` is gitignored; only
`.env.example` is committed, and it must never contain a real secret.

## Application

| Variable | Required | Where it runs | Notes |
|---|---|---|---|
| `SUPABASE_URL` | yes | client + server | Project API URL. Local: `http://127.0.0.1:54321` |
| `SUPABASE_KEY` | yes | client + server | Publishable (anon) key. Safe in the browser — every table it can reach is behind RLS |
| `SUPABASE_SERVICE_KEY` | no | **server only** | Bypasses RLS entirely. Never import it into anything the bundler can reach |
| `APP_BASE_URL` | yes in deployed environments | build/server | Public application origin used for locale metadata and future invitation links |

`@nuxtjs/supabase` reads `SUPABASE_URL` and `SUPABASE_KEY` by convention.

### About the service role key

It bypasses row level security completely. Rules:

- server-side only — Nitro server routes, edge functions, background jobs
- never referenced from `app/`
- never logged, never committed, never sent to an analytics or error tracker
- rotate it if it is ever printed anywhere

Phases 1–3 need no server-side privileged access, so leave it unset until a
background job or webhook handler actually requires it.

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

## Not yet required

These are named here so the shape is agreed before the code lands:

| Variable | Phase | Purpose |
|---|---|---|
| `BILLING_PROVIDER` | 4 | Which adapter to load (`stripe`, `paymob`, …) |
| `BILLING_WEBHOOK_SECRET` | 4 | Webhook signature verification |
