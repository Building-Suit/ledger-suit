-- Aggregate attachment quota with expiring, exactly-bound upload reservations.

create table app.attachment_storage_reservations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  attachment_id uuid unique,
  entity_type text not null check (entity_type in ('transaction', 'commitment', 'account', 'organization', 'import')),
  entity_id uuid not null,
  file_name text not null check (char_length(file_name) between 1 and 255),
  mime_type text not null check (mime_type in ('application/pdf', 'image/png', 'image/jpeg', 'image/webp')),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 26214400),
  storage_bucket text not null default 'attachments',
  storage_key text not null,
  reserved_by uuid references public.profiles (id) on delete set null,
  status text not null default 'reserved'
    check (status in ('reserved', 'committed', 'aborted', 'expired', 'cleanup_pending', 'cleaned')),
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  cleanup_claimed_at timestamptz,
  cleanup_attempts integer not null default 0,
  last_cleanup_error text,
  unique (storage_bucket, storage_key),
  check (storage_key like organization_id::text || '/%')
);

create index attachment_storage_reservations_live_idx
  on app.attachment_storage_reservations (organization_id, expires_at)
  where status = 'reserved';
create index attachment_storage_reservations_cleanup_idx
  on app.attachment_storage_reservations (cleanup_claimed_at, created_at)
  where status in ('reserved', 'aborted', 'expired', 'cleanup_pending');

insert into app.attachment_storage_reservations (
  organization_id, attachment_id, entity_type, entity_id, file_name, mime_type,
  size_bytes, storage_bucket, storage_key, reserved_by, status, expires_at,
  created_at, completed_at
)
select organization_id, id, entity_type, entity_id, file_name, mime_type,
       size_bytes, storage_bucket, storage_key, uploaded_by, 'committed',
       created_at, created_at, created_at
from public.attachments
on conflict (storage_bucket, storage_key) do nothing;

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
         where member.organization_id = p_organization_id and member.status = 'active')
        +
        (select count(*) from public.organization_invitations invitation
         where invitation.organization_id = p_organization_id
           and invitation.status = 'pending' and invitation.expires_at > now())
      into v_usage;
    when 'max_monthly_transactions' then
      select count(*) into v_usage
      from public.transactions transaction
      join public.organizations organization on organization.id = transaction.organization_id
      where transaction.organization_id = p_organization_id
        and transaction.posted_at is not null
        and transaction.posted_at >= (date_trunc('month', now() at time zone organization.timezone) at time zone organization.timezone)
        and transaction.posted_at < ((date_trunc('month', now() at time zone organization.timezone) + interval '1 month') at time zone organization.timezone);
    when 'max_storage_bytes' then
      select
        coalesce((select sum(a.size_bytes) from public.attachments a
                  where a.organization_id = p_organization_id), 0)
        +
        coalesce((select sum(r.size_bytes) from app.attachment_storage_reservations r
                  where r.organization_id = p_organization_id
                    and r.status = 'reserved' and r.expires_at > now()), 0)
      into v_usage;
    when 'max_accounts' then
      select count(*) into v_usage from public.accounts a where a.organization_id = p_organization_id;
    when 'max_counterparties' then
      select count(*) into v_usage from public.counterparties c where c.organization_id = p_organization_id;
    when 'max_recurring_rules' then
      select count(*) into v_usage from public.recurring_rules r
      where r.organization_id = p_organization_id and r.status in ('active', 'paused', 'failed');
    when 'max_custom_roles' then
      select count(*) into v_usage from public.organization_roles r where r.organization_id = p_organization_id;
    else
      raise exception 'PLAN_QUOTA_NOT_SUPPORTED: %', p_quota_key using errcode = '22023';
  end case;
  return coalesce(v_usage, 0);
end;
$$;

create or replace function app.attachment_entity_exists(
  p_organization_id uuid, p_entity_type text, p_entity_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return case p_entity_type
    when 'transaction' then exists (select 1 from public.transactions where id = p_entity_id and organization_id = p_organization_id)
    when 'commitment' then exists (select 1 from public.commitments where id = p_entity_id and organization_id = p_organization_id)
    when 'account' then exists (select 1 from public.accounts where id = p_entity_id and organization_id = p_organization_id)
    when 'organization' then p_entity_id = p_organization_id
    when 'import' then true
    else false
  end;
end;
$$;

create or replace function public.reserve_attachment_upload(
  p_organization_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_file_name text,
  p_mime_type text,
  p_size_bytes bigint,
  p_storage_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  perform app.require_capability(p_organization_id, 'attachments.create');

  if p_entity_type not in ('transaction', 'commitment', 'account', 'organization', 'import')
     or not app.attachment_entity_exists(p_organization_id, p_entity_type, p_entity_id)
     or char_length(p_file_name) not between 1 and 255
     or p_mime_type not in ('application/pdf', 'image/png', 'image/jpeg', 'image/webp')
     or p_size_bytes not between 1 and 26214400
     or p_storage_key not like p_organization_id::text || '/' || p_entity_type || '/' || p_entity_id::text || '/%'
  then
    raise exception 'ATTACHMENT_INVALID: upload metadata is invalid' using errcode = '22023';
  end if;

  perform app.assert_plan_quota(p_organization_id, 'max_storage_bytes', p_size_bytes);
  insert into app.attachment_storage_reservations (
    organization_id, entity_type, entity_id, file_name, mime_type, size_bytes,
    storage_key, reserved_by
  ) values (
    p_organization_id, p_entity_type, p_entity_id, p_file_name, p_mime_type,
    p_size_bytes, p_storage_key, auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function app.storage_upload_matches_reservation(
  p_bucket text, p_key text, p_metadata jsonb
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from app.attachment_storage_reservations r
    where r.storage_bucket = p_bucket and r.storage_key = p_key
      and r.status = 'reserved' and r.expires_at > now()
      and r.reserved_by = auth.uid()
      and r.size_bytes = nullif(p_metadata ->> 'size', '')::bigint
      and r.mime_type = p_metadata ->> 'mimetype'
      and app.has_capability(r.organization_id, 'attachments.create')
  );
$$;

create or replace function public.commit_attachment_upload(p_reservation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reservation app.attachment_storage_reservations%rowtype;
  v_object record;
  v_attachment_id uuid;
begin
  select * into v_reservation from app.attachment_storage_reservations
  where id = p_reservation_id for update;
  if not found then raise exception 'ATTACHMENT_RESERVATION_NOT_FOUND:' using errcode = 'P0002'; end if;
  perform app.require_capability(v_reservation.organization_id, 'attachments.create');
  if v_reservation.reserved_by is distinct from auth.uid() and not app.is_service_context() then
    raise exception 'TENANT_ACCESS_DENIED: reservation owner mismatch' using errcode = '42501';
  end if;
  if v_reservation.status = 'committed' then return v_reservation.attachment_id; end if;
  if v_reservation.status <> 'reserved' or v_reservation.expires_at <= now() then
    raise exception 'ATTACHMENT_RESERVATION_EXPIRED:' using errcode = 'P0001';
  end if;

  select metadata ->> 'size' as size_bytes, metadata ->> 'mimetype' as mime_type
  into v_object from storage.objects
  where bucket_id = v_reservation.storage_bucket and name = v_reservation.storage_key;
  if not found
     or nullif(v_object.size_bytes, '')::bigint is distinct from v_reservation.size_bytes
     or v_object.mime_type is distinct from v_reservation.mime_type then
    raise exception 'ATTACHMENT_STORAGE_OBJECT_MISMATCH:' using errcode = 'P0001';
  end if;

  insert into public.attachments (
    organization_id, entity_type, entity_id, file_name, mime_type, size_bytes,
    storage_bucket, storage_key, uploaded_by
  ) values (
    v_reservation.organization_id, v_reservation.entity_type, v_reservation.entity_id,
    v_reservation.file_name, v_reservation.mime_type, v_reservation.size_bytes,
    v_reservation.storage_bucket, v_reservation.storage_key, v_reservation.reserved_by
  ) returning id into v_attachment_id;

  update app.attachment_storage_reservations
  set status = 'committed', attachment_id = v_attachment_id, completed_at = now()
  where id = p_reservation_id;
  perform app.write_audit(v_reservation.organization_id, 'attachment.upload',
    'attachment', v_attachment_id, null,
    jsonb_build_object('file_name', v_reservation.file_name, 'size_bytes', v_reservation.size_bytes));
  return v_attachment_id;
end;
$$;

create or replace function public.abort_attachment_upload(p_reservation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_reservation app.attachment_storage_reservations%rowtype;
begin
  select * into v_reservation from app.attachment_storage_reservations
  where id = p_reservation_id for update;
  if not found then return true; end if;
  perform app.require_capability(v_reservation.organization_id, 'attachments.create');
  if v_reservation.reserved_by is distinct from auth.uid() and not app.is_service_context() then
    raise exception 'TENANT_ACCESS_DENIED: reservation owner mismatch' using errcode = '42501';
  end if;
  if v_reservation.status in ('aborted', 'expired', 'cleaned') then return true; end if;
  if v_reservation.status <> 'reserved' then return false; end if;
  update app.attachment_storage_reservations
  set status = 'aborted', completed_at = now() where id = p_reservation_id;
  return true;
end;
$$;

create or replace function public.begin_attachment_delete(p_attachment_id uuid)
returns table (reservation_id uuid, storage_bucket text, storage_key text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attachment public.attachments%rowtype;
  v_reservation_id uuid;
begin
  select * into v_attachment from public.attachments where id = p_attachment_id for update;
  if not found then return; end if;
  perform app.require_capability(v_attachment.organization_id, 'attachments.delete');

  insert into app.attachment_storage_reservations (
    organization_id, attachment_id, entity_type, entity_id, file_name, mime_type,
    size_bytes, storage_bucket, storage_key, reserved_by, status, expires_at,
    created_at, completed_at
  ) values (
    v_attachment.organization_id, v_attachment.id, v_attachment.entity_type,
    v_attachment.entity_id, v_attachment.file_name, v_attachment.mime_type,
    v_attachment.size_bytes, v_attachment.storage_bucket, v_attachment.storage_key,
    v_attachment.uploaded_by, 'committed', v_attachment.created_at,
    v_attachment.created_at, v_attachment.created_at
  ) on conflict on constraint attachment_storage_reservations_storage_bucket_storage_key_key
    do update set attachment_id = excluded.attachment_id
  returning id into v_reservation_id;

  delete from public.attachments where id = p_attachment_id;
  update app.attachment_storage_reservations
  set status = 'cleanup_pending', completed_at = now(), cleanup_claimed_at = null
  where id = v_reservation_id;
  perform app.write_audit(v_attachment.organization_id, 'attachment.delete',
    'attachment', p_attachment_id, to_jsonb(v_attachment), null);
  return query select v_reservation_id, v_attachment.storage_bucket, v_attachment.storage_key;
end;
$$;

create or replace function app.storage_delete_allowed(p_bucket text, p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from app.attachment_storage_reservations r
    where r.storage_bucket = p_bucket and r.storage_key = p_key
      and (
        (r.status in ('reserved', 'aborted', 'expired') and r.reserved_by = auth.uid()
          and app.has_capability(r.organization_id, 'attachments.create'))
        or (r.status = 'cleanup_pending'
          and app.has_capability(r.organization_id, 'attachments.delete'))
      )
  );
$$;

create or replace function public.claim_attachment_storage_cleanup(p_limit integer default 100)
returns table (reservation_id uuid, storage_bucket text, storage_key text)
language sql
security definer
set search_path = ''
as $$
  with candidates as (
    select r.id from app.attachment_storage_reservations r
    where ((r.status = 'reserved' and r.expires_at <= now())
       or r.status in ('aborted', 'expired', 'cleanup_pending'))
      and (r.cleanup_claimed_at is null or r.cleanup_claimed_at < now() - interval '10 minutes')
    order by r.created_at
    for update skip locked
    limit greatest(least(coalesce(p_limit, 100), 500), 1)
  ), claimed as (
    update app.attachment_storage_reservations r
    set status = case when r.status = 'reserved' then 'expired' else r.status end,
        cleanup_claimed_at = now(), cleanup_attempts = cleanup_attempts + 1
    from candidates c where r.id = c.id
    returning r.id, r.storage_bucket, r.storage_key
  )
  select id, storage_bucket, storage_key from claimed;
$$;

create or replace function public.complete_attachment_storage_cleanup(
  p_reservation_id uuid, p_error text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update app.attachment_storage_reservations
  set status = case when p_error is null then 'cleaned' else status end,
      completed_at = case when p_error is null then now() else completed_at end,
      cleanup_claimed_at = null,
      last_cleanup_error = left(p_error, 1000)
  where id = p_reservation_id and status in ('aborted', 'expired', 'cleanup_pending', 'cleaned');
  return found;
end;
$$;

revoke insert, delete on public.attachments from authenticated;
drop policy if exists "attachments are created with attachments.create" on public.attachments;
drop policy if exists "attachments are deleted with attachments.delete" on public.attachments;

drop policy if exists "attachments upload within organization" on storage.objects;
create policy "attachments upload with reservation"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'attachments' and app.storage_upload_matches_reservation(bucket_id, name, metadata));

drop policy if exists "attachments delete within organization" on storage.objects;
create policy "attachments delete with reservation"
  on storage.objects for delete to authenticated
  using (bucket_id = 'attachments' and app.storage_delete_allowed(bucket_id, name));

revoke all on table app.attachment_storage_reservations from public, anon, authenticated;
revoke all on function app.attachment_entity_exists(uuid, text, uuid) from public, anon, authenticated;
revoke all on function app.storage_upload_matches_reservation(text, text, jsonb) from public, anon, authenticated;
revoke all on function app.storage_delete_allowed(text, text) from public, anon, authenticated;
grant execute on function app.storage_upload_matches_reservation(text, text, jsonb) to authenticated, service_role;
grant execute on function app.storage_delete_allowed(text, text) to authenticated, service_role;

revoke all on function public.reserve_attachment_upload(uuid, text, uuid, text, text, bigint, text) from public, anon;
revoke all on function public.commit_attachment_upload(uuid) from public, anon;
revoke all on function public.abort_attachment_upload(uuid) from public, anon;
revoke all on function public.begin_attachment_delete(uuid) from public, anon;
grant execute on function public.reserve_attachment_upload(uuid, text, uuid, text, text, bigint, text) to authenticated, service_role;
grant execute on function public.commit_attachment_upload(uuid) to authenticated, service_role;
grant execute on function public.abort_attachment_upload(uuid) to authenticated, service_role;
grant execute on function public.begin_attachment_delete(uuid) to authenticated, service_role;

revoke all on function public.claim_attachment_storage_cleanup(integer) from public, anon, authenticated;
revoke all on function public.complete_attachment_storage_cleanup(uuid, text) from public, anon, authenticated;
grant execute on function public.claim_attachment_storage_cleanup(integer) to service_role;
grant execute on function public.complete_attachment_storage_cleanup(uuid, text) to service_role;

do $$
declare v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname = 'ledger-suit-storage-cleanup';
  if v_job_id is not null then perform cron.unschedule(v_job_id); end if;
  perform cron.schedule(
    'ledger-suit-storage-cleanup', '*/10 * * * *',
    $job$
      select net.http_post(
        url := secrets.project_url || '/functions/v1/storage-cleanup',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || secrets.service_role_key),
        body := '{}'::jsonb
      )
      from (
        select max(decrypted_secret) filter (where name = 'ledger_suit_project_url') as project_url,
               max(decrypted_secret) filter (where name = 'ledger_suit_service_role_key') as service_role_key
        from vault.decrypted_secrets
      ) secrets
      where secrets.project_url is not null and secrets.service_role_key is not null;
    $job$
  );
end;
$$;
