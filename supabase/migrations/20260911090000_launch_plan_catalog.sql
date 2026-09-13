-- Ledger Suit launch catalog: Solo, Starter, Business, and Scale preview.
--
-- This migration is deliberately dormant. Existing subscriptions remain on
-- their current plan, organization creation still starts the legacy
-- `ledger_suit` trial, and Paymob checkout/webhooks still use that legacy plan
-- until the later plan-aware checkout step.

alter table public.subscription_plans
  add column is_purchasable boolean not null default false;

alter table public.subscription_plans
  add constraint subscription_plans_purchasable_requires_public_active
  check (not is_purchasable or (is_public and is_active));

comment on column public.subscription_plans.is_purchasable is
  'Server-authoritative checkout eligibility. Public preview plans may be active without being purchasable.';

-- The original seed used these keys before the single paid product was
-- introduced. Preserve their rows, entitlements, prices, and any unexpected
-- historical references under explicit legacy keys instead of mutating them
-- into the launch products.
update public.subscription_plans
set key = 'legacy_' || key,
    name = 'Legacy ' || name,
    is_public = false,
    is_active = false,
    is_purchasable = false
where key in ('free', 'starter', 'business');

-- Current trials and paid subscriptions stay on this private plan. It must
-- remain active while referenced, but it is not a valid new checkout choice.
update public.subscription_plans
set is_public = false,
    is_active = true,
    is_purchasable = false
where key = 'ledger_suit';

insert into public.subscription_plans (
  key, name, description, is_public, is_active, is_purchasable, sort_order
) values
  (
    'solo', 'Solo', 'For owner-managed businesses that need reliable core accounting.',
    true, true, true, 10
  ),
  (
    'starter', 'Starter', 'For small teams that need more capacity and CSV imports.',
    true, true, true, 20
  ),
  (
    'business', 'Business', 'For growing teams that need higher limits and multi-currency.',
    true, true, true, 30
  ),
  (
    'scale', 'Scale', 'For high-volume and multi-location businesses. Coming Soon.',
    true, true, false, 40
  )
on conflict (key) do update
set name = excluded.name,
    description = excluded.description,
    is_public = excluded.is_public,
    is_active = excluded.is_active,
    is_purchasable = excluded.is_purchasable,
    sort_order = excluded.sort_order;

-- Annual prices are monthly × 12 less 32%, stored in EGP minor units.
insert into public.subscription_plan_prices (
  plan_id, interval, currency_code, amount_minor, provider,
  provider_price_id, is_active
)
select p.id, price.interval, 'EGP', price.amount_minor, null, null, true
from public.subscription_plans p
join (values
  ('solo',     'monthly'::public.billing_interval,  39900::bigint),
  ('solo',     'yearly'::public.billing_interval,  325584::bigint),
  ('starter',  'monthly'::public.billing_interval,  59900::bigint),
  ('starter',  'yearly'::public.billing_interval,  488784::bigint),
  ('business', 'monthly'::public.billing_interval, 109900::bigint),
  ('business', 'yearly'::public.billing_interval,  896784::bigint)
) as price(plan_key, interval, amount_minor) on price.plan_key = p.key
on conflict (plan_id, interval, currency_code) where is_active do update
set amount_minor = excluded.amount_minor,
    provider = null,
    provider_price_id = null;

insert into public.subscription_entitlements (
  plan_id, feature_key, is_enabled, limit_value
)
select p.id, entitlement.feature_key, entitlement.is_enabled,
       entitlement.limit_value
from public.subscription_plans p
join (values
  ('solo', 'max_members', true, 1::bigint),
  ('solo', 'max_monthly_transactions', true, 500::bigint),
  ('solo', 'max_storage_bytes', true, 1073741824::bigint),
  ('solo', 'max_accounts', true, 30::bigint),
  ('solo', 'max_counterparties', true, 100::bigint),
  ('solo', 'max_recurring_rules', true, 5::bigint),
  ('solo', 'max_custom_roles', true, 0::bigint),
  ('solo', 'audit_log_retention_days', true, 90::bigint),
  ('solo', 'multi_currency', false, null::bigint),
  ('solo', 'imports', false, null::bigint),
  ('solo', 'exports', true, null::bigint),
  ('solo', 'core_reports', true, null::bigint),
  ('solo', 'priority_support', false, null::bigint),
  ('solo', 'branches', false, null::bigint),
  ('solo', 'advanced_analytics', false, null::bigint),
  ('solo', 'api_access', false, null::bigint),
  ('solo', 'max_owned_organizations', true, 1::bigint),

  ('starter', 'max_members', true, 3::bigint),
  ('starter', 'max_monthly_transactions', true, 2500::bigint),
  ('starter', 'max_storage_bytes', true, 5368709120::bigint),
  ('starter', 'max_accounts', true, 100::bigint),
  ('starter', 'max_counterparties', true, 1000::bigint),
  ('starter', 'max_recurring_rules', true, 25::bigint),
  ('starter', 'max_custom_roles', true, 3::bigint),
  ('starter', 'audit_log_retention_days', true, 365::bigint),
  ('starter', 'multi_currency', false, null::bigint),
  ('starter', 'imports', true, null::bigint),
  ('starter', 'exports', true, null::bigint),
  ('starter', 'core_reports', true, null::bigint),
  ('starter', 'priority_support', false, null::bigint),
  ('starter', 'branches', false, null::bigint),
  ('starter', 'advanced_analytics', false, null::bigint),
  ('starter', 'api_access', false, null::bigint),
  ('starter', 'max_owned_organizations', true, 1::bigint),

  ('business', 'max_members', true, 10::bigint),
  ('business', 'max_monthly_transactions', true, 10000::bigint),
  ('business', 'max_storage_bytes', true, 21474836480::bigint),
  ('business', 'max_accounts', true, 300::bigint),
  ('business', 'max_counterparties', true, 5000::bigint),
  ('business', 'max_recurring_rules', true, 100::bigint),
  ('business', 'max_custom_roles', true, 10::bigint),
  ('business', 'audit_log_retention_days', true, 1095::bigint),
  ('business', 'multi_currency', true, null::bigint),
  ('business', 'imports', true, null::bigint),
  ('business', 'exports', true, null::bigint),
  ('business', 'core_reports', true, null::bigint),
  ('business', 'priority_support', true, null::bigint),
  ('business', 'branches', false, null::bigint),
  ('business', 'advanced_analytics', false, null::bigint),
  ('business', 'api_access', false, null::bigint),
  ('business', 'max_owned_organizations', true, 1::bigint)
) as entitlement(plan_key, feature_key, is_enabled, limit_value)
  on entitlement.plan_key = p.key
on conflict (plan_id, feature_key) do update
set is_enabled = excluded.is_enabled,
    limit_value = excluded.limit_value;

-- Resolve only commercial launch plans. This private helper is the boundary
-- that plan-aware checkout will call in a later step; neither a preview plan
-- nor a private legacy plan can resolve successfully.
create or replace function app.resolve_purchasable_plan(
  p_plan_key text,
  p_interval public.billing_interval,
  p_currency_code char(3) default 'EGP'
)
returns table (
  plan_id uuid,
  price_id uuid,
  amount_minor bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.subscription_plans p
    where p.key = p_plan_key
      and p.is_active
      and p.is_public
      and p.is_purchasable
  ) then
    raise exception 'PLAN_NOT_AVAILABLE' using errcode = '22023';
  end if;

  return query
  select p.id, price.id, price.amount_minor
  from public.subscription_plans p
  join public.subscription_plan_prices price on price.plan_id = p.id
  where p.key = p_plan_key
    and p.is_active
    and p.is_public
    and p.is_purchasable
    and price.interval = p_interval
    and price.currency_code = p_currency_code
    and price.is_active;

  if not found then
    raise exception 'PLAN_PRICE_NOT_AVAILABLE' using errcode = '22023';
  end if;
end;
$$;

comment on function app.resolve_purchasable_plan(text, public.billing_interval, char) is
  'Server-only resolution of an active public purchasable plan and its commercial price.';

-- Public pricing needs commercial data and feature limits, never provider
-- mappings. JSON objects keep the API one row per plan and allow Scale to be a
-- visible preview without fake prices or entitlements.
create or replace function public.subscription_plan_catalog()
returns table (
  plan_key text,
  name text,
  description text,
  sort_order integer,
  is_purchasable boolean,
  prices jsonb,
  entitlements jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.key,
    p.name,
    p.description,
    p.sort_order,
    p.is_purchasable,
    coalesce((
      select jsonb_object_agg(
        price.interval::text,
        jsonb_build_object(
          'currency_code', btrim(price.currency_code),
          'amount_minor', price.amount_minor
        )
      )
      from public.subscription_plan_prices price
      where price.plan_id = p.id and price.is_active
    ), '{}'::jsonb),
    coalesce((
      select jsonb_object_agg(
        entitlement.feature_key,
        jsonb_build_object(
          'is_enabled', entitlement.is_enabled,
          'limit_value', entitlement.limit_value
        )
      )
      from public.subscription_entitlements entitlement
      where entitlement.plan_id = p.id
    ), '{}'::jsonb)
  from public.subscription_plans p
  where p.is_active and p.is_public
  order by p.sort_order, p.key;
$$;

comment on function public.subscription_plan_catalog() is
  'Public launch-plan projection. Omits provider IDs and includes non-purchasable previews.';

-- Catalog tables may contain provider mappings. Consumers use the projection
-- above; entitlement evaluation continues through SECURITY DEFINER helpers.
revoke select on public.subscription_plans,
  public.subscription_plan_prices,
  public.subscription_entitlements
from anon, authenticated;

revoke all on function app.resolve_purchasable_plan(
  text, public.billing_interval, char
) from public, anon, authenticated;

revoke all on function public.subscription_plan_catalog() from public;
grant execute on function public.subscription_plan_catalog()
  to anon, authenticated, service_role;
