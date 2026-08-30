-- Ledger Suit — 17. Attachments and tenant-scoped storage
--
-- Files live in a private storage bucket under a path that starts with the
-- organization id:
--
--     attachments/<organization_id>/<entity_type>/<entity_id>/<uuid>.<ext>
--
-- Storage policies check membership of that first path segment, so one tenant's
-- object key is unusable to another even if it leaks.

create table if not exists public.attachments (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  entity_type     text not null,
  entity_id       uuid not null,
  file_name       text not null,
  mime_type       text not null,
  size_bytes      bigint not null,
  storage_bucket  text not null default 'attachments',
  storage_key     text not null,
  checksum        text,
  uploaded_by     uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),

  constraint attachments_size_positive check (size_bytes > 0 and size_bytes <= 26214400),
  constraint attachments_entity_type_allowed check (
    entity_type in ('transaction', 'commitment', 'account', 'organization', 'import')
  ),
  constraint attachments_mime_allowed check (
    mime_type in ('application/pdf', 'image/png', 'image/jpeg', 'image/webp')
  ),
  constraint attachments_file_name_length check (char_length(file_name) between 1 and 255),
  -- The storage key must sit under this organization's prefix. Without this a
  -- valid row could point at another tenant's object.
  constraint attachments_key_is_tenant_scoped check (
    storage_key like organization_id::text || '/%'
  )
);

comment on table public.attachments is
  'Metadata for files in the private attachments bucket. storage_key is '
  'constrained to the owning organization prefix.';
comment on constraint attachments_size_positive on public.attachments is
  'Non-negative and capped at 25 MiB.';

create unique index if not exists attachments_storage_key_key
  on public.attachments (storage_bucket, storage_key);
create index if not exists attachments_org_entity_idx
  on public.attachments (organization_id, entity_type, entity_id);
create index if not exists attachments_org_created_idx
  on public.attachments (organization_id, created_at desc);
create index if not exists attachments_uploaded_by_idx
  on public.attachments (uploaded_by);

alter table public.attachments enable row level security;

-- ---------------------------------------------------------------------------
-- Private bucket
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'attachments', 'attachments', false, 26214400,
  array['application/pdf', 'image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Safe UUID parse: a malformed first path segment must return NULL, not abort
-- the policy evaluation.
create or replace function app.try_uuid(p_text text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return p_text::uuid;
exception when others then
  return null;
end;
$$;

grant execute on function app.try_uuid(text) to authenticated, anon, service_role;

drop policy if exists "attachments read within organization" on storage.objects;
create policy "attachments read within organization"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'attachments'
    and app.is_org_member(app.try_uuid((storage.foldername(name))[1]))
    and app.has_capability(app.try_uuid((storage.foldername(name))[1]), 'attachments.read')
  );

drop policy if exists "attachments upload within organization" on storage.objects;
create policy "attachments upload within organization"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'attachments'
    and app.has_capability(app.try_uuid((storage.foldername(name))[1]), 'attachments.create')
  );

drop policy if exists "attachments delete within organization" on storage.objects;
create policy "attachments delete within organization"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'attachments'
    and app.has_capability(app.try_uuid((storage.foldername(name))[1]), 'attachments.delete')
  );

-- Deliberately no UPDATE policy: an uploaded document is replaced by a new
-- object, never mutated in place.
