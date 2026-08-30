-- Ledger Suit — 18. Notifications

create table if not exists public.notifications (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  -- NULL means the notification is addressed to the whole organization.
  user_id         uuid references public.profiles (id) on delete cascade,
  type            text not null,
  title           text not null,
  body            text,
  entity_type     text,
  entity_id       uuid,
  action_url      text,
  severity        text not null default 'info',
  metadata        jsonb not null default '{}'::jsonb,
  read_at         timestamptz,
  created_at      timestamptz not null default now(),

  constraint notifications_severity_allowed check (
    severity in ('info', 'success', 'warning', 'error')
  ),
  constraint notifications_type_format check (type ~ '^[a-z_]+\.[a-z_]+$')
);

comment on table public.notifications is
  'In-app notifications. Delivery to email/push/SMS is layered on top by a '
  'worker reading this table, so the channel set can grow without a schema '
  'change.';

create index if not exists notifications_org_user_idx
  on public.notifications (organization_id, user_id, created_at desc);
create index if not exists notifications_unread_idx
  on public.notifications (organization_id, user_id) where read_at is null;

alter table public.notifications enable row level security;

create or replace function app.notify(
  p_organization_id uuid,
  p_user_id         uuid,
  p_type            text,
  p_title           text,
  p_body            text default null,
  p_entity_type     text default null,
  p_entity_id       uuid default null,
  p_severity        text default 'info',
  p_metadata        jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.notifications (
    organization_id, user_id, type, title, body, entity_type, entity_id,
    severity, metadata
  )
  values (
    p_organization_id, p_user_id, p_type, p_title, p_body, p_entity_type,
    p_entity_id, p_severity, coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function app.notify(uuid, uuid, text, text, text, text, uuid, text, jsonb)
  to authenticated, service_role;
