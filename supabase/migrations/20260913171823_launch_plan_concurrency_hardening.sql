-- Serialize any physical plan transition with every quota-increasing boundary.
-- Resource operations take one of these locks; acquiring all seven in a fixed
-- order prevents a service callback or future controlled transition from
-- racing a write evaluated against the previous plan.

create function app.lock_all_plan_quotas(p_organization_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_quota_key text;
begin
  if p_organization_id is null then
    raise exception 'PLAN_SUBSCRIPTION_NOT_FOUND' using errcode = '22023';
  end if;

  foreach v_quota_key in array array[
    'max_accounts',
    'max_counterparties',
    'max_custom_roles',
    'max_members',
    'max_monthly_transactions',
    'max_recurring_rules',
    'max_storage_bytes'
  ] loop
    perform app.lock_plan_quota(p_organization_id, v_quota_key);
  end loop;
end;
$$;

comment on function app.lock_all_plan_quotas(uuid) is
  'Takes every organization quota lock in canonical order before a physical subscription plan transition.';

create function app.lock_subscription_plan_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.plan_id is distinct from old.plan_id then
    perform app.lock_all_plan_quotas(new.organization_id);
  end if;
  return new;
end;
$$;

create trigger subscriptions_lock_plan_change
  before update of plan_id on public.subscriptions
  for each row execute function app.lock_subscription_plan_change();

comment on trigger subscriptions_lock_plan_change on public.subscriptions is
  'Coordinates provider/service plan updates with all server-authoritative quota write boundaries.';

revoke all on function app.lock_all_plan_quotas(uuid),
  app.lock_subscription_plan_change()
from public, anon, authenticated;
