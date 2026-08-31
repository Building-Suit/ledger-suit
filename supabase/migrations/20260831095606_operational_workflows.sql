-- Ledger Suit — Controlled account and notification operations used by the UI.

create or replace function public.create_account(
  p_organization_id uuid,
  p_name text,
  p_type public.account_type,
  p_subtype public.account_subtype,
  p_currency char(3) default null,
  p_code text default null,
  p_parent_account_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  perform app.require_capability(p_organization_id, 'accounts.create');
  if p_name is null or char_length(trim(p_name)) = 0 then
    raise exception 'INVALID_INPUT: account name is required' using errcode = '22023';
  end if;
  if p_parent_account_id is not null then
    perform app.require_account(p_organization_id, p_parent_account_id,
      array[p_type]::public.account_type[], 'parent account');
  end if;

  insert into public.accounts (
    organization_id, code, name, type, subtype, currency,
    parent_account_id, created_by
  ) values (
    p_organization_id, nullif(trim(p_code), ''), trim(p_name), p_type,
    p_subtype, coalesce(p_currency, app.org_base_currency(p_organization_id)),
    p_parent_account_id, auth.uid()
  ) returning id into v_id;

  perform app.write_audit(p_organization_id, 'account.created', 'account', v_id,
    null, jsonb_build_object('name', trim(p_name), 'type', p_type, 'subtype', p_subtype));
  return v_id;
end;
$$;

create or replace function public.update_account(
  p_account_id uuid,
  p_name text,
  p_code text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_row public.accounts%rowtype;
begin
  select * into v_row from public.accounts a where a.id = p_account_id for update;
  if not found then
    raise exception 'TENANT_ACCESS_DENIED: account not found' using errcode = '42501';
  end if;
  perform app.require_capability(v_row.organization_id, 'accounts.update');
  if p_name is null or char_length(trim(p_name)) = 0 then
    raise exception 'INVALID_INPUT: account name is required' using errcode = '22023';
  end if;
  update public.accounts a
  set name = trim(p_name), code = nullif(trim(p_code), '')
  where a.id = p_account_id;
  perform app.write_audit(v_row.organization_id, 'account.updated', 'account', p_account_id,
    jsonb_build_object('name', v_row.name, 'code', v_row.code),
    jsonb_build_object('name', trim(p_name), 'code', nullif(trim(p_code), '')));
  return p_account_id;
end;
$$;

create or replace function public.archive_account(p_account_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_row public.accounts%rowtype;
begin
  select * into v_row from public.accounts a where a.id = p_account_id for update;
  if not found then
    raise exception 'TENANT_ACCESS_DENIED: account not found' using errcode = '42501';
  end if;
  perform app.require_capability(v_row.organization_id, 'accounts.archive');
  if v_row.is_system then
    raise exception 'SYSTEM_ACCOUNT_PROTECTED: system accounts cannot be archived'
      using errcode = '23514';
  end if;
  update public.accounts a set is_archived = true, archived_at = now()
  where a.id = p_account_id;
  perform app.write_audit(v_row.organization_id, 'account.archived', 'account', p_account_id,
    jsonb_build_object('is_archived', false), jsonb_build_object('is_archived', true));
  return p_account_id;
end;
$$;

-- A notification recipient may only change read state, not routing/content.
revoke update on public.notifications from authenticated;
drop policy if exists "notifications are marked read by their addressee"
  on public.notifications;

create or replace function public.mark_notification_read(
  p_notification_id uuid,
  p_read boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_row public.notifications%rowtype;
begin
  select * into v_row from public.notifications n where n.id = p_notification_id for update;
  if not found or not app.is_org_member(v_row.organization_id)
     or (v_row.user_id is not null and v_row.user_id <> auth.uid()) then
    raise exception 'TENANT_ACCESS_DENIED: notification not found' using errcode = '42501';
  end if;
  update public.notifications n set read_at = case when p_read then now() else null end
  where n.id = p_notification_id;
  return p_notification_id;
end;
$$;

create or replace function public.mark_all_notifications_read(p_organization_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_count integer;
begin
  if not app.is_org_member(p_organization_id) then
    raise exception 'TENANT_ACCESS_DENIED' using errcode = '42501';
  end if;
  update public.notifications n set read_at = now()
  where n.organization_id = p_organization_id
    and (n.user_id is null or n.user_id = auth.uid())
    and n.read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

do $$
declare v_fn record;
begin
  for v_fn in
    select p.oid::regprocedure as signature
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'create_account', 'update_account', 'archive_account',
        'mark_notification_read', 'mark_all_notifications_read'
      )
  loop
    execute format('revoke all on function %s from public, anon', v_fn.signature);
    execute format('grant execute on function %s to authenticated, service_role', v_fn.signature);
  end loop;
end;
$$;
