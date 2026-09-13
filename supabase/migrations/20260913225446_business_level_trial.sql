-- New customers receive a dedicated 14-day product trial. Existing
-- compatibility and paid subscriptions are intentionally not migrated.

insert into public.subscription_plans (
  key, name, description, is_public, is_active, is_purchasable, sort_order
) values (
  'trial',
  '14-Day Free Trial',
  'Business-level product access for 14 days, excluding Priority Support.',
  false,
  true,
  false,
  0
);

insert into public.subscription_entitlements (
  plan_id, feature_key, is_enabled, limit_value
)
select plan.id, entitlement.feature_key, entitlement.is_enabled,
       entitlement.limit_value
from public.subscription_plans plan
join (values
  ('max_members', true, 10::bigint),
  ('max_monthly_transactions', true, 10000::bigint),
  ('max_storage_bytes', true, 21474836480::bigint),
  ('max_accounts', true, 300::bigint),
  ('max_counterparties', true, 5000::bigint),
  ('max_recurring_rules', true, 100::bigint),
  ('max_custom_roles', true, 10::bigint),
  ('audit_log_retention_days', true, 1095::bigint),
  ('multi_currency', true, null::bigint),
  ('imports', true, null::bigint),
  ('exports', true, null::bigint),
  ('core_reports', true, null::bigint),
  ('priority_support', false, null::bigint),
  ('branches', false, null::bigint),
  ('advanced_analytics', false, null::bigint),
  ('api_access', false, null::bigint),
  ('max_owned_organizations', true, 1::bigint)
) as entitlement(feature_key, is_enabled, limit_value) on true
where plan.key = 'trial';

create or replace function app.start_default_subscription()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan uuid;
begin
  select id into v_plan
  from public.subscription_plans
  where key = 'trial'
    and is_active
    and not is_public
    and not is_purchasable;

  if v_plan is null then
    raise exception 'BILLING_CONFIGURATION_ERROR: trial plan is missing';
  end if;

  insert into public.subscriptions (
    organization_id, plan_id, status, trial_started_at, trial_ends_at
  ) values (
    new.id, v_plan, 'trialing', now(), now() + interval '14 days'
  )
  on conflict (organization_id) do nothing;

  return new;
end;
$$;

comment on function app.start_default_subscription() is
  'Starts each newly provisioned organization on the private 14-day product trial without selecting or purchasing a paid plan.';
