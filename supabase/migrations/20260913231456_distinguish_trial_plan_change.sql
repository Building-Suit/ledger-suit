-- Trial conversion is checkout, not an in-place Step-20 plan change. Preserve
-- the existing launch-plan preflight implementation behind a private boundary
-- and keep the public RPC's source-plan classification authoritative.

alter function public.plan_change_impact(
  uuid, text, public.billing_interval
) set schema app;

revoke all on function app.plan_change_impact(
  uuid, text, public.billing_interval
) from public, anon, authenticated;

comment on function app.plan_change_impact(
  uuid, text, public.billing_interval
) is
  'Private Solo/Starter/Business impact implementation called only after the public source-plan boundary validates the current subscription.';

create function public.plan_change_impact(
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
  v_current_plan_key text;
begin
  perform app.require_capability(p_organization_id, 'billing.manage');

  select plan.key into v_current_plan_key
  from public.subscriptions subscription
  join public.subscription_plans plan on plan.id = subscription.plan_id
  where subscription.organization_id = p_organization_id;

  if not found then
    raise exception 'PLAN_SUBSCRIPTION_NOT_FOUND' using errcode = 'P0001';
  end if;

  if v_current_plan_key = 'trial' then
    raise exception 'TRIAL_PLAN_CHANGE_REQUIRES_CHECKOUT'
      using errcode = 'P0001';
  end if;

  if v_current_plan_key = 'ledger_suit'
     or v_current_plan_key like 'legacy\_%' escape '\'
     or v_current_plan_key not in ('solo', 'starter', 'business') then
    raise exception 'LEGACY_PLAN_TRANSITION_NOT_APPROVED'
      using errcode = 'P0001';
  end if;

  return query
  select *
  from app.plan_change_impact(
    p_organization_id,
    p_target_plan_key,
    p_target_interval
  );
end;
$$;

comment on function public.plan_change_impact(
  uuid, text, public.billing_interval
) is
  'Authorized read-only launch-plan preflight. Trial conversion requires signed checkout; compatibility-plan migration remains unavailable.';

revoke all on function public.plan_change_impact(
  uuid, text, public.billing_interval
) from public, anon;
grant execute on function public.plan_change_impact(
  uuid, text, public.billing_interval
) to authenticated, service_role;
