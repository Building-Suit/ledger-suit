-- Ledger Suit — organization-defined roles (custom roles)
--
-- System roles stay the public.organization_role enum. Custom roles live in
-- public.organization_roles with bilingual display names; their permission
-- sets are public.role_capabilities rows keyed by role_id. A member on a
-- custom role keeps role = 'viewer' as the enum fallback (used only by
-- owner-only guards) while role_id points at the real definition.
--
-- The capability catalogue becomes bilingual: description_ar is the readable
-- Arabic name shown alongside the English description.

-- ---------------------------------------------------------------------------
-- Bilingual capability catalogue
-- ---------------------------------------------------------------------------
alter table public.capabilities add column if not exists description_ar text not null default '';

update public.capabilities set description_ar = v.ar
from (values
  ('organization.read',               'عرض ملف المؤسسة والإعدادات'),
  ('organization.update',             'تعديل ملف المؤسسة والإعدادات'),
  ('organization.archive',            'أرشفة المؤسسة'),
  ('organization.transfer_ownership', 'نقل الملكية إلى عضو آخر'),
  ('members.read',                    'عرض أعضاء المؤسسة'),
  ('members.invite',                  'دعوة أعضاء جدد'),
  ('members.update',                  'تغيير أدوار الأعضاء والصلاحيات'),
  ('members.remove',                  'إزالة الأعضاء'),
  ('accounts.read',                   'عرض دليل الحسابات'),
  ('accounts.create',                 'إنشاء حسابات'),
  ('accounts.update',                 'تعديل الحسابات'),
  ('accounts.archive',                'أرشفة الحسابات'),
  ('categories.read',                 'عرض الفئات'),
  ('categories.manage',               'إنشاء وتعديل وأرشفة الفئات'),
  ('counterparties.read',             'عرض الأطراف'),
  ('counterparties.manage',           'إنشاء وتعديل الأطراف'),
  ('tags.read',                       'عرض الوسوم'),
  ('tags.manage',                     'إنشاء وتعديل الوسوم'),
  ('transactions.read',               'عرض المعاملات وقيود اليومية'),
  ('transactions.create',             'إنشاء معاملات مسودة'),
  ('transactions.update_draft',       'تعديل المعاملات المسودة'),
  ('transactions.post',               'ترحيل المعاملات إلى دفتر الأستاذ'),
  ('transactions.void',               'إلغاء المعاملات غير المرحّلة'),
  ('transactions.reverse',            'عكس المعاملات المرحّلة'),
  ('transactions.adjust',             'إنشاء قيود تسوية يدوية'),
  ('commitments.read',                'عرض الالتزامات'),
  ('commitments.create',              'إنشاء التزامات'),
  ('commitments.update',              'تعديل الالتزامات'),
  ('commitments.settle',              'تسوية الالتزامات في دفتر الأستاذ'),
  ('recurring.read',                  'عرض القواعد المتكررة'),
  ('recurring.manage',                'إنشاء وتعديل القواعد المتكررة'),
  ('attachments.read',                'تنزيل المرفقات'),
  ('attachments.create',              'رفع المرفقات'),
  ('attachments.delete',              'حذف المرفقات'),
  ('reports.read',                    'عرض التقارير المالية'),
  ('reports.export',                  'تصدير التقارير'),
  ('imports.create',                  'استيراد البيانات من CSV/XLSX'),
  ('exports.create',                  'تصدير بيانات المؤسسة'),
  ('audit.read',                      'عرض سجل التدقيق'),
  ('books.override_lock',             'الترحيل في فترة محاسبية مقفلة'),
  ('billing.read',                    'عرض الاشتراك والفواتير'),
  ('billing.manage',                  'بدء الاشتراك أو تغييره أو إلغائه')
) as v(key, ar)
where public.capabilities.key = v.key;

-- ---------------------------------------------------------------------------
-- Custom role definitions
-- ---------------------------------------------------------------------------
create table if not exists public.organization_roles (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  key             text not null,
  name_en         text not null,
  name_ar         text not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organization_id, key)
);

comment on table public.organization_roles is
  'Workspace-defined roles. System roles stay in the organization_role enum; '
  'every row here is a custom role created by the workspace.';

create trigger organization_roles_set_updated_at
  before update on public.organization_roles
  for each row execute function app.set_updated_at();

alter table public.organization_roles enable row level security;

create policy "organization roles are visible to members"
  on public.organization_roles for select to authenticated
  using (app.is_org_member(organization_id));

grant select on public.organization_roles to authenticated;

-- ---------------------------------------------------------------------------
-- Role-capability and membership links
-- ---------------------------------------------------------------------------
alter table public.role_capabilities
  add column if not exists role_id uuid references public.organization_roles (id) on delete cascade;

-- Custom-role permission rows carry only role_id; the enum column becomes
-- optional so both kinds of row can live in this table.
alter table public.role_capabilities alter column role drop not null;

alter table public.organization_members
  add column if not exists role_id uuid references public.organization_roles (id) on delete set null;

alter table public.organization_invitations
  add column if not exists role_id uuid references public.organization_roles (id) on delete set null;

-- ---------------------------------------------------------------------------
-- Effective capabilities: enum roles use their enum defaults, custom roles use
-- exactly the capability set chosen for them — no hidden viewer baseline.
-- ---------------------------------------------------------------------------
create or replace function app.capabilities_for(
  p_organization_id uuid,
  p_user_id uuid default null
)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  with membership as (
    select m.role, m.role_id, m.granted_capabilities, m.revoked_capabilities
    from public.organization_members m
    where m.organization_id = p_organization_id
      and m.user_id = coalesce(p_user_id, auth.uid())
      and m.status = 'active'
  ),
  effective as (
    select rc.capability_key as key
    from membership ms
    join public.role_capabilities rc
      on (ms.role_id is null and rc.role = ms.role)
      or (ms.role_id is not null and rc.role_id = ms.role_id)
    union
    select unnest(ms.granted_capabilities) from membership ms
  )
  select coalesce(array_agg(distinct e.key), '{}')
  from effective e
  where not exists (
    select 1 from membership ms
    where e.key = any (ms.revoked_capabilities)
  );
$$;

-- ---------------------------------------------------------------------------
-- Custom role lifecycle. Gated behind members.update; every mutation is
-- audited. Writes are RPC-only (no insert/update/delete policies above).
-- ---------------------------------------------------------------------------
create or replace function public.create_organization_role(
  p_organization_id uuid,
  p_key text,
  p_name_en text,
  p_name_ar text,
  p_capabilities text[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role_id uuid;
  v_unknown text[];
  v_key text := lower(btrim(coalesce(p_key, '')));
begin
  perform app.require_capability(p_organization_id, 'members.update');

  if v_key !~ '^[a-z][a-z0-9_]{1,39}$'
     or v_key in ('owner', 'admin', 'accountant', 'data_entry', 'viewer') then
    raise exception 'INVALID_ROLE: role key is reserved or malformed'
      using errcode = '22023';
  end if;
  if coalesce(btrim(p_name_en), '') = '' or coalesce(btrim(p_name_ar), '') = ''
     or char_length(btrim(p_name_en)) > 80 or char_length(btrim(p_name_ar)) > 80 then
    raise exception 'INVALID_ROLE: both an English and an Arabic name are required'
      using errcode = '22023';
  end if;
  if p_capabilities is null or cardinality(p_capabilities) = 0 then
    raise exception 'INVALID_ROLE: select at least one permission'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct requested), '{}') into v_unknown
  from unnest(p_capabilities) requested
  where not exists (select 1 from public.capabilities c where c.key = requested);
  if cardinality(v_unknown) > 0 then
    raise exception 'INVALID_ROLE: unknown capabilities' using errcode = '22023';
  end if;

  insert into public.organization_roles (organization_id, key, name_en, name_ar)
  values (p_organization_id, v_key, btrim(p_name_en), btrim(p_name_ar))
  returning id into v_role_id;

  insert into public.role_capabilities (role_id, capability_key)
  select v_role_id, capability from (select distinct unnest(p_capabilities) as capability) picked;

  perform app.write_audit(
    p_organization_id, 'role.created', 'organization_role', v_role_id,
    null,
    jsonb_build_object('key', v_key, 'name_en', btrim(p_name_en), 'name_ar', btrim(p_name_ar),
                       'capabilities', p_capabilities)
  );
  return v_role_id;
end;
$$;

create or replace function public.update_organization_role(
  p_role_id uuid,
  p_name_en text,
  p_name_ar text,
  p_capabilities text[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.organization_roles%rowtype;
  v_unknown text[];
begin
  select * into v_role from public.organization_roles r where r.id = p_role_id for update;
  if not found then
    raise exception 'ROLE_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform app.require_capability(v_role.organization_id, 'members.update');

  if coalesce(btrim(p_name_en), '') = '' or coalesce(btrim(p_name_ar), '') = ''
     or char_length(btrim(p_name_en)) > 80 or char_length(btrim(p_name_ar)) > 80 then
    raise exception 'INVALID_ROLE: both an English and an Arabic name are required'
      using errcode = '22023';
  end if;
  if p_capabilities is null or cardinality(p_capabilities) = 0 then
    raise exception 'INVALID_ROLE: select at least one permission'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct requested), '{}') into v_unknown
  from unnest(p_capabilities) requested
  where not exists (select 1 from public.capabilities c where c.key = requested);
  if cardinality(v_unknown) > 0 then
    raise exception 'INVALID_ROLE: unknown capabilities' using errcode = '22023';
  end if;

  update public.organization_roles
  set name_en = btrim(p_name_en), name_ar = btrim(p_name_ar)
  where id = p_role_id;

  delete from public.role_capabilities where role_id = p_role_id;
  insert into public.role_capabilities (role_id, capability_key)
  select p_role_id, capability from (select distinct unnest(p_capabilities) as capability) picked;

  perform app.write_audit(
    v_role.organization_id, 'role.updated', 'organization_role', p_role_id,
    jsonb_build_object('name_en', v_role.name_en, 'name_ar', v_role.name_ar),
    jsonb_build_object('name_en', btrim(p_name_en), 'name_ar', btrim(p_name_ar),
                       'capabilities', p_capabilities)
  );
  return p_role_id;
end;
$$;

create or replace function public.delete_organization_role(p_role_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.organization_roles%rowtype;
begin
  select * into v_role from public.organization_roles r where r.id = p_role_id for update;
  if not found then
    raise exception 'ROLE_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform app.require_capability(v_role.organization_id, 'members.update');

  if exists (select 1 from public.organization_members m where m.role_id = p_role_id)
     or exists (select 1 from public.organization_invitations i where i.role_id = p_role_id and i.status = 'pending') then
    raise exception 'ROLE_IN_USE: move members off this role before deleting it'
      using errcode = '22023';
  end if;

  delete from public.organization_roles where id = p_role_id;

  perform app.write_audit(
    v_role.organization_id, 'role.deleted', 'organization_role', p_role_id,
    jsonb_build_object('key', v_role.key, 'name_en', v_role.name_en, 'name_ar', v_role.name_ar),
    null
  );
  return p_role_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Invitations and membership: carry a custom role id end to end
-- ---------------------------------------------------------------------------
create or replace function public.create_organization_invitation(
  p_organization_id uuid,
  p_email text,
  p_role public.organization_role default 'viewer',
  p_role_id uuid default null
)
returns table (invitation_id uuid, invitation_token text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
begin
  perform app.require_capability(p_organization_id, 'members.invite');
  if p_role = 'owner' then
    raise exception 'INVALID_ROLE: owners cannot be invited directly' using errcode = '22023';
  end if;
  if p_role_id is not null and not exists (
    select 1 from public.organization_roles r
    where r.id = p_role_id and r.organization_id = p_organization_id
  ) then
    raise exception 'INVALID_ROLE: unknown role for this organization' using errcode = '22023';
  end if;
  if p_email is null or p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'INVALID_INPUT: a valid email is required' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.organization_members m
    join public.profiles p on p.id = m.user_id
    where m.organization_id = p_organization_id and p.email = p_email
  ) then
    raise exception 'DUPLICATE_MEMBERSHIP: this user is already a member' using errcode = '23505';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.organization_invitations (
    organization_id, email, role, role_id, token_hash, invited_by
  ) values (
    p_organization_id, lower(trim(p_email)), p_role, p_role_id,
    encode(extensions.digest(v_token, 'sha256'), 'hex'), auth.uid()
  )
  returning id into invitation_id;
  invitation_token := v_token;

  perform app.write_audit(
    p_organization_id, 'member.invited', 'organization_invitation', invitation_id,
    null, jsonb_build_object('email', lower(trim(p_email)), 'role', p_role, 'role_id', p_role_id)
  );
  return next;
end;
$$;

create or replace function public.manage_organization_member(
  p_member_id uuid,
  p_role public.organization_role,
  p_status public.membership_status,
  p_granted_capabilities text[] default '{}',
  p_revoked_capabilities text[] default '{}',
  p_role_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.organization_members%rowtype;
  v_actor_role public.organization_role;
  v_unknown text[];
begin
  select * into v_member
  from public.organization_members m
  where m.id = p_member_id
  for update;

  if not found then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform app.require_capability(v_member.organization_id, 'members.update');
  v_actor_role := app.member_role(v_member.organization_id);

  if v_member.user_id = auth.uid() and p_status = 'suspended' then
    raise exception 'INVALID_MEMBER_CHANGE: you cannot suspend yourself'
      using errcode = '22023';
  end if;
  if (v_member.role = 'owner' or p_role = 'owner') and v_actor_role <> 'owner' then
    raise exception 'INSUFFICIENT_PERMISSION: only an owner can manage owners'
      using errcode = '42501';
  end if;
  if p_role_id is not null then
    if not exists (
      select 1 from public.organization_roles r
      where r.id = p_role_id and r.organization_id = v_member.organization_id
    ) then
      raise exception 'INVALID_ROLE: unknown role for this organization'
        using errcode = '22023';
    end if;
    if v_member.role = 'owner' then
      raise exception 'INVALID_MEMBER_CHANGE: the owner role cannot be replaced'
        using errcode = '22023';
    end if;
  end if;
  if p_granted_capabilities && p_revoked_capabilities then
    raise exception 'INVALID_MEMBER_CHANGE: a capability cannot be both granted and revoked'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(requested), '{}') into v_unknown
  from (
    select distinct unnest(p_granted_capabilities || p_revoked_capabilities) requested
  ) requested
  where not exists (
    select 1 from public.capabilities c where c.key = requested.requested
  );
  if cardinality(v_unknown) > 0 then
    raise exception 'INVALID_MEMBER_CHANGE: unknown capabilities'
      using errcode = '22023';
  end if;

  update public.organization_members m
  set role = case when p_role_id is not null then 'viewer' else p_role end,
      role_id = p_role_id,
      status = p_status,
      granted_capabilities = coalesce(p_granted_capabilities, '{}'),
      revoked_capabilities = coalesce(p_revoked_capabilities, '{}')
  where m.id = p_member_id;

  perform app.write_audit(
    v_member.organization_id,
    'member.updated',
    'organization_member',
    p_member_id,
    jsonb_build_object(
      'role', v_member.role,
      'role_id', v_member.role_id,
      'status', v_member.status,
      'granted_capabilities', v_member.granted_capabilities,
      'revoked_capabilities', v_member.revoked_capabilities
    ),
    jsonb_build_object(
      'role', p_role,
      'role_id', p_role_id,
      'status', p_status,
      'granted_capabilities', p_granted_capabilities,
      'revoked_capabilities', p_revoked_capabilities
    )
  );
  return p_member_id;
end;
$$;

create or replace function public.accept_organization_invitation(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv public.organization_invitations%rowtype;
  v_email extensions.citext;
begin
  if auth.uid() is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  select p.email into v_email from public.profiles p where p.id = auth.uid();
  select * into v_inv
  from public.organization_invitations i
  where i.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
  for update;

  if not found or v_inv.status <> 'pending' or v_inv.expires_at <= now()
     or v_inv.email <> v_email then
    raise exception 'INVALID_INVITATION: invitation is invalid or expired'
      using errcode = '42501';
  end if;

  insert into public.organization_members (
    organization_id, user_id, role, role_id, invited_by
  ) values (v_inv.organization_id, auth.uid(), v_inv.role, v_inv.role_id, v_inv.invited_by)
  on conflict (organization_id, user_id) do nothing;

  update public.organization_invitations i
  set status = 'accepted', accepted_by = auth.uid(), accepted_at = now()
  where i.id = v_inv.id;

  perform app.write_audit(
    v_inv.organization_id, 'member.invitation_accepted', 'organization_invitation', v_inv.id,
    null, jsonb_build_object('user_id', auth.uid(), 'role', v_inv.role, 'role_id', v_inv.role_id)
  );
  return v_inv.organization_id;
end;
$$;

create or replace function public.preview_organization_invitation(p_token text)
returns table (
  email text,
  organization_name text,
  role public.organization_role,
  role_key text,
  role_name_en text,
  role_name_ar text,
  inviter_name text,
  inviter_job_title text,
  expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_token is null or char_length(p_token) <> 64 then
    raise exception 'INVALID_INVITATION: invitation is invalid or expired'
      using errcode = '42501';
  end if;

  return query
  select
    i.email::text,
    o.name,
    i.role,
    r.key,
    r.name_en,
    r.name_ar,
    coalesce(nullif(trim(p.full_name), ''), 'A Ledger Suit administrator'),
    nullif(trim(p.job_title), ''),
    i.expires_at
  from public.organization_invitations i
  join public.organizations o on o.id = i.organization_id
  left join public.organization_roles r on r.id = i.role_id
  left join public.profiles p on p.id = i.invited_by
  where i.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and i.status = 'pending'
    and i.expires_at > now();

  if not found then
    raise exception 'INVALID_INVITATION: invitation is invalid or expired'
      using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Execute permissions
-- ---------------------------------------------------------------------------
revoke all on function public.create_organization_role(uuid, text, text, text, text[]) from public, anon;
grant execute on function public.create_organization_role(uuid, text, text, text, text[]) to authenticated, service_role;

revoke all on function public.update_organization_role(uuid, text, text, text[]) from public, anon;
grant execute on function public.update_organization_role(uuid, text, text, text[]) to authenticated, service_role;

revoke all on function public.delete_organization_role(uuid) from public, anon;
grant execute on function public.delete_organization_role(uuid) to authenticated, service_role;

revoke all on function public.create_organization_invitation(uuid, text, public.organization_role, uuid) from public, anon;
grant execute on function public.create_organization_invitation(uuid, text, public.organization_role, uuid) to authenticated, service_role;

revoke all on function public.manage_organization_member(uuid, public.organization_role, public.membership_status, text[], text[], uuid) from public, anon;
grant execute on function public.manage_organization_member(uuid, public.organization_role, public.membership_status, text[], text[], uuid) to authenticated, service_role;

revoke all on function public.preview_organization_invitation(text) from public;
grant execute on function public.preview_organization_invitation(text) to anon, authenticated, service_role;
