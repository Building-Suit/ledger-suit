-- Ledger Suit — 05. Capability model and authorization helpers
--
-- All authorization in this database funnels through app.has_capability().
-- RLS policies and RPCs call it; nothing hard-codes a role name.
--
-- Every helper is SECURITY DEFINER with a pinned empty search_path, resolves
-- the caller from auth.uid() and never trusts an organization id supplied by
-- the client beyond using it as a lookup key.

create table if not exists public.capabilities (
  key         text primary key,
  domain      text not null,
  description text not null
);

comment on table public.capabilities is
  'Catalogue of every permission the product understands. Reference data.';

alter table public.capabilities enable row level security;

insert into public.capabilities (key, domain, description) values
  ('organization.read',              'organization', 'View organization profile and settings'),
  ('organization.update',            'organization', 'Edit organization profile and settings'),
  ('organization.archive',           'organization', 'Archive the organization'),
  ('organization.transfer_ownership','organization', 'Transfer ownership to another member'),

  ('members.read',                   'members',      'List organization members'),
  ('members.invite',                 'members',      'Invite new members'),
  ('members.update',                 'members',      'Change member roles and capabilities'),
  ('members.remove',                 'members',      'Remove members'),

  ('accounts.read',                  'accounts',     'View the chart of accounts'),
  ('accounts.create',                'accounts',     'Create accounts'),
  ('accounts.update',                'accounts',     'Edit accounts'),
  ('accounts.archive',               'accounts',     'Archive accounts'),

  ('categories.read',                'categories',   'View categories'),
  ('categories.manage',              'categories',   'Create, edit and archive categories'),

  ('counterparties.read',            'counterparties','View counterparties'),
  ('counterparties.manage',          'counterparties','Create and edit counterparties'),

  ('tags.read',                      'tags',         'View tags'),
  ('tags.manage',                    'tags',         'Create and edit tags'),

  ('transactions.read',              'transactions', 'View transactions and ledger entries'),
  ('transactions.create',            'transactions', 'Create draft transactions'),
  ('transactions.update_draft',      'transactions', 'Edit draft transactions'),
  ('transactions.post',              'transactions', 'Post transactions to the ledger'),
  ('transactions.void',              'transactions', 'Void unposted transactions'),
  ('transactions.reverse',           'transactions', 'Reverse posted transactions'),
  ('transactions.adjust',            'transactions', 'Create manual journal adjustments'),

  ('commitments.read',               'commitments',  'View commitments'),
  ('commitments.create',             'commitments',  'Create commitments'),
  ('commitments.update',             'commitments',  'Edit commitments'),
  ('commitments.settle',             'commitments',  'Settle commitments into the ledger'),

  ('recurring.read',                 'recurring',    'View recurring rules'),
  ('recurring.manage',               'recurring',    'Create and edit recurring rules'),

  ('attachments.read',               'attachments',  'Download attachments'),
  ('attachments.create',             'attachments',  'Upload attachments'),
  ('attachments.delete',             'attachments',  'Delete attachments'),

  ('reports.read',                   'reports',      'View financial reports'),
  ('reports.export',                 'reports',      'Export reports'),

  ('imports.create',                 'imports',      'Import data from CSV/XLSX'),
  ('exports.create',                 'exports',      'Export organization data'),

  ('audit.read',                     'audit',        'Read the audit log'),

  ('books.override_lock',            'books',        'Post into a locked accounting period'),

  ('billing.read',                   'billing',      'View subscription and invoices'),
  ('billing.manage',                 'billing',      'Start, change or cancel the subscription')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Role → capability defaults
-- ---------------------------------------------------------------------------
create table if not exists public.role_capabilities (
  role           public.organization_role not null,
  capability_key text not null references public.capabilities (key) on delete cascade,
  primary key (role, capability_key)
);

comment on table public.role_capabilities is
  'Default capability set per role. Per-member overrides live on '
  'organization_members.granted_capabilities / revoked_capabilities.';

alter table public.role_capabilities enable row level security;

-- owner: everything
insert into public.role_capabilities (role, capability_key)
select 'owner', key from public.capabilities
on conflict do nothing;

-- admin: everything except ownership transfer, archiving and billing changes
insert into public.role_capabilities (role, capability_key)
select 'admin', key from public.capabilities
where key not in (
  'organization.transfer_ownership',
  'organization.archive',
  'billing.manage'
)
on conflict do nothing;

-- accountant: full financial control, no member management, no billing changes
insert into public.role_capabilities (role, capability_key)
values
  ('accountant', 'organization.read'),
  ('accountant', 'members.read'),
  ('accountant', 'accounts.read'),
  ('accountant', 'accounts.create'),
  ('accountant', 'accounts.update'),
  ('accountant', 'accounts.archive'),
  ('accountant', 'categories.read'),
  ('accountant', 'categories.manage'),
  ('accountant', 'counterparties.read'),
  ('accountant', 'counterparties.manage'),
  ('accountant', 'tags.read'),
  ('accountant', 'tags.manage'),
  ('accountant', 'transactions.read'),
  ('accountant', 'transactions.create'),
  ('accountant', 'transactions.update_draft'),
  ('accountant', 'transactions.post'),
  ('accountant', 'transactions.void'),
  ('accountant', 'transactions.reverse'),
  ('accountant', 'transactions.adjust'),
  ('accountant', 'commitments.read'),
  ('accountant', 'commitments.create'),
  ('accountant', 'commitments.update'),
  ('accountant', 'commitments.settle'),
  ('accountant', 'recurring.read'),
  ('accountant', 'recurring.manage'),
  ('accountant', 'attachments.read'),
  ('accountant', 'attachments.create'),
  ('accountant', 'attachments.delete'),
  ('accountant', 'reports.read'),
  ('accountant', 'reports.export'),
  ('accountant', 'imports.create'),
  ('accountant', 'exports.create'),
  ('accountant', 'audit.read'),
  ('accountant', 'books.override_lock'),
  ('accountant', 'billing.read')
on conflict do nothing;

-- data_entry: day-to-day bookkeeping, no corrections, no manual journals
insert into public.role_capabilities (role, capability_key)
values
  ('data_entry', 'organization.read'),
  ('data_entry', 'members.read'),
  ('data_entry', 'accounts.read'),
  ('data_entry', 'categories.read'),
  ('data_entry', 'counterparties.read'),
  ('data_entry', 'counterparties.manage'),
  ('data_entry', 'tags.read'),
  ('data_entry', 'transactions.read'),
  ('data_entry', 'transactions.create'),
  ('data_entry', 'transactions.update_draft'),
  ('data_entry', 'transactions.post'),
  ('data_entry', 'transactions.void'),
  ('data_entry', 'commitments.read'),
  ('data_entry', 'commitments.create'),
  ('data_entry', 'commitments.update'),
  ('data_entry', 'attachments.read'),
  ('data_entry', 'attachments.create'),
  ('data_entry', 'reports.read')
on conflict do nothing;

-- viewer: read-only
insert into public.role_capabilities (role, capability_key)
values
  ('viewer', 'organization.read'),
  ('viewer', 'members.read'),
  ('viewer', 'accounts.read'),
  ('viewer', 'categories.read'),
  ('viewer', 'counterparties.read'),
  ('viewer', 'tags.read'),
  ('viewer', 'transactions.read'),
  ('viewer', 'commitments.read'),
  ('viewer', 'recurring.read'),
  ('viewer', 'attachments.read'),
  ('viewer', 'reports.read')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- True for trusted server-side contexts: a service_role JWT (edge functions,
-- background jobs) or a session that has explicitly opted in via
--     set local app.bypass_authz = 'on';
-- which only a superuser/seed script would do.
--
-- Note what is deliberately NOT used here: current_user. Inside a SECURITY
-- DEFINER function current_user becomes the function owner (postgres), so a
-- current_user check would silently authorize every capability test in this
-- file. session_user is likewise avoided so that pgTAP tests, which run as
-- postgres while impersonating an application role, exercise the real rules.
create or replace function app.is_service_context()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role'
      or coalesce(current_setting('app.bypass_authz', true), '') = 'on';
$$;

create or replace function app.is_org_member(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.is_service_context()
      or exists (
           select 1
           from public.organization_members m
           where m.organization_id = p_organization_id
             and m.user_id = auth.uid()
             and m.status = 'active'
         );
$$;

comment on function app.is_org_member(uuid) is
  'Membership test for the current caller. The organization id is only ever '
  'used as a lookup key; it never grants access on its own.';

create or replace function app.member_role(p_organization_id uuid)
returns public.organization_role
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
  from public.organization_members m
  where m.organization_id = p_organization_id
    and m.user_id = auth.uid()
    and m.status = 'active';
$$;

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
    select m.role, m.granted_capabilities, m.revoked_capabilities
    from public.organization_members m
    where m.organization_id = p_organization_id
      and m.user_id = coalesce(p_user_id, auth.uid())
      and m.status = 'active'
  ),
  effective as (
    select rc.capability_key as key
    from membership ms
    join public.role_capabilities rc on rc.role = ms.role
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

comment on function app.capabilities_for(uuid, uuid) is
  'Effective capability set: role defaults + per-member grants - per-member '
  'revocations. Revocation always wins.';

create or replace function app.has_capability(
  p_organization_id uuid,
  p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.is_service_context()
      or p_capability = any (app.capabilities_for(p_organization_id));
$$;

comment on function app.has_capability(uuid, text) is
  'Single authorization predicate used by every RLS policy and RPC.';

create or replace function app.require_capability(
  p_organization_id uuid,
  p_capability text
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_organization_id is null then
    raise exception 'TENANT_ACCESS_DENIED: organization is required'
      using errcode = '42501';
  end if;

  if not app.is_org_member(p_organization_id) then
    -- Deliberately identical to the capability failure below: a non-member
    -- must not be able to distinguish "no such organization" from
    -- "organization exists but you are not in it".
    raise exception 'TENANT_ACCESS_DENIED: not a member of this organization'
      using errcode = '42501';
  end if;

  if not app.has_capability(p_organization_id, p_capability) then
    raise exception 'INSUFFICIENT_PERMISSION: % is required', p_capability
      using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Books lock
-- ---------------------------------------------------------------------------
create or replace function app.assert_books_open(
  p_organization_id uuid,
  p_date date
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_locked_until date;
begin
  select s.books_locked_until into v_locked_until
  from public.organization_settings s
  where s.organization_id = p_organization_id;

  if v_locked_until is not null
     and p_date <= v_locked_until
     and not app.has_capability(p_organization_id, 'books.override_lock') then
    raise exception 'BOOKS_LOCKED: books are locked through %', v_locked_until
      using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Client-facing convenience RPCs
-- ---------------------------------------------------------------------------
create or replace function public.my_capabilities(p_organization_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when app.is_org_member(p_organization_id) then app.capabilities_for(p_organization_id)
    else '{}'::text[]
  end;
$$;

comment on function public.my_capabilities(uuid) is
  'Capability set of the calling user for one organization. Returns an empty '
  'array for non-members rather than raising, so the UI can degrade quietly.';

revoke all on function public.my_capabilities(uuid) from public, anon;
grant execute on function public.my_capabilities(uuid) to authenticated, service_role;

-- RLS policy expressions are evaluated as the querying role, so `authenticated`
-- needs USAGE on the private schema to call the helpers. PostgREST still cannot
-- reach anything in `app` because the schema is not in its exposed-schema list.
grant usage on schema app to authenticated, anon;

grant execute on function app.is_org_member(uuid) to authenticated, service_role;
grant execute on function app.has_capability(uuid, text) to authenticated, service_role;
grant execute on function app.capabilities_for(uuid, uuid) to authenticated, service_role;
grant execute on function app.member_role(uuid) to authenticated, service_role;
grant execute on function app.require_capability(uuid, text) to authenticated, service_role;
grant execute on function app.assert_books_open(uuid, date) to authenticated, service_role;
grant execute on function app.is_service_context() to authenticated, service_role;
grant execute on function app.currency_minor_unit(char) to authenticated, service_role;
grant execute on function app.convert_minor(bigint, char, char, numeric) to authenticated, service_role;
