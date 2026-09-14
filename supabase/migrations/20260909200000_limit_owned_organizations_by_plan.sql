-- The current Ledger Suit plan permits one owned organization per user. Users
-- may still belong to any number of organizations in non-owner roles.

insert into public.subscription_entitlements (
  plan_id, feature_key, is_enabled, limit_value
)
select p.id, 'max_owned_organizations', true, 1
from public.subscription_plans p
where p.key = 'ledger_suit'
on conflict (plan_id, feature_key) do update
set is_enabled = excluded.is_enabled,
    limit_value = excluded.limit_value;

create or replace function app.enforce_owned_organization_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit bigint;
  v_owned bigint;
  v_excluded_membership uuid;
begin
  -- Only check transitions that add an active owner. Updates to an existing
  -- active owner remain possible, and demotions/suspensions are unrestricted.
  if new.role <> 'owner' or new.status <> 'active' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.user_id = new.user_id
      and old.organization_id = new.organization_id
      and old.role = 'owner'
      and old.status = 'active' then
      return new;
    end if;
    v_excluded_membership := old.id;
  end if;

  -- Serialize ownership grants for this user so concurrent requests cannot
  -- both observe an available slot.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.user_id::text, 726478)
  );

  select case when e.is_enabled then e.limit_value else 0 end
  into v_limit
  from public.subscriptions s
  join public.subscription_entitlements e on e.plan_id = s.plan_id
  where s.organization_id = new.organization_id
    and e.feature_key = 'max_owned_organizations';

  -- A missing entitlement or NULL limit means unlimited, preserving future
  -- plans until they explicitly opt into an ownership cap.
  if not found or v_limit is null then
    return new;
  end if;

  select count(*)
  into v_owned
  from public.organization_members m
  where m.user_id = new.user_id
    and m.role = 'owner'
    and m.status = 'active'
    and (v_excluded_membership is null or m.id <> v_excluded_membership);

  if v_owned >= v_limit then
    raise exception 'ORGANIZATION_OWNER_LIMIT_REACHED: current plan allows % owned organization(s)', v_limit
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists organization_members_enforce_owner_limit
  on public.organization_members;
create trigger organization_members_enforce_owner_limit
  before insert or update of user_id, organization_id, role, status
  on public.organization_members
  for each row execute function app.enforce_owned_organization_limit();

comment on function app.enforce_owned_organization_limit() is
  'Enforces the target organization plan max_owned_organizations entitlement for active owner memberships.';
