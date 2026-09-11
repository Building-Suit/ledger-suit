-- Central plan resolution, quota assertions, locks, and tenant-safe usage.
begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select plan(34);

create temp table quota_test_ids (key text primary key, value uuid not null);
grant all on quota_test_ids to authenticated, service_role;

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

insert into quota_test_ids values (
  'launch_org',
  public.create_organization('Quota Engine Launch Co', 'EGP')
);

select public.create_account(
  (select value from quota_test_ids where key = 'launch_org'),
  'Quota account', 'asset', 'bank'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

insert into quota_test_ids values (
  'legacy_org',
  public.create_organization('Quota Engine Legacy Co', 'EGP')
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
set local role service_role;

insert into public.organization_invitations (
  organization_id, email, token_hash, expires_at
) values
  (
    (select value from quota_test_ids where key = 'launch_org'),
    'reserved-seat@example.com', 'quota-reserved-seat', now() + interval '1 day'
  ),
  (
    (select value from quota_test_ids where key = 'launch_org'),
    'expired-seat@example.com', 'quota-expired-seat', now() - interval '1 day'
  );

-- Build the over-limit fixture while it is still on the unlimited
-- compatibility plan, then model a downgrade to Solo. Resource-specific
-- enforcement must preserve existing rows after that transition.
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from quota_test_ids where key = 'launch_org');

reset role;

select is(
  (select plan_key from app.resolve_plan_entitlement(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  )),
  'solo',
  'private resolution returns the subscribed plan independently of caller membership'
);

select is(
  (select limit_value from app.resolve_plan_entitlement(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  )),
  30::bigint,
  'private resolution returns the raw plan limit'
);

select ok(
  not (select entitlement_found from app.resolve_plan_entitlement(
    (select value from quota_test_ids where key = 'legacy_org'),
    'max_accounts'
  )),
  'a missing compatibility-plan entitlement remains distinguishable'
);

select ok(
  (select is_enabled and limit_value is null
   from app.resolve_plan_entitlement(
     (select value from quota_test_ids where key = 'legacy_org'),
     'max_accounts'
   )),
  'a missing compatibility-plan entitlement remains enabled and unlimited'
);

select throws_ok(
  format(
    'select * from app.resolve_plan_entitlement(%L, %L)',
    (select value from quota_test_ids where key = 'launch_org'),
    'missing_launch_key'
  ),
  'P0001', 'PLAN_ENTITLEMENT_NOT_CONFIGURED: missing_launch_key',
  'a missing launch-plan entitlement fails closed'
);

select throws_ok(
  format(
    'select app.assert_plan_feature(%L, %L)',
    (select value from quota_test_ids where key = 'launch_org'),
    'imports'
  ),
  'P0001', 'FEATURE_NOT_AVAILABLE_ON_PLAN: imports',
  'disabled features use the stable generic plan error'
);

select throws_ok(
  format(
    'select app.assert_plan_feature(%L, %L)',
    (select value from quota_test_ids where key = 'launch_org'),
    'multi_currency'
  ),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'multi-currency uses its stable specific plan error'
);

select lives_ok(
  format(
    'select app.assert_plan_feature(%L, %L)',
    (select value from quota_test_ids where key = 'launch_org'),
    'exports'
  ),
  'enabled features pass the private assertion'
);

select throws_ok(
  format(
    'select app.assert_plan_quota(%L, %L)',
    (select value from quota_test_ids where key = 'launch_org'),
    'max_custom_roles'
  ),
  'P0001',
  'PLAN_CUSTOM_ROLE_LIMIT_REACHED: usage 0, requested 1, limit 0',
  'a zero quota rejects the first usage-increasing action'
);

select lives_ok(
  format(
    'select app.assert_plan_quota(%L, %L)',
    (select value from quota_test_ids where key = 'legacy_org'),
    'max_accounts'
  ),
  'an unlimited compatibility quota permits an increase'
);

select throws_ok(
  format(
    'select app.assert_plan_quota(%L, %L, 0)',
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  ),
  '22023', 'PLAN_QUOTA_INCREMENT_INVALID',
  'quota assertions reject non-increasing requests'
);

select throws_ok(
  format(
    'select app.assert_plan_quota(%L, %L)',
    (select value from quota_test_ids where key = 'launch_org'),
    'not_a_quota'
  ),
  '22023', 'PLAN_QUOTA_NOT_SUPPORTED: not_a_quota',
  'unsupported quota keys fail with a stable error'
);

select is(
  app.plan_quota_lock_key(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  ),
  app.plan_quota_lock_key(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  ),
  'the same tenant and quota always derive the same advisory-lock key'
);

select isnt(
  app.plan_quota_lock_key(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  ),
  app.plan_quota_lock_key(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_members'
  ),
  'different resources use different advisory-lock keys'
);

select lives_ok(
  format(
    'select app.assert_plan_quota(%L, %L)',
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  ),
  'an under-limit quota passes after locking and recounting'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_locks
    where locktype = 'advisory'
      and pid = pg_backend_pid()
      and granted
  ),
  'a successful assertion holds its advisory lock until transaction end'
);

select extensions.dblink_connect(
  'quota_lock_1',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_connect(
  'quota_lock_2',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_exec('quota_lock_1', 'begin');
select extensions.dblink_exec(
  'quota_lock_1',
  $$do $remote$ begin
      perform app.lock_plan_quota(
        '10000000-0000-4000-8000-000000000001'::uuid,
        'max_accounts'
      );
    end $remote$;$$
);

select is(
  (select locked
   from extensions.dblink(
     'quota_lock_2',
     $$select pg_catalog.pg_try_advisory_xact_lock(
         app.plan_quota_lock_key(
           '10000000-0000-4000-8000-000000000001'::uuid,
           'max_accounts'
         )
       )$$
   ) as result(locked boolean)),
  false,
  'a second database session cannot acquire the same tenant-resource lock'
);

select extensions.dblink_exec('quota_lock_1', 'rollback');

select is(
  (select locked
   from extensions.dblink(
     'quota_lock_2',
     $$select pg_catalog.pg_try_advisory_xact_lock(
         app.plan_quota_lock_key(
           '10000000-0000-4000-8000-000000000001'::uuid,
           'max_accounts'
         )
       )$$
   ) as result(locked boolean)),
  true,
  'the tenant-resource lock is released when the owning transaction ends'
);

select extensions.dblink_disconnect('quota_lock_1');
select extensions.dblink_disconnect('quota_lock_2');

select is(
  app.plan_quota_usage(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_members'
  ),
  2::bigint,
  'member usage counts active members and live pending invitations only'
);

select is(
  app.plan_quota_usage(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  ),
  1::bigint,
  'account usage uses the shared authoritative counting predicate'
);

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select is(
  public.get_limit(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  ),
  30::bigint,
  'the existing get_limit signature and active-subscription behavior remain compatible'
);

select ok(
  public.can_use_feature(
    (select value from quota_test_ids where key = 'launch_org'),
    'exports'
  ),
  'the existing can_use_feature signature remains compatible'
);

select is(
  public.get_usage(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  ),
  1::bigint,
  'members can read authoritative usage'
);

select is(
  (select count(*) from public.subscription_usage_summary(
    (select value from quota_test_ids where key = 'launch_org')
  )),
  7::bigint,
  'the usage summary has one row for every launch quota'
);

select is(
  (select used_value from public.subscription_usage_summary(
    (select value from quota_test_ids where key = 'launch_org')
  ) where quota_key = 'max_members'),
  2::bigint,
  'the public summary and enforcement use the same usage count'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000000","role":"service_role"}', true);
set local role service_role;

update public.subscription_entitlements
set limit_value = 0
where plan_id = (select id from public.subscription_plans where key = 'solo')
  and feature_key = 'max_accounts';

update public.subscriptions
set trial_ends_at = now() - interval '1 second'
where organization_id = (select value from quota_test_ids where key = 'launch_org');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select is(
  public.get_limit(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  ),
  0::bigint,
  'the public compatibility lookup still folds lapsed subscription access into its result'
);

select ok(
  not public.can_use_feature(
    (select value from quota_test_ids where key = 'launch_org'),
    'exports'
  ),
  'the public compatibility feature lookup still blocks a lapsed subscription'
);

select ok(
  (select not writes_allowed and used_value = 1 and is_over_limit
   from public.subscription_usage_summary(
     (select value from quota_test_ids where key = 'launch_org')
   ) where quota_key = 'max_accounts'),
  'usage summary keeps subscription access, readable usage, and downgrade-over-limit state separate'
);

reset role;

select throws_ok(
  format(
    'select app.assert_plan_quota(%L, %L)',
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  ),
  'P0001',
  'PLAN_ACCOUNT_LIMIT_REACHED: usage 1, requested 1, limit 0',
  'downgrade-over-limit state blocks only the next quota-increasing assertion'
);

select is(
  (select limit_value from app.resolve_plan_entitlement(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  )),
  0::bigint,
  'private plan resolution remains available independently of lapsed subscription access'
);

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

select is(
  public.get_usage(
    (select value from quota_test_ids where key = 'launch_org'),
    'max_accounts'
  ),
  0::bigint,
  'cross-tenant get_usage calls reveal no usage'
);

select is(
  (select count(*) from public.subscription_usage_summary(
    (select value from quota_test_ids where key = 'launch_org')
  )),
  0::bigint,
  'cross-tenant usage summaries return no rows'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'app.assert_plan_quota(uuid,text,bigint)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'app.resolve_plan_entitlement(uuid,text)',
    'EXECUTE'
  ),
  'raw plan resolution and quota assertions are not client-callable'
);

select ok(
  has_function_privilege('authenticated', 'public.get_usage(uuid,text)', 'EXECUTE')
  and has_function_privilege(
    'authenticated',
    'public.subscription_usage_summary(uuid)',
    'EXECUTE'
  ),
  'authenticated clients can call only the tenant-checked usage APIs'
);

reset role;
select * from finish();
rollback;
