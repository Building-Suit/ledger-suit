-- Only workspace-defined rows consume custom-role capacity. Organization-level
-- overrides for built-in system roles live in separate tables and never count.

create or replace function app.enforce_custom_role_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.assert_plan_quota(new.organization_id, 'max_custom_roles');
  return new;
end;
$$;

comment on function app.enforce_custom_role_quota() is
  'Blocks custom-role inserts that would exceed max_custom_roles under the organization quota lock.';

drop trigger if exists organization_roles_enforce_plan_quota
  on public.organization_roles;
create trigger organization_roles_enforce_plan_quota
  before insert on public.organization_roles
  for each row execute function app.enforce_custom_role_quota();

revoke all on function app.enforce_custom_role_quota()
  from public, anon, authenticated;
