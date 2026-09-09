-- Workspace-specific permission sets for the built-in roles. Owner remains a
-- product invariant and always receives every capability.

create table public.organization_system_roles (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  role public.organization_role not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, role),
  constraint organization_system_roles_owner_is_fixed check (role <> 'owner')
);

create trigger organization_system_roles_set_updated_at
  before update on public.organization_system_roles
  for each row execute function app.set_updated_at();

create table public.organization_system_role_capabilities (
  organization_id uuid not null,
  role public.organization_role not null,
  capability_key text not null references public.capabilities (key) on delete cascade,
  primary key (organization_id, role, capability_key),
  foreign key (organization_id, role)
    references public.organization_system_roles (organization_id, role)
    on delete cascade
);

alter table public.organization_system_roles enable row level security;
alter table public.organization_system_role_capabilities enable row level security;

create policy "organization system roles are visible to members"
  on public.organization_system_roles for select to authenticated
  using (app.is_org_member(organization_id));

create policy "organization system role capabilities are visible to members"
  on public.organization_system_role_capabilities for select to authenticated
  using (app.is_org_member(organization_id));

revoke all on public.organization_system_roles from public, anon, authenticated;
revoke all on public.organization_system_role_capabilities from public, anon, authenticated;
grant select on public.organization_system_roles to authenticated, service_role;
grant select on public.organization_system_role_capabilities to authenticated, service_role;

-- A workspace override wins when one exists. Without an override, built-in
-- roles continue to inherit the product defaults in role_capabilities.
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
    -- Owner is deliberately independent of editable defaults and overrides.
    select c.key
    from membership ms
    cross join public.capabilities c
    where ms.role_id is null and ms.role = 'owner'
    union
    -- Workspace-specific built-in role override.
    select rc.capability_key
    from membership ms
    join public.organization_system_roles sr
      on sr.organization_id = p_organization_id and sr.role = ms.role
    join public.organization_system_role_capabilities rc
      on rc.organization_id = sr.organization_id and rc.role = sr.role
    where ms.role_id is null and ms.role <> 'owner'
    union
    -- Product default when this workspace has not customized the role.
    select rc.capability_key
    from membership ms
    join public.role_capabilities rc
      on rc.role = ms.role and rc.role_id is null
    where ms.role_id is null
      and ms.role <> 'owner'
      and not exists (
        select 1 from public.organization_system_roles sr
        where sr.organization_id = p_organization_id and sr.role = ms.role
      )
    union
    -- Workspace-defined custom role.
    select rc.capability_key
    from membership ms
    join public.role_capabilities rc on rc.role_id = ms.role_id
    where ms.role_id is not null
    union
    select unnest(ms.granted_capabilities) from membership ms
  )
  select coalesce(array_agg(distinct e.key), '{}')
  from effective e
  where exists (
    select 1 from membership ms
    where ms.role_id is null and ms.role = 'owner'
  ) or not exists (
    select 1 from membership ms
    where e.key = any (ms.revoked_capabilities)
  );
$$;

create or replace function public.update_organization_system_role(
  p_organization_id uuid,
  p_role public.organization_role,
  p_capabilities text[]
)
returns public.organization_role
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unknown text[];
  v_before text[];
begin
  perform app.require_capability(p_organization_id, 'members.update');

  if p_role is null or p_role = 'owner' then
    raise exception 'INVALID_ROLE: owner permissions cannot be changed'
      using errcode = '22023';
  end if;
  if p_capabilities is null or cardinality(p_capabilities) = 0 then
    raise exception 'INVALID_ROLE: select at least one permission'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct requested), '{}') into v_unknown
  from unnest(p_capabilities) requested
  where not exists (
    select 1 from public.capabilities c where c.key = requested
  );
  if cardinality(v_unknown) > 0 then
    raise exception 'INVALID_ROLE: unknown capabilities' using errcode = '22023';
  end if;

  select coalesce(
    (
      select array_agg(rc.capability_key order by rc.capability_key)
      from public.organization_system_role_capabilities rc
      where rc.organization_id = p_organization_id and rc.role = p_role
    ),
    (
      select array_agg(rc.capability_key order by rc.capability_key)
      from public.role_capabilities rc
      where rc.role = p_role and rc.role_id is null
    ),
    '{}'
  ) into v_before;

  insert into public.organization_system_roles (organization_id, role)
  values (p_organization_id, p_role)
  on conflict (organization_id, role) do update set updated_at = now();

  perform 1 from public.organization_system_roles sr
  where sr.organization_id = p_organization_id and sr.role = p_role
  for update;

  delete from public.organization_system_role_capabilities rc
  where rc.organization_id = p_organization_id and rc.role = p_role;

  insert into public.organization_system_role_capabilities (
    organization_id, role, capability_key
  )
  select p_organization_id, p_role, capability
  from (select distinct unnest(p_capabilities) as capability) picked;

  perform app.write_audit(
    p_organization_id,
    'system_role.updated',
    'organization_system_role',
    null,
    jsonb_build_object('role', p_role, 'capabilities', v_before),
    jsonb_build_object('role', p_role, 'capabilities', p_capabilities)
  );

  return p_role;
end;
$$;

revoke all on function public.update_organization_system_role(
  uuid, public.organization_role, text[]
) from public, anon;
grant execute on function public.update_organization_system_role(
  uuid, public.organization_role, text[]
) to authenticated, service_role;
