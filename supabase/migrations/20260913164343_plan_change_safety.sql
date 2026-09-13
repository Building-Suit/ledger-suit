-- Read-only plan-change preflight. Provider mutation is deliberately excluded:
-- the checked-in Paymob contract supports initial checkout and verified
-- lifecycle callbacks, but does not establish a safe plan-change API.

create or replace function public.plan_change_impact(
  p_organization_id uuid,
  p_target_plan_key text,
  p_target_interval public.billing_interval
)
returns table (
  current_plan_key text,
  current_interval public.billing_interval,
  target_plan_key text,
  target_interval public.billing_interval,
  target_amount_minor bigint,
  change_direction text,
  provider_change_supported boolean,
  requires_manual_handoff boolean,
  would_block_new_activity boolean,
  audit_history_current_days bigint,
  audit_history_target_days bigint,
  audit_history_reduced boolean,
  quota_impacts jsonb,
  feature_impacts jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current record;
  v_target record;
  v_current_audit record;
  v_target_audit bigint;
  v_quota_impacts jsonb;
  v_feature_impacts jsonb;
  v_would_block boolean;
  v_direction text;
begin
  perform app.require_capability(p_organization_id, 'billing.manage');

  if p_target_plan_key not in ('solo', 'starter', 'business') then
    raise exception 'PLAN_NOT_AVAILABLE' using errcode = '22023';
  end if;

  select plan.key, plan.sort_order, subscription.billing_interval
  into v_current
  from public.subscriptions subscription
  join public.subscription_plans plan on plan.id = subscription.plan_id
  where subscription.organization_id = p_organization_id;

  if not found then
    raise exception 'PLAN_SUBSCRIPTION_NOT_FOUND' using errcode = 'P0001';
  end if;

  -- Migration away from the private compatibility catalog needs the explicit
  -- per-customer policy approved in Step 21. Step 20 must not create a path
  -- that looks like an ordinary launch-plan change.
  if v_current.key = 'ledger_suit'
     or v_current.key like 'legacy\_%' escape '\'
     or v_current.key not in ('solo', 'starter', 'business') then
    raise exception 'LEGACY_PLAN_TRANSITION_NOT_APPROVED'
      using errcode = 'P0001';
  end if;

  select resolved.plan_id, resolved.amount_minor, plan.sort_order
  into strict v_target
  from app.resolve_purchasable_plan(
    p_target_plan_key,
    p_target_interval,
    'EGP'
  ) resolved
  join public.subscription_plans plan on plan.id = resolved.plan_id;

  select * into strict v_current_audit
  from app.resolve_plan_entitlement(
    p_organization_id,
    'audit_log_retention_days'
  );

  select entitlement.limit_value into strict v_target_audit
  from public.subscription_entitlements entitlement
  where entitlement.plan_id = v_target.plan_id
    and entitlement.feature_key = 'audit_log_retention_days'
    and entitlement.is_enabled;

  with quota_keys(key, ordinal) as (
    values
      ('max_members'::text, 1),
      ('max_monthly_transactions', 2),
      ('max_storage_bytes', 3),
      ('max_accounts', 4),
      ('max_counterparties', 5),
      ('max_recurring_rules', 6),
      ('max_custom_roles', 7)
  ), impacts as (
    select
      quota.key,
      quota.ordinal,
      app.plan_quota_usage(p_organization_id, quota.key) as used_value,
      current_entitlement.limit_value as current_limit_value,
      target_entitlement.limit_value as target_limit_value,
      target_entitlement.is_enabled as target_enabled
    from quota_keys quota
    cross join lateral app.resolve_plan_entitlement(
      p_organization_id,
      quota.key
    ) current_entitlement
    join public.subscription_entitlements target_entitlement
      on target_entitlement.plan_id = v_target.plan_id
     and target_entitlement.feature_key = quota.key
  )
  select
    jsonb_agg(
      jsonb_build_object(
        'quota_key', key,
        'used_value', used_value,
        'current_limit_value', current_limit_value,
        'target_limit_value', target_limit_value,
        'is_over_target', target_limit_value is not null and used_value > target_limit_value,
        'will_block_new_activity', not target_enabled
          or (target_limit_value is not null and used_value >= target_limit_value)
      ) order by ordinal
    ),
    bool_or(
      not target_enabled
      or (target_limit_value is not null and used_value >= target_limit_value)
    )
  into v_quota_impacts, v_would_block
  from impacts;

  with feature_keys(key, ordinal) as (
    values
      ('imports'::text, 1),
      ('multi_currency', 2),
      ('priority_support', 3)
  ), impacts as (
    select
      feature.key,
      feature.ordinal,
      current_entitlement.is_enabled as current_enabled,
      target_entitlement.is_enabled as target_enabled
    from feature_keys feature
    cross join lateral app.resolve_plan_entitlement(
      p_organization_id,
      feature.key
    ) current_entitlement
    join public.subscription_entitlements target_entitlement
      on target_entitlement.plan_id = v_target.plan_id
     and target_entitlement.feature_key = feature.key
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'feature_key', key,
        'current_enabled', current_enabled,
        'target_enabled', target_enabled,
        'will_gain', not current_enabled and target_enabled,
        'will_lose', current_enabled and not target_enabled
      ) order by ordinal
    ),
    '[]'::jsonb
  )
  into v_feature_impacts
  from impacts;

  v_direction := case
    when v_current.sort_order < v_target.sort_order then 'upgrade'
    when v_current.sort_order > v_target.sort_order then 'downgrade'
    when v_current.billing_interval is distinct from p_target_interval then 'billing_cycle_change'
    else 'no_change'
  end;

  return query select
    v_current.key,
    v_current.billing_interval,
    p_target_plan_key,
    p_target_interval,
    v_target.amount_minor,
    v_direction,
    false,
    v_direction <> 'no_change',
    coalesce(v_would_block, false),
    v_current_audit.limit_value,
    v_target_audit,
    v_current_audit.limit_value is null
      or v_current_audit.limit_value > v_target_audit,
    coalesce(v_quota_impacts, '[]'::jsonb),
    v_feature_impacts;
end;
$$;

comment on function public.plan_change_impact(
  uuid, text, public.billing_interval
) is
  'Authorized, read-only launch-plan preflight. Reports quota and feature consequences without changing subscription or customer data.';

revoke all on function public.plan_change_impact(
  uuid, text, public.billing_interval
) from public, anon;
grant execute on function public.plan_change_impact(
  uuid, text, public.billing_interval
) to authenticated, service_role;
