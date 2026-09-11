-- Controlled counterparty creation, auditing, quota boundaries, and locking.
begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select plan(26);

create temp table counterparty_quota_ids (key text primary key, value uuid not null);
grant all on counterparty_quota_ids to authenticated, service_role;

insert into counterparty_quota_ids
select 'alpha_org', id from public.organizations where name = 'Alpha Trading';
insert into counterparty_quota_ids
select 'beta_org', id from public.organizations where name = 'Beta Supplies';

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from counterparty_quota_ids where key = 'alpha_org');

insert into public.counterparties (
  organization_id, name, type, is_archived, archived_at, created_by
)
select
  (select value from counterparty_quota_ids where key = 'alpha_org'),
  format('Quota counterparty %s', n),
  'customer',
  n = 99,
  case when n = 99 then now() else null end,
  'a0000000-0000-4000-8000-000000000001'
from generate_series(1, 99) n;

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from counterparty_quota_ids where key = 'alpha_org');

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.get_usage(
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'max_counterparties'
  ),
  99::bigint,
  'Solo usage includes an archived counterparty below its boundary'
);

select lives_ok(
  format(
    'select public.create_counterparty(%L, %L, %L, p_email => %L)',
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'Solo counterparty 100', 'vendor', 'vendor@example.com'
  ),
  'Solo permits its one-hundredth counterparty'
);

select is(
  (select count(*) from public.counterparties
   where organization_id = (select value from counterparty_quota_ids where key = 'alpha_org')
     and name = 'Solo counterparty 100'
     and email = 'vendor@example.com'),
  1::bigint,
  'the creation RPC persists normalized counterparty input'
);

select is(
  (select count(*) from public.audit_logs
   where organization_id = (select value from counterparty_quota_ids where key = 'alpha_org')
     and action = 'counterparty.created'
     and entity_id = (select id from public.counterparties
       where organization_id = (select value from counterparty_quota_ids where key = 'alpha_org')
         and name = 'Solo counterparty 100')),
  1::bigint,
  'the controlled RPC writes one creation audit entry'
);

select is(
  (select actor_id from public.audit_logs
   where organization_id = (select value from counterparty_quota_ids where key = 'alpha_org')
     and action = 'counterparty.created'
     and entity_id = (select id from public.counterparties
       where organization_id = (select value from counterparty_quota_ids where key = 'alpha_org')
         and name = 'Solo counterparty 100')),
  'a0000000-0000-4000-8000-000000000001'::uuid,
  'the audit entry attributes creation to the authenticated actor'
);

select is(
  public.get_usage(
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'max_counterparties'
  ),
  100::bigint,
  'Solo reaches its exact counterparty boundary'
);

select throws_ok(
  format(
    'select public.create_counterparty(%L, %L)',
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'Solo counterparty 101'
  ),
  'P0001',
  'PLAN_COUNTERPARTY_LIMIT_REACHED: usage 100, requested 1, limit 100',
  'Solo rejects its one-hundred-first counterparty with a stable error'
);

reset role;
select throws_ok(
  format(
    'insert into public.counterparties (organization_id, name) values (%L, %L)',
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'Privileged counterparty bypass'
  ),
  'P0001',
  'PLAN_COUNTERPARTY_LIMIT_REACHED: usage 100, requested 1, limit 100',
  'the table trigger blocks privileged direct inserts at the exact limit'
);

set local role authenticated;
select throws_ok(
  format(
    'insert into public.counterparties (organization_id, name) values (%L, %L)',
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'Direct counterparty bypass'
  ),
  '42501', null,
  'authenticated users cannot bypass the controlled creation RPC'
);

select lives_ok(
  format(
    $$update public.counterparties
      set is_archived = true, archived_at = now()
      where organization_id = %L and name = %L$$,
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'Solo counterparty 100'
  ),
  'counterparties remain archivable at the limit'
);

select is(
  public.get_usage(
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'max_counterparties'
  ),
  100::bigint,
  'archiving does not create counterparty capacity'
);

select throws_ok(
  format(
    'select public.create_counterparty(%L, %L)',
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    '   '
  ),
  '22023',
  'INVALID_INPUT: counterparty name is required',
  'the RPC reports a stable validation error before checking quota'
);

reset role;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from counterparty_quota_ids where key = 'alpha_org');

insert into public.counterparties (organization_id, name, type, created_by)
select
  (select value from counterparty_quota_ids where key = 'alpha_org'),
  format('Quota counterparty %s', n), 'customer',
  'a0000000-0000-4000-8000-000000000001'
from generate_series(101, 999) n;

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'starter')
where organization_id = (select value from counterparty_quota_ids where key = 'alpha_org');

select is(
  app.plan_quota_usage(
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'max_counterparties'
  ),
  999::bigint,
  'Starter begins one below its one-thousand-counterparty boundary'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select public.create_counterparty(%L, %L)',
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'Starter counterparty 1000'
  ),
  'Starter permits its one-thousandth counterparty'
);

select is(
  public.get_usage(
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'max_counterparties'
  ),
  1000::bigint,
  'Starter reaches its exact counterparty boundary'
);

select throws_ok(
  format(
    'select public.create_counterparty(%L, %L)',
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'Starter counterparty 1001'
  ),
  'P0001',
  'PLAN_COUNTERPARTY_LIMIT_REACHED: usage 1000, requested 1, limit 1000',
  'Starter rejects its one-thousand-first counterparty'
);

reset role;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from counterparty_quota_ids where key = 'alpha_org');

insert into public.counterparties (organization_id, name, type, created_by)
select
  (select value from counterparty_quota_ids where key = 'alpha_org'),
  format('Quota counterparty %s', n), 'customer',
  'a0000000-0000-4000-8000-000000000001'
from generate_series(1001, 4999) n;

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'business')
where organization_id = (select value from counterparty_quota_ids where key = 'alpha_org');

select is(
  app.plan_quota_usage(
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'max_counterparties'
  ),
  4999::bigint,
  'Business begins one below its five-thousand-counterparty boundary'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select public.create_counterparty(%L, %L)',
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'Business counterparty 5000'
  ),
  'Business permits its five-thousandth counterparty'
);

select is(
  public.get_usage(
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'max_counterparties'
  ),
  5000::bigint,
  'Business reaches its exact counterparty boundary'
);

select throws_ok(
  format(
    'select public.create_counterparty(%L, %L)',
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'Business counterparty 5001'
  ),
  'P0001',
  'PLAN_COUNTERPARTY_LIMIT_REACHED: usage 5000, requested 1, limit 5000',
  'Business rejects its five-thousand-first counterparty'
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
    'select public.create_counterparty(%L, %L)',
    (select value from counterparty_quota_ids where key = 'alpha_org'),
    'Cross-tenant counterparty'
  ),
  '42501', null,
  'an owner cannot consume another tenant counterparty quota'
);

-- Two independent sessions compete for the final Solo slot in Beta Supplies.
reset role;
select extensions.dblink_connect(
  'counterparty_race_1',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_connect(
  'counterparty_race_2',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);

select extensions.dblink_exec(
  'counterparty_race_1',
  format(
    $$insert into public.counterparties (
        organization_id, name, type, created_by
      )
      select %L, format('Race counterparty %%s', n), 'customer',
        'b0000000-0000-4000-8000-000000000001'
      from generate_series(1, 99) n$$,
    (select value from counterparty_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_exec(
  'counterparty_race_1',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'solo')
      where organization_id = %L$$,
    (select value from counterparty_quota_ids where key = 'beta_org')
  )
);

select extensions.dblink_exec('counterparty_race_1', 'begin');
select extensions.dblink_exec(
  'counterparty_race_1',
  format(
    $$do $block$ begin
      perform app.lock_plan_quota(%L, 'max_counterparties');
    end $block$;$$,
    (select value from counterparty_quota_ids where key = 'beta_org')
  )
);

select extensions.dblink_exec(
  'counterparty_race_1',
  $$do $block$ begin
      perform set_config(
        'request.jwt.claims',
        '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
        false
      );
    end $block$;$$
);
select extensions.dblink_exec('counterparty_race_1', 'set role authenticated');
select extensions.dblink_exec(
  'counterparty_race_2',
  $$do $block$ begin
      perform set_config(
        'request.jwt.claims',
        '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
        false
      );
    end $block$;$$
);
select extensions.dblink_exec('counterparty_race_2', 'set role authenticated');

select extensions.dblink_send_query(
  'counterparty_race_2',
  format(
    'select public.create_counterparty(%L, %L)',
    (select value from counterparty_quota_ids where key = 'beta_org'),
    'Race losing counterparty'
  )
);

select is(
  extensions.dblink_is_busy('counterparty_race_2'),
  1,
  'the concurrent counterparty request waits on the organization quota lock'
);

select lives_ok(
  format(
    $$select * from extensions.dblink('counterparty_race_1', %L)
      as counterparty(counterparty_id uuid)$$,
    format(
      'select public.create_counterparty(%L, %L)',
      (select value from counterparty_quota_ids where key = 'beta_org'),
      'Race winning counterparty'
    )
  ),
  'the lock owner consumes the final Solo counterparty slot'
);

select extensions.dblink_exec('counterparty_race_1', 'commit');
select *
from extensions.dblink_get_result('counterparty_race_2', false)
  as result(counterparty_id uuid);

select is(
  (select count(*) from public.counterparties
   where organization_id = (select value from counterparty_quota_ids where key = 'beta_org')
     and name like 'Race %'),
  100::bigint,
  'only one concurrent request consumes the final counterparty slot'
);

select ok(
  extensions.dblink_error_message('counterparty_race_2')
    like '%PLAN_COUNTERPARTY_LIMIT_REACHED:%',
  'the losing request receives the stable counterparty-limit error'
);

select is(
  app.plan_quota_usage(
    (select value from counterparty_quota_ids where key = 'beta_org'),
    'max_counterparties'
  ),
  100::bigint,
  'concurrent requests cannot overbook the Solo counterparty limit'
);

select extensions.dblink_exec('counterparty_race_1', 'reset role');
select extensions.dblink_exec(
  'counterparty_race_1',
  format(
    $$delete from public.counterparties
      where organization_id = %L and name like 'Race %%'$$,
    (select value from counterparty_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_exec(
  'counterparty_race_1',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
      where organization_id = %L$$,
    (select value from counterparty_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_disconnect('counterparty_race_1');
select extensions.dblink_disconnect('counterparty_race_2');

select * from finish();
rollback;
