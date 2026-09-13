-- Plan-aware visibility over the append-only audit trail. Historical rows stay
-- stored; only this tenant-safe read boundary applies the current plan window.

drop function if exists public.audit_history_window_days(uuid);

create or replace function public.audit_history_window(p_organization_id uuid)
returns table (days bigint, is_unlimited boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_entitlement record;
begin
  perform app.require_capability(p_organization_id, 'audit.read');
  select * into strict v_entitlement
  from app.resolve_plan_entitlement(p_organization_id, 'audit_log_retention_days');

  if not v_entitlement.is_enabled
     or (v_entitlement.limit_value is not null and v_entitlement.limit_value <= 0) then
    raise exception 'AUDIT_HISTORY_WINDOW_NOT_CONFIGURED'
      using errcode = '55000';
  end if;

  return query select
    v_entitlement.limit_value,
    v_entitlement.limit_value is null;
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
  v_entitlement record;
begin
  perform app.require_capability(p_organization_id, 'audit.read');

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'INVALID_AUDIT_HISTORY_LIMIT: expected 1 to 100'
      using errcode = '22023';
  end if;

  select * into strict v_entitlement
  from app.resolve_plan_entitlement(p_organization_id, 'audit_log_retention_days');
  if not v_entitlement.is_enabled
     or (v_entitlement.limit_value is not null and v_entitlement.limit_value <= 0) then
    raise exception 'AUDIT_HISTORY_WINDOW_NOT_CONFIGURED'
      using errcode = '55000';
  end if;

  return query
  select audit.id, audit.actor_id, audit.actor_email, audit.action,
         audit.entity_type, audit.entity_id, audit.before_state,
         audit.after_state, audit.metadata, audit.created_at
  from public.audit_logs audit
  where audit.organization_id = p_organization_id
    and (
      v_entitlement.limit_value is null
      or audit.created_at >= transaction_timestamp()
        - make_interval(days => v_entitlement.limit_value::integer)
    )
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

comment on function public.audit_history_window(uuid) is
  'Returns finite days or an explicit unlimited flag using the compatibility-aware plan entitlement resolver.';
comment on function public.list_audit_history(uuid, integer, timestamptz, bigint) is
  'Lists tenant audit events inside the current plan window without deleting older append-only records.';

-- Direct table reads would bypass the plan window; all client reads use the RPC.
revoke select on public.audit_logs from authenticated;

revoke all on function public.audit_history_window(uuid),
  public.list_audit_history(uuid, integer, timestamptz, bigint) from public, anon;
grant execute on function public.audit_history_window(uuid),
  public.list_audit_history(uuid, integer, timestamptz, bigint)
  to authenticated, service_role;
