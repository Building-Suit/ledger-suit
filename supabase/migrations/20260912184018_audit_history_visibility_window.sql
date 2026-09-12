-- Plan-aware visibility over the append-only audit trail. Historical rows stay
-- stored; only this tenant-safe read boundary applies the current plan window.

create or replace function app.audit_history_days(p_organization_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select entitlement.limit_value
  from public.subscriptions subscription
  join public.subscription_entitlements entitlement
    on entitlement.plan_id = subscription.plan_id
  where subscription.organization_id = p_organization_id
    and entitlement.feature_key = 'audit_log_retention_days'
    and entitlement.is_enabled
$$;

create or replace function public.audit_history_window_days(p_organization_id uuid)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_days bigint;
begin
  perform app.require_capability(p_organization_id, 'audit.read');
  v_days := app.audit_history_days(p_organization_id);

  if v_days is null or v_days <= 0 then
    raise exception 'AUDIT_HISTORY_WINDOW_NOT_CONFIGURED'
      using errcode = '55000';
  end if;

  return v_days;
end;
$$;

create or replace function public.list_audit_history(
  p_organization_id uuid,
  p_limit integer default 50,
  p_before_created_at timestamptz default null,
  p_before_id bigint default null
)
returns table (
  id bigint,
  actor_id uuid,
  actor_email text,
  action text,
  entity_type text,
  entity_id uuid,
  before_state jsonb,
  after_state jsonb,
  metadata jsonb,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_days bigint;
begin
  perform app.require_capability(p_organization_id, 'audit.read');

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'INVALID_AUDIT_HISTORY_LIMIT: expected 1 to 100'
      using errcode = '22023';
  end if;

  v_days := app.audit_history_days(p_organization_id);
  if v_days is null or v_days <= 0 then
    raise exception 'AUDIT_HISTORY_WINDOW_NOT_CONFIGURED'
      using errcode = '55000';
  end if;

  return query
  select audit.id, audit.actor_id, audit.actor_email, audit.action,
         audit.entity_type, audit.entity_id, audit.before_state,
         audit.after_state, audit.metadata, audit.created_at
  from public.audit_logs audit
  where audit.organization_id = p_organization_id
    and audit.created_at >= transaction_timestamp() - make_interval(days => v_days::integer)
    and (
      p_before_created_at is null
      or (audit.created_at, audit.id) < (
        p_before_created_at,
        coalesce(p_before_id, 9223372036854775807::bigint)
      )
    )
  order by audit.created_at desc, audit.id desc
  limit p_limit;
end;
$$;

comment on function public.audit_history_window_days(uuid) is
  'Returns the current plan audit-history visibility window after tenant and capability checks.';
comment on function public.list_audit_history(uuid, integer, timestamptz, bigint) is
  'Lists tenant audit events inside the current plan window without deleting older append-only records.';

-- Direct table reads would bypass the plan window; all client reads use the RPC.
revoke select on public.audit_logs from authenticated;

revoke all on function app.audit_history_days(uuid) from public, anon, authenticated;
revoke all on function public.audit_history_window_days(uuid),
  public.list_audit_history(uuid, integer, timestamptz, bigint) from public, anon;
grant execute on function public.audit_history_window_days(uuid),
  public.list_audit_history(uuid, integer, timestamptz, bigint)
  to authenticated, service_role;
