-- Ledger Suit — 04. Organization membership and invitations
--
-- Membership is the only thing that grants access to a tenant. Knowing an
-- organization UUID must never be sufficient.

create type public.organization_role as enum (
  'owner',
  'admin',
  'accountant',
  'data_entry',
  'viewer'
);

create type public.membership_status as enum (
  'active',
  'suspended'
);

create type public.invitation_status as enum (
  'pending',
  'accepted',
  'revoked',
  'expired'
);

create table if not exists public.organization_members (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references public.organizations (id) on delete cascade,
  user_id             uuid not null references public.profiles (id) on delete cascade,
  role                public.organization_role not null default 'viewer',
  status              public.membership_status not null default 'active',
  -- Per-member capability overrides layered on top of the role defaults.
  -- Kept as arrays rather than a join table because the set is small and is
  -- read on every authorization check.
  granted_capabilities text[] not null default '{}',
  revoked_capabilities text[] not null default '{}',
  invited_by          uuid references public.profiles (id) on delete set null,
  joined_at           timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint organization_members_unique unique (organization_id, user_id)
);

comment on table public.organization_members is
  'Join table between profiles and organizations. Source of truth for tenant '
  'authorization. One active row per (organization, user).';
comment on column public.organization_members.granted_capabilities is
  'Capabilities added on top of the role defaults for this specific member.';
comment on column public.organization_members.revoked_capabilities is
  'Capabilities removed from the role defaults. Takes precedence over grants.';

create index if not exists organization_members_org_user_idx
  on public.organization_members (organization_id, user_id);
create index if not exists organization_members_user_idx
  on public.organization_members (user_id) where status = 'active';

-- Tenant-safe composite target for child tables.
create unique index if not exists organization_members_id_org_key
  on public.organization_members (id, organization_id);

create trigger organization_members_set_updated_at
  before update on public.organization_members
  for each row execute function app.set_updated_at();

alter table public.organization_members enable row level security;

-- ---------------------------------------------------------------------------
-- An organization must always retain at least one active owner
-- ---------------------------------------------------------------------------
create or replace function app.guard_last_owner()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  -- OLD is assigned for both UPDATE and DELETE; NEW is not, so it must not be
  -- touched before the operation is known.
  v_org uuid := old.organization_id;
  v_remaining int;
begin
  -- The guard only fires when an active owner stops being one.
  if old.role <> 'owner' or old.status <> 'active' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.role = 'owner' and new.status = 'active' then
      return new;
    end if;
  end if;

  select count(*) into v_remaining
  from public.organization_members m
  where m.organization_id = v_org
    and m.role = 'owner'
    and m.status = 'active'
    and m.id <> old.id;

  if v_remaining = 0
     -- Allow the cascade when the organization itself is being deleted.
     and exists (select 1 from public.organizations o where o.id = v_org) then
    raise exception 'LAST_OWNER_REQUIRED: an organization must keep one active owner'
      using errcode = '23514';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create trigger organization_members_guard_last_owner
  before update or delete on public.organization_members
  for each row execute function app.guard_last_owner();

-- ---------------------------------------------------------------------------
-- Invitations
-- ---------------------------------------------------------------------------
create table if not exists public.organization_invitations (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  email            extensions.citext not null,
  role             public.organization_role not null default 'viewer',
  status           public.invitation_status not null default 'pending',
  -- Only the digest is stored; the raw token is returned once, to the inviter.
  token_hash       text not null,
  invited_by       uuid references public.profiles (id) on delete set null,
  accepted_by      uuid references public.profiles (id) on delete set null,
  expires_at       timestamptz not null default (now() + interval '14 days'),
  accepted_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint organization_invitations_role_not_owner check (role <> 'owner'),
  constraint organization_invitations_email_format check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

comment on table public.organization_invitations is
  'Pending membership invitations. The raw token is never persisted.';

create unique index if not exists organization_invitations_pending_key
  on public.organization_invitations (organization_id, email)
  where status = 'pending';
create unique index if not exists organization_invitations_token_key
  on public.organization_invitations (token_hash);
create index if not exists organization_invitations_email_idx
  on public.organization_invitations (email) where status = 'pending';

create trigger organization_invitations_set_updated_at
  before update on public.organization_invitations
  for each row execute function app.set_updated_at();

alter table public.organization_invitations enable row level security;
