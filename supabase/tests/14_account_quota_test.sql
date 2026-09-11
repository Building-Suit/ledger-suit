-- Account quota enforcement, including archived rows and concurrent creation.
begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select plan(28);

create temp table account_quota_ids (key text primary key, value uuid not null);
grant all on account_quota_ids to authenticated, service_role;

insert into account_quota_ids
select 'alpha_org', id from public.organizations where name = 'Alpha Trading';
insert into account_quota_ids
select 'beta_org', id from public.organizations where name = 'Beta Supplies';

insert into public.accounts (
  organization_id, code, name, type, subtype, currency, created_by
)
select
  (select value from account_quota_ids where key = 'alpha_org'),
  format('A%s', lpad(account_number::text, 3, '0')),
  format('Quota account %s', account_number),
  'asset', 'cash', 'EGP',
  'a0000000-0000-4000-8000-000000000001'
from generate_series(1, 29) account_number;

update public.accounts
set is_archived = true, archived_at = now()
where organization_id = (select value from account_quota_ids where key = 'alpha_org')
  and code = 'A029';

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from account_quota_ids where key = 'alpha_org');

reset role;
select is(
  app.plan_quota_usage(
    (select value from account_quota_ids where key = 'alpha_org'),
    'max_accounts'
  ),
  29::bigint,
  'Solo usage includes an archived account at one below its boundary'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select public.create_account(%L, %L, %L, %L, p_code => %L)',
    (select value from account_quota_ids where key = 'alpha_org'),
    'Solo account 30', 'asset', 'cash', 'A030'
  ),
  'Solo permits its thirtieth account'
);

select is(
  public.get_usage(
    (select value from account_quota_ids where key = 'alpha_org'),
    'max_accounts'
  ),
  30::bigint,
  'Solo reaches its exact thirty-account boundary'
);

select lives_ok(
  format(
    'select public.archive_account(%L)',
    (select id from public.accounts
     where organization_id = (select value from account_quota_ids where key = 'alpha_org')
       and code = 'A030')
  ),
  'an account can be archived at the limit'
);

select is(
  public.get_usage(
    (select value from account_quota_ids where key = 'alpha_org'),
    'max_accounts'
  ),
  30::bigint,
  'archiving does not create account capacity'
);

select throws_ok(
  format(
    'select public.create_account(%L, %L, %L, %L)',
    (select value from account_quota_ids where key = 'alpha_org'),
    'Solo account 31', 'asset', 'cash'
  ),
  'P0001',
  'PLAN_ACCOUNT_LIMIT_REACHED: usage 30, requested 1, limit 30',
  'Solo rejects its thirty-first account'
);

reset role;
select throws_ok(
  format(
    $$insert into public.accounts (
        organization_id, name, type, subtype, currency
      ) values (%L, %L, 'asset', 'cash', 'EGP')$$,
    (select value from account_quota_ids where key = 'alpha_org'),
    'Direct account bypass'
  ),
  'P0001',
  'PLAN_ACCOUNT_LIMIT_REACHED: usage 30, requested 1, limit 30',
  'the table trigger blocks privileged direct-insert bypasses'
);

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from account_quota_ids where key = 'alpha_org');

insert into public.accounts (
  organization_id, code, name, type, subtype, currency, created_by
)
select
  (select value from account_quota_ids where key = 'alpha_org'),
  format('A%s', lpad(account_number::text, 3, '0')),
  format('Quota account %s', account_number),
  'asset', 'cash', 'EGP',
  'a0000000-0000-4000-8000-000000000001'
from generate_series(31, 99) account_number;

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'starter')
where organization_id = (select value from account_quota_ids where key = 'alpha_org');

reset role;
select is(
  app.plan_quota_usage(
    (select value from account_quota_ids where key = 'alpha_org'),
    'max_accounts'
  ),
  99::bigint,
  'Starter fixture begins one below its one-hundred-account boundary'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select public.create_account(%L, %L, %L, %L, p_code => %L)',
    (select value from account_quota_ids where key = 'alpha_org'),
    'Starter revenue 100', 'revenue', 'service_revenue', 'A100'
  ),
  'Starter permits its one-hundredth account'
);

select is(
  (select count(*) from public.categories
   where organization_id = (select value from account_quota_ids where key = 'alpha_org')
     and name = 'Starter revenue 100'),
  1::bigint,
  'automatic category creation remains a category and does not add an account'
);

select is(
  public.get_usage(
    (select value from account_quota_ids where key = 'alpha_org'),
    'max_accounts'
  ),
  100::bigint,
  'Starter reaches its exact one-hundred-account boundary'
);

select throws_ok(
  format(
    'select public.create_account(%L, %L, %L, %L)',
    (select value from account_quota_ids where key = 'alpha_org'),
    'Starter account 101', 'asset', 'cash'
  ),
  'P0001',
  'PLAN_ACCOUNT_LIMIT_REACHED: usage 100, requested 1, limit 100',
  'Starter rejects its one-hundred-first account'
);

reset role;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from account_quota_ids where key = 'alpha_org');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select count(*) from public.accounts
   where organization_id = (select value from account_quota_ids where key = 'alpha_org')),
  100::bigint,
  'all accounts remain readable after a downgrade below current usage'
);

select lives_ok(
  format(
    'select public.archive_account(%L)',
    (select id from public.accounts
     where organization_id = (select value from account_quota_ids where key = 'alpha_org')
       and code = 'A031')
  ),
  'archival remains available while downgraded over limit'
);

select is(
  public.get_usage(
    (select value from account_quota_ids where key = 'alpha_org'),
    'max_accounts'
  ),
  100::bigint,
  'archival still does not bypass the downgraded limit'
);

select lives_ok(
  format(
    'select public.update_account(%L, %L, %L)',
    (select id from public.accounts
     where organization_id = (select value from account_quota_ids where key = 'alpha_org')
       and code = 'A032'),
    'Corrected account 32',
    'A032'
  ),
  'safe account corrections remain available while over limit'
);

select is(
  (select name from public.accounts
   where organization_id = (select value from account_quota_ids where key = 'alpha_org')
     and code = 'A032'),
  'Corrected account 32',
  'the over-limit account correction is persisted'
);

select throws_ok(
  format(
    'select public.create_account(%L, %L, %L, %L)',
    (select value from account_quota_ids where key = 'alpha_org'),
    'Downgraded account', 'asset', 'cash'
  ),
  'P0001',
  'PLAN_ACCOUNT_LIMIT_REACHED: usage 100, requested 1, limit 30',
  'downgrade blocks only additional account creation'
);

reset role;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from account_quota_ids where key = 'alpha_org');

insert into public.accounts (
  organization_id, code, name, type, subtype, currency, created_by
)
select
  (select value from account_quota_ids where key = 'alpha_org'),
  format('A%s', lpad(account_number::text, 3, '0')),
  format('Quota account %s', account_number),
  'asset', 'cash', 'EGP',
  'a0000000-0000-4000-8000-000000000001'
from generate_series(101, 299) account_number;

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'business')
where organization_id = (select value from account_quota_ids where key = 'alpha_org');

reset role;
select is(
  app.plan_quota_usage(
    (select value from account_quota_ids where key = 'alpha_org'),
    'max_accounts'
  ),
  299::bigint,
  'Business fixture begins one below its three-hundred-account boundary'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select public.create_account(%L, %L, %L, %L, p_code => %L)',
    (select value from account_quota_ids where key = 'alpha_org'),
    'Business account 300', 'asset', 'cash', 'A300'
  ),
  'Business permits its three-hundredth account'
);

select is(
  public.get_usage(
    (select value from account_quota_ids where key = 'alpha_org'),
    'max_accounts'
  ),
  300::bigint,
  'Business reaches its exact three-hundred-account boundary'
);

select throws_ok(
  format(
    'select public.create_account(%L, %L, %L, %L)',
    (select value from account_quota_ids where key = 'alpha_org'),
    'Business account 301', 'asset', 'cash'
  ),
  'P0001',
  'PLAN_ACCOUNT_LIMIT_REACHED: usage 300, requested 1, limit 300',
  'Business rejects its three-hundred-first account'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  format(
    'select public.create_account(%L, %L, %L, %L)',
    (select value from account_quota_ids where key = 'alpha_org'),
    'Cross-tenant account', 'asset', 'cash'
  ),
  '42501', null,
  'an owner cannot consume another tenant account quota'
);

-- Two independent sessions compete for the final Solo slot in Beta Supplies.
reset role;
select extensions.dblink_connect(
  'account_race_1',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_connect(
  'account_race_2',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);

select extensions.dblink_exec(
  'account_race_1',
  format(
    $$insert into public.accounts (
        organization_id, code, name, type, subtype, currency, created_by
      )
      select %L, format('R%%s', lpad(n::text, 3, '0')),
        format('Race account %%s', n), 'asset', 'cash', 'EGP',
        'b0000000-0000-4000-8000-000000000001'
      from generate_series(1, 29) n$$,
    (select value from account_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_exec(
  'account_race_1',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'solo')
      where organization_id = %L$$,
    (select value from account_quota_ids where key = 'beta_org')
  )
);

select extensions.dblink_exec('account_race_1', 'begin');
select extensions.dblink_exec(
  'account_race_1',
  format(
    $$do $block$ begin
      perform app.lock_plan_quota(%L, 'max_accounts');
    end $block$;$$,
    (select value from account_quota_ids where key = 'beta_org')
  )
);

select extensions.dblink_exec(
  'account_race_1',
  $$do $block$ begin
      perform set_config(
        'request.jwt.claims',
        '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
        false
      );
    end $block$;$$
);
select extensions.dblink_exec('account_race_1', 'set role authenticated');
select extensions.dblink_exec(
  'account_race_2',
  $$do $block$ begin
      perform set_config(
        'request.jwt.claims',
        '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
        false
      );
    end $block$;$$
);
select extensions.dblink_exec('account_race_2', 'set role authenticated');

select extensions.dblink_send_query(
  'account_race_2',
  format(
    'select public.create_account(%L, %L, %L, %L, p_code => %L)',
    (select value from account_quota_ids where key = 'beta_org'),
    'Race losing account', 'asset', 'cash', 'R031'
  )
);

select is(
  extensions.dblink_is_busy('account_race_2'),
  1,
  'the concurrent account request waits on the organization quota lock'
);

select lives_ok(
  format(
    $$select * from extensions.dblink('account_race_1', %L)
      as account(account_id uuid)$$,
    format(
      'select public.create_account(%L, %L, %L, %L, p_code => %L)',
      (select value from account_quota_ids where key = 'beta_org'),
      'Race winning account', 'asset', 'cash', 'R030'
    )
  ),
  'the lock owner consumes the final Solo account slot'
);

select extensions.dblink_exec('account_race_1', 'commit');
select *
from extensions.dblink_get_result('account_race_2', false)
  as result(account_id uuid);

select is(
  (select count(*) from public.accounts
   where organization_id = (select value from account_quota_ids where key = 'beta_org')
     and code like 'R%'),
  30::bigint,
  'only one concurrent request consumes the final account slot'
);

select ok(
  extensions.dblink_error_message('account_race_2')
    like '%PLAN_ACCOUNT_LIMIT_REACHED:%',
  'the losing request receives the stable account-limit error'
);

select is(
  app.plan_quota_usage(
    (select value from account_quota_ids where key = 'beta_org'),
    'max_accounts'
  ),
  30::bigint,
  'concurrent requests cannot overbook the Solo account limit'
);

select extensions.dblink_exec('account_race_1', 'reset role');
select extensions.dblink_exec(
  'account_race_1',
  format(
    $$delete from public.accounts
      where organization_id = %L and code like 'R%%'$$,
    (select value from account_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_exec(
  'account_race_1',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
      where organization_id = %L$$,
    (select value from account_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_disconnect('account_race_1');
select extensions.dblink_disconnect('account_race_2');

select * from finish();
rollback;
