-- Workspace-specific built-in role permissions and immutable Owner access.
begin;

create extension if not exists pgtap with schema extensions;
select plan(9);

create temp table editable_role_ids (key text primary key, value uuid);
grant all on editable_role_ids to authenticated;

insert into editable_role_ids values
  ('org', (select id from public.organizations where name = 'Alpha Trading')),
  ('owner_member', (select id from public.organization_members where user_id = 'a0000000-0000-4000-8000-000000000001'));

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  format(
    $sql$select public.update_organization_system_role(%L, 'viewer', array['organization.read', 'reports.read'])$sql$,
    (select value from editable_role_ids where key = 'org')
  ),
  'an authorized member can customize a non-owner system role'
);

select is(
  (
    select count(*)::integer
    from public.organization_system_role_capabilities
    where organization_id = (select value from editable_role_ids where key = 'org')
      and role = 'viewer'
  ),
  2,
  'the workspace-specific permission set is persisted'
);

select throws_ok(
  $$delete from public.organization_system_roles where role = 'viewer'$$,
  '42501', null,
  'workspace role permissions cannot be mutated directly'
);

select throws_ok(
  format(
    $sql$select public.update_organization_system_role(%L, 'owner', array['organization.read'])$sql$,
    (select value from editable_role_ids where key = 'org')
  ),
  '22023', null,
  'Owner permissions cannot be customized'
);

select lives_ok(
  format(
    $sql$select public.manage_organization_member(%L, 'owner', 'active', '{}', array['billing.manage'])$sql$,
    (select value from editable_role_ids where key = 'owner_member')
  ),
  'an owner member override can be stored without weakening the Owner invariant'
);

select is(
  cardinality(public.my_capabilities((select value from editable_role_ids where key = 'org'))),
  (select count(*)::integer from public.capabilities),
  'Owner always receives every catalogued permission'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

select is(
  cardinality(public.my_capabilities((select value from editable_role_ids where key = 'org'))),
  2,
  'a member on the customized role receives only its workspace permissions'
);

select ok(
  app.has_capability((select value from editable_role_ids where key = 'org'), 'reports.read'),
  'the customized role grants its selected capability'
);

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select throws_ok(
  $$select * from public.organization_system_role_capabilities$$,
  '42501', null,
  'anonymous callers cannot read workspace role permissions'
);

select * from finish();
rollback;
