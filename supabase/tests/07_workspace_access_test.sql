-- Workspace access management and public invitation preview regressions.
begin;

create extension if not exists pgtap with schema extensions;
select plan(10);

create temp table access_ids (key text primary key, value text);
grant all on access_ids to authenticated, anon;

insert into access_ids values
  ('org', (select id::text from public.organizations where name = 'Alpha Trading')),
  ('owner_member', (select id::text from public.organization_members where user_id = 'a0000000-0000-4000-8000-000000000001')),
  ('viewer_member', (select id::text from public.organization_members where user_id = 'a0000000-0000-4000-8000-000000000003'));

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select throws_ok(
  format('update public.organization_members set status = %L where id = %L',
         'suspended', (select value from access_ids where key = 'viewer_member')),
  '42501', null,
  'members cannot be mutated directly through the Data API role'
);

select lives_ok(
  format($sql$select public.manage_organization_member(%L, 'viewer', 'suspended', '{}', '{}')$sql$,
         (select value from access_ids where key = 'viewer_member')),
  'an owner can suspend a non-owner through the audited RPC'
);

select is(
  (select status::text from public.organization_members where id =
    (select value::uuid from access_ids where key = 'viewer_member')),
  'suspended',
  'the suspension is persisted'
);

select throws_ok(
  format($sql$select public.manage_organization_member(%L, 'owner', 'suspended', '{}', '{}')$sql$,
         (select value from access_ids where key = 'owner_member')),
  '22023', null,
  'a member cannot suspend themselves'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

select is(
  cardinality(public.my_capabilities((select value::uuid from access_ids where key = 'org'))),
  0,
  'a suspended member has no effective capabilities'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  format($sql$select public.manage_organization_member(%L, 'admin', 'active', array['reports.export'], array['transactions.reverse'])$sql$,
         (select value from access_ids where key = 'viewer_member')),
  'an owner can reactivate a member with a role and capability overrides'
);

select is(
  (select granted_capabilities[1] from public.organization_members where id =
    (select value::uuid from access_ids where key = 'viewer_member')),
  'reports.export',
  'the explicit capability grant is stored'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

select throws_ok(
  format($sql$select public.manage_organization_member(%L, 'viewer', 'active', '{}', '{}')$sql$,
         (select value from access_ids where key = 'owner_member')),
  '42501', null,
  'an admin cannot demote an owner'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

insert into access_ids
select 'invite_token', invitation_token
from public.create_organization_invitation(
  (select value::uuid from access_ids where key = 'org'),
  'secure-invite@ledgersuit.test',
  'accountant'
);

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select is(
  (select email from public.preview_organization_invitation(
    (select value from access_ids where key = 'invite_token'))),
  'secure-invite@ledgersuit.test',
  'a valid high-entropy token exposes only its invitation preview'
);

select throws_ok(
  $$select * from public.preview_organization_invitation('invalid')$$,
  '42501', null,
  'an invalid token cannot preview an invitation'
);

select * from finish();
rollback;
