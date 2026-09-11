-- Central plan entitlement, usage, and quota assertion contracts.
--
-- Resource-specific write paths are connected to these helpers in the
-- following focused migrations. Keeping the engine private prevents clients
-- from treating plan metadata or a UI preflight as authorization.

create or replace function app.resolve_plan_entitlement(
  p_organization_id uuid,
  p_feature_key text
)
returns table (
  plan_key text,
  entitlement_found boolean,
  is_enabled boolean,
  limit_value bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_plan_key text;
  v_entitlement_found boolean;
  v_is_enabled boolean;
  v_limit_value bigint;
begin
  if p_organization_id is null or nullif(btrim(p_feature_key), '') is null then
    raise exception 'PLAN_ENTITLEMENT_ARGUMENT_INVALID'
      using errcode = '22023';
  end if;

  select
    plan.key,
    entitlement.feature_key is not null,
    coalesce(entitlement.is_enabled, true),
    entitlement.limit_value
  into
    v_plan_key,
    v_entitlement_found,
    v_is_enabled,
    v_limit_value
  from public.subscriptions subscription
  join public.subscription_plans plan on plan.id = subscription.plan_id
  left join public.subscription_entitlements entitlement
    on entitlement.plan_id = plan.id
   and entitlement.feature_key = p_feature_key
  where subscription.organization_id = p_organization_id;

  if not found then
    raise exception 'PLAN_SUBSCRIPTION_NOT_FOUND'
      using errcode = 'P0001';
  end if;

  -- The compatibility plan predates the complete launch matrix. Its missing
  -- keys remain enabled and unlimited until customers are explicitly moved.
  -- A missing launch-plan key is configuration drift and must fail closed.
  if not v_entitlement_found
     and v_plan_key <> 'ledger_suit'
     and v_plan_key not like 'legacy\_%' escape '\' then
    raise exception 'PLAN_ENTITLEMENT_NOT_CONFIGURED: %', p_feature_key
      using errcode = 'P0001';
  end if;

  return query select
    v_plan_key,
    v_entitlement_found,
    v_is_enabled,
    v_limit_value;
end;
$$;

comment on function app.resolve_plan_entitlement(uuid, text) is
  'Private plan lookup independent of membership and subscription write state. Missing compatibility-plan keys are unlimited; missing launch-plan keys fail closed.';

create or replace function app.plan_quota_lock_key(
  p_organization_id uuid,
  p_quota_key text
)
returns bigint
language plpgsql
immutable
strict
set search_path = ''
as $$
begin
  if nullif(btrim(p_quota_key), '') is null then
    raise exception 'PLAN_QUOTA_KEY_INVALID'
      using errcode = '22023';
  end if;

  return pg_catalog.hashtextextended(
    p_organization_id::text || ':' || p_quota_key,
    73214761
  );
end;
$$;

comment on function app.plan_quota_lock_key(uuid, text) is
  'Stable transaction-lock key derived from an organization UUID and canonical quota key.';

create or replace function app.lock_plan_quota(
  p_organization_id uuid,
  p_quota_key text
)
returns bigint
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_lock_key bigint := app.plan_quota_lock_key(p_organization_id, p_quota_key);
begin
  perform pg_catalog.pg_advisory_xact_lock(v_lock_key);
  return v_lock_key;
end;
$$;

comment on function app.lock_plan_quota(uuid, text) is
  'Serializes quota-increasing writes for one organization and resource until the current transaction ends.';

create or replace function app.plan_quota_error_code(p_quota_key text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select case p_quota_key
    when 'max_members' then 'PLAN_MEMBER_LIMIT_REACHED'
    when 'max_monthly_transactions' then 'PLAN_TRANSACTION_LIMIT_REACHED'
    when 'max_storage_bytes' then 'PLAN_STORAGE_LIMIT_REACHED'
    when 'max_accounts' then 'PLAN_ACCOUNT_LIMIT_REACHED'
    when 'max_counterparties' then 'PLAN_COUNTERPARTY_LIMIT_REACHED'
    when 'max_recurring_rules' then 'PLAN_RECURRING_LIMIT_REACHED'
    when 'max_custom_roles' then 'PLAN_CUSTOM_ROLE_LIMIT_REACHED'
    else null
  end;
$$;

create or replace function app.plan_feature_error_code(p_feature_key text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select case p_feature_key
    when 'multi_currency' then 'MULTI_CURRENCY_REQUIRES_BUSINESS'
    else 'FEATURE_NOT_AVAILABLE_ON_PLAN'
  end;
$$;

create or replace function app.plan_quota_usage(
  p_organization_id uuid,
  p_quota_key text
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_usage bigint;
begin
  case p_quota_key
    when 'max_members' then
      select
        (select count(*) from public.organization_members member
         where member.organization_id = p_organization_id
           and member.status = 'active')
        +
        (select count(*) from public.organization_invitations invitation
         where invitation.organization_id = p_organization_id
           and invitation.status = 'pending'
           and invitation.expires_at > now())
      into v_usage;

    when 'max_monthly_transactions' then
      select count(*)
      into v_usage
      from public.transactions transaction
      join public.organizations organization
        on organization.id = transaction.organization_id
      where transaction.organization_id = p_organization_id
        and transaction.posted_at is not null
        and transaction.posted_at >= (
          date_trunc('month', now() at time zone organization.timezone)
          at time zone organization.timezone
        )
        and transaction.posted_at < (
          (date_trunc('month', now() at time zone organization.timezone) + interval '1 month')
          at time zone organization.timezone
        );

    when 'max_storage_bytes' then
      select coalesce(sum(attachment.size_bytes), 0)
      into v_usage
      from public.attachments attachment
      where attachment.organization_id = p_organization_id;

    when 'max_accounts' then
      select count(*) into v_usage
      from public.accounts account
      where account.organization_id = p_organization_id;

    when 'max_counterparties' then
      select count(*) into v_usage
      from public.counterparties counterparty
      where counterparty.organization_id = p_organization_id;

    when 'max_recurring_rules' then
      select count(*) into v_usage
      from public.recurring_rules rule
      where rule.organization_id = p_organization_id
        and rule.status in ('active', 'paused', 'failed');

    when 'max_custom_roles' then
      select count(*) into v_usage
      from public.organization_roles role
      where role.organization_id = p_organization_id;

    else
      raise exception 'PLAN_QUOTA_NOT_SUPPORTED: %', p_quota_key
        using errcode = '22023';
  end case;

  return coalesce(v_usage, 0);
end;
$$;

comment on function app.plan_quota_usage(uuid, text) is
  'Private authoritative usage count. Each predicate is shared by enforcement and the public usage summary.';

create or replace function app.assert_plan_feature(
  p_organization_id uuid,
  p_feature_key text
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_entitlement record;
begin
  select * into strict v_entitlement
  from app.resolve_plan_entitlement(p_organization_id, p_feature_key);

  if not v_entitlement.is_enabled
     or (v_entitlement.limit_value is not null and v_entitlement.limit_value = 0) then
    raise exception '%: %', app.plan_feature_error_code(p_feature_key), p_feature_key
      using errcode = 'P0001';
  end if;
end;
$$;

comment on function app.assert_plan_feature(uuid, text) is
  'Private feature assertion. Subscription access must be checked separately by the calling write path.';

create or replace function app.assert_plan_quota(
  p_organization_id uuid,
  p_quota_key text,
  p_requested bigint default 1
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_entitlement record;
  v_usage bigint;
  v_error_code text := app.plan_quota_error_code(p_quota_key);
begin
  if p_requested is null or p_requested <= 0 then
    raise exception 'PLAN_QUOTA_INCREMENT_INVALID'
      using errcode = '22023';
  end if;

  if v_error_code is null then
    raise exception 'PLAN_QUOTA_NOT_SUPPORTED: %', p_quota_key
      using errcode = '22023';
  end if;

  -- Every caller uses the same key and recounts after acquiring the lock.
  perform app.lock_plan_quota(p_organization_id, p_quota_key);

  select * into strict v_entitlement
  from app.resolve_plan_entitlement(p_organization_id, p_quota_key);

  v_usage := app.plan_quota_usage(p_organization_id, p_quota_key);

  if not v_entitlement.is_enabled
     or (v_entitlement.limit_value is not null
         and v_usage + p_requested > v_entitlement.limit_value) then
    raise exception '%: usage %, requested %, limit %',
      v_error_code,
      v_usage,
      p_requested,
      coalesce(v_entitlement.limit_value::text, 'unlimited')
      using errcode = 'P0001';
  end if;
end;
$$;

comment on function app.assert_plan_quota(uuid, text, bigint) is
  'Locks, recounts, and rejects a quota-increasing write when current usage plus the requested increment exceeds the raw plan limit.';

create or replace function public.get_usage(
  p_organization_id uuid,
  p_quota_key text
)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not app.is_org_member(p_organization_id) then 0::bigint
    else app.plan_quota_usage(p_organization_id, p_quota_key)
  end;
$$;

create or replace function public.subscription_usage_summary(
  p_organization_id uuid
)
returns table (
  plan_key text,
  subscription_status public.billing_status,
  writes_allowed boolean,
  quota_key text,
  used_value bigint,
  limit_value bigint,
  remaining_value bigint,
  is_unlimited boolean,
  is_at_limit boolean,
  is_over_limit boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    plan.key,
    subscription.status,
    app.subscription_writes_allowed(p_organization_id),
    quota.key,
    usage.used_value,
    entitlement.limit_value,
    case
      when entitlement.limit_value is null then null
      else greatest(entitlement.limit_value - usage.used_value, 0)
    end,
    entitlement.limit_value is null,
    entitlement.limit_value is not null
      and usage.used_value >= entitlement.limit_value,
    entitlement.limit_value is not null
      and usage.used_value > entitlement.limit_value
  from public.subscriptions subscription
  join public.subscription_plans plan on plan.id = subscription.plan_id
  cross join (values
    ('max_members'),
    ('max_monthly_transactions'),
    ('max_storage_bytes'),
    ('max_accounts'),
    ('max_counterparties'),
    ('max_recurring_rules'),
    ('max_custom_roles')
  ) as quota(key)
  cross join lateral app.resolve_plan_entitlement(
    p_organization_id,
    quota.key
  ) entitlement
  cross join lateral (
    select app.plan_quota_usage(p_organization_id, quota.key) as used_value
  ) usage
  where subscription.organization_id = p_organization_id
    and app.is_org_member(p_organization_id)
  order by quota.key;
$$;

comment on function public.get_usage(uuid, text) is
  'Returns authoritative current usage to organization members and 0 across the tenant boundary.';
comment on function public.subscription_usage_summary(uuid) is
  'Tenant-safe quota summary. Subscription write access and plan capacity are reported as separate states.';

revoke all on function app.resolve_plan_entitlement(uuid, text) from public, anon, authenticated;
revoke all on function app.plan_quota_lock_key(uuid, text) from public, anon, authenticated;
revoke all on function app.lock_plan_quota(uuid, text) from public, anon, authenticated;
revoke all on function app.plan_quota_error_code(text) from public, anon, authenticated;
revoke all on function app.plan_feature_error_code(text) from public, anon, authenticated;
revoke all on function app.plan_quota_usage(uuid, text) from public, anon, authenticated;
revoke all on function app.assert_plan_feature(uuid, text) from public, anon, authenticated;
revoke all on function app.assert_plan_quota(uuid, text, bigint) from public, anon, authenticated;

revoke all on function public.get_usage(uuid, text) from public, anon;
revoke all on function public.subscription_usage_summary(uuid) from public, anon;
grant execute on function public.get_usage(uuid, text) to authenticated, service_role;
grant execute on function public.subscription_usage_summary(uuid) to authenticated, service_role;
