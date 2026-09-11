-- Custom-role quota boundaries, assignment preservation, deletion, and locking.
begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select plan(33);

create temp table custom_role_quota_ids (key text primary key, value uuid not null);
grant all on custom_role_quota_ids to authenticated, service_role;

insert into custom_role_quota_ids
select 'alpha_org', id from public.organizations where name = 'Alpha Trading';
insert into custom_role_quota_ids
select 'beta_org', id from public.organizations where name = 'Beta Supplies';
insert into custom_role_quota_ids
select 'beta_user', id from public.profiles where email = 'owner@beta.test';

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org');

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.get_usage(
    (select value from custom_role_quota_ids where key = 'alpha_org'),
    'max_custom_roles'
  ),
  0::bigint,
  'Solo starts with zero custom-role usage'
);

select lives_ok(
  format(
    $$select public.update_organization_system_role(
      %L, 'viewer', array['organization.read', 'reports.read']
    )$$,
    (select value from custom_role_quota_ids where key = 'alpha_org')
  ),
  'editing a built-in system role remains available on Solo'
);

select is(
  public.get_usage(
    (select value from custom_role_quota_ids where key = 'alpha_org'),
    'max_custom_roles'
  ),
  0::bigint,
  'system-role overrides do not consume custom-role capacity'
);

select throws_ok(
  format(
    $$select public.create_organization_role(
      %L, 'solo_role', 'Solo role', 'دور فردي', array['organization.read']
    )$$,
    (select value from custom_role_quota_ids where key = 'alpha_org')
  ),
  'P0001',
  'PLAN_CUSTOM_ROLE_LIMIT_REACHED: usage 0, requested 1, limit 0',
  'Solo rejects custom-role creation with the stable quota error'
);

reset role;
select throws_ok(
  format(
    $$insert into public.organization_roles (organization_id, key, name_en, name_ar)
      values (%L, 'solo_bypass', 'Solo bypass', 'تجاوز فردي')$$,
    (select value from custom_role_quota_ids where key = 'alpha_org')
  ),
  'P0001',
  'PLAN_CUSTOM_ROLE_LIMIT_REACHED: usage 0, requested 1, limit 0',
  'the table trigger blocks privileged custom-role inserts on Solo'
);

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'starter')
where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org');
set local role authenticated;

select lives_ok(
  format(
    $$select public.create_organization_role(
      %L, 'starter_role_1', 'Starter role 1', 'دور مبتدئ ١', array['organization.read']
    )$$,
    (select value from custom_role_quota_ids where key = 'alpha_org')
  ),
  'Starter permits its first custom role'
);

select lives_ok(
  format(
    $$select public.create_organization_role(
      %L, 'starter_role_2', 'Starter role 2', 'دور مبتدئ ٢', array['organization.read']
    )$$,
    (select value from custom_role_quota_ids where key = 'alpha_org')
  ),
  'Starter permits its second custom role'
);

select lives_ok(
  format(
    $$select public.create_organization_role(
      %L, 'starter_role_3', 'Starter role 3', 'دور مبتدئ ٣', array['organization.read']
    )$$,
    (select value from custom_role_quota_ids where key = 'alpha_org')
  ),
  'Starter permits its third custom role'
);

select is(
  public.get_usage(
    (select value from custom_role_quota_ids where key = 'alpha_org'),
    'max_custom_roles'
  ),
  3::bigint,
  'Starter reaches its exact three-role boundary'
);

select throws_ok(
  format(
    $$select public.create_organization_role(
      %L, 'starter_role_4', 'Starter role 4', 'دور مبتدئ ٤', array['organization.read']
    )$$,
    (select value from custom_role_quota_ids where key = 'alpha_org')
  ),
  'P0001',
  'PLAN_CUSTOM_ROLE_LIMIT_REACHED: usage 3, requested 1, limit 3',
  'Starter rejects its fourth custom role'
);

select is(
  (select count(*) from public.audit_logs
   where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
     and action = 'role.created'
     and entity_id in (
       select id from public.organization_roles
       where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
         and key like 'starter_role_%'
     )),
  3::bigint,
  'successful custom-role creation remains audited'
);

reset role;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org');

insert into public.organization_members (organization_id, user_id, role)
values (
  (select value from custom_role_quota_ids where key = 'alpha_org'),
  (select value from custom_role_quota_ids where key = 'beta_user'),
  'viewer'
);
set local role authenticated;

select lives_ok(
  format(
    $$select public.manage_organization_member(
      p_member_id => %L,
      p_role => 'viewer',
      p_status => 'active',
      p_role_id => %L
    )$$,
    (select id from public.organization_members
     where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
       and user_id = (select value from custom_role_quota_ids where key = 'beta_user')),
    (select id from public.organization_roles
     where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
       and key = 'starter_role_1')
  ),
  'a member can be assigned to a custom role at the limit'
);

select lives_ok(
  format(
    $$select * from public.create_organization_invitation(
      p_organization_id => %L,
      p_email => 'custom-role-quota-invite@ledgersuit.test',
      p_role => 'viewer',
      p_role_id => %L
    )$$,
    (select value from custom_role_quota_ids where key = 'alpha_org'),
    (select id from public.organization_roles
     where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
       and key = 'starter_role_1')
  ),
  'a pending invitation can be assigned to a custom role at the limit'
);

select is(
  (select role_id from public.organization_members
   where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
     and user_id = (select value from custom_role_quota_ids where key = 'beta_user')),
  (select id from public.organization_roles
   where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
     and key = 'starter_role_1'),
  'the member assignment points to the custom role'
);

select is(
  (select role_id from public.organization_invitations
   where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
     and email = 'custom-role-quota-invite@ledgersuit.test'),
  (select id from public.organization_roles
   where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
     and key = 'starter_role_1'),
  'the invitation assignment points to the custom role'
);

reset role;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org');
set local role authenticated;

select is(
  public.get_usage(
    (select value from custom_role_quota_ids where key = 'alpha_org'),
    'max_custom_roles'
  ),
  3::bigint,
  'downgrade preserves existing custom-role usage above the Solo limit'
);

select is(
  (select role_id from public.organization_members
   where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
     and user_id = (select value from custom_role_quota_ids where key = 'beta_user')),
  (select id from public.organization_roles
   where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
     and key = 'starter_role_1'),
  'downgrade preserves the member custom-role assignment'
);

select is(
  (select role_id from public.organization_invitations
   where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
     and email = 'custom-role-quota-invite@ledgersuit.test'),
  (select id from public.organization_roles
   where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
     and key = 'starter_role_1'),
  'downgrade preserves the pending invitation assignment'
);

select throws_ok(
  format(
    'select public.delete_organization_role(%L)',
    (select id from public.organization_roles
     where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
       and key = 'starter_role_1')
  ),
  '22023',
  'ROLE_IN_USE: move members off this role before deleting it',
  'an assigned custom role cannot be deleted while over limit'
);

select lives_ok(
  format(
    'select public.delete_organization_role(%L)',
    (select id from public.organization_roles
     where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
       and key = 'starter_role_2')
  ),
  'an unused custom role can be safely deleted while over limit'
);

select is(
  public.get_usage(
    (select value from custom_role_quota_ids where key = 'alpha_org'),
    'max_custom_roles'
  ),
  2::bigint,
  'safe deletion reduces custom-role usage while still over Solo limit'
);

select is(
  (select count(*) from public.organization_roles
   where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org')
     and key in ('starter_role_1', 'starter_role_3')),
  2::bigint,
  'assigned and remaining role definitions stay intact after safe deletion'
);

reset role;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org');

insert into public.organization_roles (organization_id, key, name_en, name_ar)
select
  (select value from custom_role_quota_ids where key = 'alpha_org'),
  format('business_seed_%s', n),
  format('Business seed %s', n),
  format('دور أعمال %s', n)
from generate_series(1, 7) n;

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'business')
where organization_id = (select value from custom_role_quota_ids where key = 'alpha_org');
set local role authenticated;

select is(
  public.get_usage(
    (select value from custom_role_quota_ids where key = 'alpha_org'),
    'max_custom_roles'
  ),
  9::bigint,
  'Business begins one below its ten-role boundary'
);

select lives_ok(
  format(
    $$select public.create_organization_role(
      %L, 'business_role_10', 'Business role 10', 'دور أعمال ١٠', array['organization.read']
    )$$,
    (select value from custom_role_quota_ids where key = 'alpha_org')
  ),
  'Business permits its tenth custom role'
);

select is(
  public.get_usage(
    (select value from custom_role_quota_ids where key = 'alpha_org'),
    'max_custom_roles'
  ),
  10::bigint,
  'Business reaches its exact ten-role boundary'
);

select throws_ok(
  format(
    $$select public.create_organization_role(
      %L, 'business_role_11', 'Business role 11', 'دور أعمال ١١', array['organization.read']
    )$$,
    (select value from custom_role_quota_ids where key = 'alpha_org')
  ),
  'P0001',
  'PLAN_CUSTOM_ROLE_LIMIT_REACHED: usage 10, requested 1, limit 10',
  'Business rejects its eleventh custom role'
);

reset role;
select throws_ok(
  format(
    $$insert into public.organization_roles (organization_id, key, name_en, name_ar)
      values (%L, 'business_bypass', 'Business bypass', 'تجاوز أعمال')$$,
    (select value from custom_role_quota_ids where key = 'alpha_org')
  ),
  'P0001',
  'PLAN_CUSTOM_ROLE_LIMIT_REACHED: usage 10, requested 1, limit 10',
  'privileged inserts cannot bypass the Business boundary'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  format(
    $$select public.create_organization_role(
      %L, 'cross_tenant_role', 'Cross tenant', 'عبر المؤسسات', array['organization.read']
    )$$,
    (select value from custom_role_quota_ids where key = 'alpha_org')
  ),
  '42501', null,
  'an owner cannot consume another tenant custom-role quota'
);

-- Two sessions compete for the final Starter slot in Beta Supplies.
reset role;
select extensions.dblink_connect(
  'custom_role_race_1',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_connect(
  'custom_role_race_2',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);

select extensions.dblink_exec(
  'custom_role_race_1',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
      where organization_id = %L$$,
    (select value from custom_role_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_exec(
  'custom_role_race_1',
  format(
    $$insert into public.organization_roles (organization_id, key, name_en, name_ar)
      values
        (%L, 'race_role_1', 'Race role 1', 'دور سباق ١'),
        (%L, 'race_role_2', 'Race role 2', 'دور سباق ٢')$$,
    (select value from custom_role_quota_ids where key = 'beta_org'),
    (select value from custom_role_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_exec(
  'custom_role_race_1',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'starter')
      where organization_id = %L$$,
    (select value from custom_role_quota_ids where key = 'beta_org')
  )
);

select extensions.dblink_exec('custom_role_race_1', 'begin');
select extensions.dblink_exec(
  'custom_role_race_1',
  format(
    $$do $block$ begin
      perform app.lock_plan_quota(%L, 'max_custom_roles');
    end $block$;$$,
    (select value from custom_role_quota_ids where key = 'beta_org')
  )
);

select extensions.dblink_exec(
  'custom_role_race_1',
  $$do $block$ begin
      perform set_config(
        'request.jwt.claims',
        '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
        false
      );
    end $block$;$$
);
select extensions.dblink_exec('custom_role_race_1', 'set role authenticated');
select extensions.dblink_exec(
  'custom_role_race_2',
  $$do $block$ begin
      perform set_config(
        'request.jwt.claims',
        '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
        false
      );
    end $block$;$$
);
select extensions.dblink_exec('custom_role_race_2', 'set role authenticated');

select extensions.dblink_send_query(
  'custom_role_race_2',
  format(
    $$select public.create_organization_role(
      %L, 'race_role_4', 'Race role 4', 'دور سباق ٤', array['organization.read']
    )$$,
    (select value from custom_role_quota_ids where key = 'beta_org')
  )
);

select is(
  extensions.dblink_is_busy('custom_role_race_2'),
  1,
  'a concurrent custom-role request waits on the organization quota lock'
);

select lives_ok(
  format(
    $$select * from extensions.dblink('custom_role_race_1', %L)
      as role(role_id uuid)$$,
    format(
      $$select public.create_organization_role(
        %L, 'race_role_3', 'Race role 3', 'دور سباق ٣', array['organization.read']
      )$$,
      (select value from custom_role_quota_ids where key = 'beta_org')
    )
  ),
  'the lock owner consumes the final Starter custom-role slot'
);

select extensions.dblink_exec('custom_role_race_1', 'commit');
select *
from extensions.dblink_get_result('custom_role_race_2', false)
  as result(role_id uuid);

select is(
  (select count(*) from public.organization_roles
   where organization_id = (select value from custom_role_quota_ids where key = 'beta_org')
     and key like 'race_role_%'),
  3::bigint,
  'only one concurrent request consumes the final custom-role slot'
);

select ok(
  extensions.dblink_error_message('custom_role_race_2')
    like '%PLAN_CUSTOM_ROLE_LIMIT_REACHED:%',
  'the losing request receives the stable custom-role-limit error'
);

select is(
  app.plan_quota_usage(
    (select value from custom_role_quota_ids where key = 'beta_org'),
    'max_custom_roles'
  ),
  3::bigint,
  'concurrent requests cannot overbook Starter custom-role capacity'
);

select extensions.dblink_exec('custom_role_race_1', 'reset role');
select extensions.dblink_exec(
  'custom_role_race_1',
  format(
    $$delete from public.organization_roles
      where organization_id = %L and key like 'race_role_%%'$$,
    (select value from custom_role_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_exec(
  'custom_role_race_1',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
      where organization_id = %L$$,
    (select value from custom_role_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_disconnect('custom_role_race_1');
select extensions.dblink_disconnect('custom_role_race_2');

select * from finish();
rollback;
