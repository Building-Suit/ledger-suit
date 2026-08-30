-- Ledger Suit — 12. Audit log
--
-- Append-only from every ordinary path. Written by app.write_audit() only;
-- INSERT/UPDATE/DELETE are revoked from client roles and blocked by trigger,
-- so there is no client-side deletion even with a forged request.

create table if not exists public.audit_logs (
  id              bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  actor_id        uuid references public.profiles (id) on delete set null,
  actor_email     text,
  action          text not null,
  entity_type     text not null,
  entity_id       uuid,
  before_state    jsonb,
  after_state     jsonb,
  ip_address      inet,
  user_agent      text,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),

  constraint audit_logs_action_format check (action ~ '^[a-z_]+\.[a-z_]+$')
);

comment on table public.audit_logs is
  'Append-only audit trail. Written exclusively through app.write_audit().';
comment on column public.audit_logs.actor_email is
  'Snapshot of the actor email at the time of the action, so the entry stays '
  'readable after the profile is deleted.';

create index if not exists audit_logs_org_created_idx
  on public.audit_logs (organization_id, created_at desc);
create index if not exists audit_logs_org_entity_idx
  on public.audit_logs (organization_id, entity_type, entity_id);
create index if not exists audit_logs_org_actor_idx
  on public.audit_logs (organization_id, actor_id);
create index if not exists audit_logs_org_action_idx
  on public.audit_logs (organization_id, action);

alter table public.audit_logs enable row level security;

create trigger audit_logs_append_only
  before update or delete on public.audit_logs
  for each row execute function app.reject_mutation();

revoke insert, update, delete on public.audit_logs from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Writer
-- ---------------------------------------------------------------------------
create or replace function app.request_header(p_name text)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_headers jsonb;
begin
  -- request.headers is only present behind PostgREST and is not guaranteed to
  -- be valid JSON in every context, so failure here must never break a write.
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then
    return null;
  end;

  return v_headers ->> p_name;
end;
$$;

create or replace function app.write_audit(
  p_organization_id uuid,
  p_action          text,
  p_entity_type     text,
  p_entity_id       uuid    default null,
  p_before          jsonb   default null,
  p_after           jsonb   default null,
  p_metadata        jsonb   default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
  v_ip text;
begin
  v_ip := split_part(coalesce(app.request_header('x-forwarded-for'), ''), ',', 1);

  insert into public.audit_logs (
    organization_id, actor_id, actor_email, action, entity_type, entity_id,
    before_state, after_state, ip_address, user_agent, metadata
  )
  values (
    p_organization_id,
    auth.uid(),
    (select p.email::text from public.profiles p where p.id = auth.uid()),
    p_action,
    p_entity_type,
    p_entity_id,
    p_before,
    p_after,
    case when v_ip ~ '^\d{1,3}(\.\d{1,3}){3}$' or v_ip like '%:%'
         then v_ip::inet else null end,
    left(coalesce(app.request_header('user-agent'), ''), 500),
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function app.write_audit(uuid, text, text, uuid, jsonb, jsonb, jsonb) is
  'The only sanctioned writer for public.audit_logs. Actor is resolved from '
  'auth.uid(), never from an argument.';

grant execute on function app.write_audit(uuid, text, text, uuid, jsonb, jsonb, jsonb)
  to authenticated, service_role;
