-- Ledger Suit — 19. Subscriptions and entitlements
--
-- Billing is modelled at the organization level and is deliberately free of any
-- payment-vendor specifics: a provider is just a string plus an opaque id. The
-- accounting domain never imports a billing SDK.
--
-- Entitlements are evaluated in one place — public.can_use_feature() and
-- public.get_limit() — so no component ever hard-codes plan logic.

create type public.billing_interval as enum ('monthly', 'yearly');

create type public.billing_status as enum (
  'trialing',
  'active',
  'past_due',
  'grace_period',
  'suspended',
  'cancelled'
);

create table if not exists public.subscription_plans (
  id          uuid primary key default gen_random_uuid(),
  key         text not null unique,
  name        text not null,
  description text,
  is_public   boolean not null default true,
  is_active   boolean not null default true,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint subscription_plans_key_format check (key ~ '^[a-z][a-z0-9_]{1,40}$')
);

alter table public.subscription_plans enable row level security;

create trigger subscription_plans_set_updated_at
  before update on public.subscription_plans
  for each row execute function app.set_updated_at();

create table if not exists public.subscription_plan_prices (
  id                uuid primary key default gen_random_uuid(),
  plan_id           uuid not null references public.subscription_plans (id) on delete cascade,
  interval          public.billing_interval not null,
  currency_code     char(3) not null references public.currencies (code),
  amount_minor      bigint not null,
  provider          text,
  provider_price_id text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),

  constraint subscription_plan_prices_amount_non_negative check (amount_minor >= 0)
);

create unique index if not exists subscription_plan_prices_unique
  on public.subscription_plan_prices (plan_id, interval, currency_code)
  where is_active;
create unique index if not exists subscription_plan_prices_provider_key
  on public.subscription_plan_prices (provider, provider_price_id)
  where provider_price_id is not null;

alter table public.subscription_plan_prices enable row level security;

-- ---------------------------------------------------------------------------
-- What a plan grants
-- ---------------------------------------------------------------------------
create table if not exists public.subscription_entitlements (
  plan_id      uuid not null references public.subscription_plans (id) on delete cascade,
  feature_key  text not null,
  is_enabled   boolean not null default true,
  -- NULL means "no limit". 0 means "not allowed at all".
  limit_value  bigint,
  primary key (plan_id, feature_key),

  constraint subscription_entitlements_limit_non_negative check (
    limit_value is null or limit_value >= 0
  )
);

comment on column public.subscription_entitlements.limit_value is
  'NULL = unlimited. 0 = feature present but quota exhausted by definition.';

alter table public.subscription_entitlements enable row level security;

-- ---------------------------------------------------------------------------
-- Provider customer mapping
-- ---------------------------------------------------------------------------
create table if not exists public.subscription_customers (
  id                   uuid primary key default gen_random_uuid(),
  organization_id      uuid not null references public.organizations (id) on delete cascade,
  provider             text not null,
  provider_customer_id text not null,
  billing_email        extensions.citext,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint subscription_customers_unique unique (organization_id, provider)
);

create unique index if not exists subscription_customers_provider_key
  on public.subscription_customers (provider, provider_customer_id);

create trigger subscription_customers_set_updated_at
  before update on public.subscription_customers
  for each row execute function app.set_updated_at();

alter table public.subscription_customers enable row level security;

-- ---------------------------------------------------------------------------
-- The subscription itself
-- ---------------------------------------------------------------------------
create table if not exists public.subscriptions (
  id                       uuid primary key default gen_random_uuid(),
  organization_id          uuid not null unique
                             references public.organizations (id) on delete cascade,
  plan_id                  uuid not null references public.subscription_plans (id),
  price_id                 uuid references public.subscription_plan_prices (id),
  status                   public.billing_status not null default 'trialing',
  provider                 text,
  provider_subscription_id text,
  trial_started_at         timestamptz,
  trial_ends_at            timestamptz,
  current_period_start     timestamptz,
  current_period_end       timestamptz,
  grace_period_ends_at     timestamptz,
  cancel_at_period_end     boolean not null default false,
  cancelled_at             timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

comment on table public.subscriptions is
  'One subscription per organization. Backend state is authoritative; the '
  'frontend never decides entitlement.';

create unique index if not exists subscriptions_provider_key
  on public.subscriptions (provider, provider_subscription_id)
  where provider_subscription_id is not null;
create index if not exists subscriptions_status_idx on public.subscriptions (status);
create index if not exists subscriptions_plan_idx on public.subscriptions (plan_id);
create index if not exists subscriptions_price_idx on public.subscriptions (price_id);

create trigger subscriptions_set_updated_at
  before update on public.subscriptions
  for each row execute function app.set_updated_at();

alter table public.subscriptions enable row level security;

-- ---------------------------------------------------------------------------
-- Webhook ledger — idempotent by construction
-- ---------------------------------------------------------------------------
create table if not exists public.billing_events (
  id                uuid primary key default gen_random_uuid(),
  provider          text not null,
  provider_event_id text not null,
  event_type        text not null,
  organization_id   uuid references public.organizations (id) on delete set null,
  payload           jsonb not null,
  signature_verified boolean not null default false,
  processed_at      timestamptz,
  processing_error  text,
  received_at       timestamptz not null default now(),

  -- A replayed webhook cannot be recorded twice, so downstream handling is
  -- idempotent even if the provider retries indefinitely.
  constraint billing_events_provider_event_unique unique (provider, provider_event_id)
);

comment on table public.billing_events is
  'Append-only webhook log. Uniqueness on (provider, provider_event_id) is what '
  'makes webhook processing idempotent.';

create index if not exists billing_events_unprocessed_idx
  on public.billing_events (received_at) where processed_at is null;
create index if not exists billing_events_org_idx
  on public.billing_events (organization_id, received_at desc);

alter table public.billing_events enable row level security;

revoke insert, update, delete on public.billing_events from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Seed plans
-- ---------------------------------------------------------------------------
insert into public.subscription_plans (key, name, description, sort_order) values
  ('free',     'Free',     'For trying Ledger Suit out. One organization, limited volume.', 0),
  ('starter',  'Starter',  'For a small business keeping its own books.', 1),
  ('business', 'Business', 'For teams that need multi-currency, imports and an audit trail.', 2)
on conflict (key) do nothing;

insert into public.subscription_plan_prices (plan_id, interval, currency_code, amount_minor)
select p.id, i.interval, 'EGP', i.amount
from public.subscription_plans p
join (values
  ('free',     'monthly'::public.billing_interval, 0::bigint),
  ('free',     'yearly'::public.billing_interval,  0::bigint),
  ('starter',  'monthly'::public.billing_interval, 49900::bigint),
  ('starter',  'yearly'::public.billing_interval,  499000::bigint),
  ('business', 'monthly'::public.billing_interval, 149900::bigint),
  ('business', 'yearly'::public.billing_interval,  1499000::bigint)
) as i(plan_key, interval, amount) on i.plan_key = p.key
on conflict do nothing;

insert into public.subscription_entitlements (plan_id, feature_key, is_enabled, limit_value)
select p.id, e.feature_key, e.is_enabled, e.limit_value
from public.subscription_plans p
join (values
  ('free',     'max_members',                true,  2::bigint),
  ('free',     'max_monthly_transactions',   true,  200::bigint),
  ('free',     'max_storage_bytes',          true,  104857600::bigint),
  ('free',     'max_recurring_rules',        true,  0::bigint),
  ('free',     'multi_currency',             false, null::bigint),
  ('free',     'advanced_reports',           false, null::bigint),
  ('free',     'imports',                    false, null::bigint),
  ('free',     'exports',                    true,  null::bigint),
  ('free',     'audit_log_retention_days',   true,  30::bigint),
  ('free',     'api_access',                 false, null::bigint),

  ('starter',  'max_members',                true,  5::bigint),
  ('starter',  'max_monthly_transactions',   true,  2000::bigint),
  ('starter',  'max_storage_bytes',          true,  5368709120::bigint),
  ('starter',  'max_recurring_rules',        true,  25::bigint),
  ('starter',  'multi_currency',             true,  null::bigint),
  ('starter',  'advanced_reports',           true,  null::bigint),
  ('starter',  'imports',                    true,  null::bigint),
  ('starter',  'exports',                    true,  null::bigint),
  ('starter',  'audit_log_retention_days',   true,  365::bigint),
  ('starter',  'api_access',                 false, null::bigint),

  ('business', 'max_members',                true,  25::bigint),
  ('business', 'max_monthly_transactions',   true,  null::bigint),
  ('business', 'max_storage_bytes',          true,  53687091200::bigint),
  ('business', 'max_recurring_rules',        true,  null::bigint),
  ('business', 'multi_currency',             true,  null::bigint),
  ('business', 'advanced_reports',           true,  null::bigint),
  ('business', 'imports',                    true,  null::bigint),
  ('business', 'exports',                    true,  null::bigint),
  ('business', 'audit_log_retention_days',   true,  2555::bigint),
  ('business', 'api_access',                 true,  null::bigint)
) as e(plan_key, feature_key, is_enabled, limit_value) on e.plan_key = p.key
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Every new organization starts on the free plan, in trial
-- ---------------------------------------------------------------------------
create or replace function app.start_default_subscription()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan uuid;
begin
  select id into v_plan from public.subscription_plans where key = 'free';

  if v_plan is not null then
    insert into public.subscriptions (
      organization_id, plan_id, status, trial_started_at, trial_ends_at
    )
    values (new.id, v_plan, 'trialing', now(), now() + interval '14 days')
    on conflict (organization_id) do nothing;
  end if;

  return new;
end;
$$;

create trigger organizations_start_subscription
  after insert on public.organizations
  for each row execute function app.start_default_subscription();

-- ---------------------------------------------------------------------------
-- Centralised entitlement evaluation
-- ---------------------------------------------------------------------------
create or replace function public.can_use_feature(
  p_organization_id uuid,
  p_feature_key     text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not app.is_org_member(p_organization_id) then false
    else coalesce(
      (
        select e.is_enabled and coalesce(e.limit_value, 1) <> 0
        from public.subscriptions s
        join public.subscription_entitlements e on e.plan_id = s.plan_id
        where s.organization_id = p_organization_id
          and e.feature_key = p_feature_key
          -- A suspended or cancelled subscription keeps the data readable but
          -- switches features off.
          and s.status in ('trialing', 'active', 'past_due', 'grace_period')
      ),
      false
    )
  end;
$$;

create or replace function public.get_limit(
  p_organization_id uuid,
  p_limit_key       text
)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not app.is_org_member(p_organization_id) then 0::bigint
    else (
      select e.limit_value
      from public.subscriptions s
      join public.subscription_entitlements e on e.plan_id = s.plan_id
      where s.organization_id = p_organization_id
        and e.feature_key = p_limit_key
    )
  end;
$$;

comment on function public.get_limit(uuid, text) is
  'Returns NULL for "unlimited" and 0 for "not permitted". Callers must treat '
  'NULL as unlimited rather than as zero.';

grant execute on function public.can_use_feature(uuid, text) to authenticated, service_role;
grant execute on function public.get_limit(uuid, text) to authenticated, service_role;
