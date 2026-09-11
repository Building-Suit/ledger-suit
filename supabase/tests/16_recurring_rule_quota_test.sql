-- Recurring-rule quota state transitions, scheduler compatibility, and locking.
begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select plan(44);

create temp table recurring_quota_ids (key text primary key, value uuid not null);
grant all on recurring_quota_ids to authenticated, service_role;

insert into recurring_quota_ids
select 'alpha_org', id from public.organizations where name = 'Alpha Trading';
insert into recurring_quota_ids
select 'beta_org', id from public.organizations where name = 'Beta Supplies';

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from recurring_quota_ids where key = 'alpha_org');

select app.seed_chart_of_accounts(
  (select value from recurring_quota_ids where key = 'alpha_org')
);
select app.seed_categories(
  (select value from recurring_quota_ids where key = 'alpha_org')
);

insert into recurring_quota_ids
select 'bank', id from public.accounts
where organization_id = (select value from recurring_quota_ids where key = 'alpha_org')
  and system_key = 'bank';
insert into recurring_quota_ids
select 'rent_category', id from public.categories
where organization_id = (select value from recurring_quota_ids where key = 'alpha_org')
  and name = 'Rent';

insert into public.recurring_rules (
  organization_id, name, transaction_type, template, frequency,
  start_date, next_run_on, status, created_by
)
values
  ((select value from recurring_quota_ids where key = 'alpha_org'),
   'Quota active A', 'expense', '{}'::jsonb, 'monthly', current_date + 365,
   current_date + 365, 'active', 'a0000000-0000-4000-8000-000000000001'),
  ((select value from recurring_quota_ids where key = 'alpha_org'),
   'Quota paused B', 'expense', '{}'::jsonb, 'monthly', current_date + 365,
   current_date + 365, 'paused', 'a0000000-0000-4000-8000-000000000001'),
  ((select value from recurring_quota_ids where key = 'alpha_org'),
   'Quota failed C', 'expense', '{}'::jsonb, 'monthly', current_date + 365,
   current_date + 365, 'failed', 'a0000000-0000-4000-8000-000000000001'),
  ((select value from recurring_quota_ids where key = 'alpha_org'),
   'Quota active D', 'expense', '{}'::jsonb, 'monthly', current_date + 365,
   current_date + 365, 'active', 'a0000000-0000-4000-8000-000000000001'),
  ((select value from recurring_quota_ids where key = 'alpha_org'),
   'Quota completed E', 'expense', '{}'::jsonb, 'monthly', current_date + 365,
   current_date + 365, 'completed', 'a0000000-0000-4000-8000-000000000001');

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from recurring_quota_ids where key = 'alpha_org');

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.get_usage(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    'max_recurring_rules'
  ),
  4::bigint,
  'active, paused, and failed rules count while completed rules do not'
);

select lives_ok(
  format(
    $$select public.create_recurring_rule(
      p_organization_id => %L,
      p_name => 'Quota fifth rule',
      p_transaction_type => 'expense',
      p_template => jsonb_build_object(
        'amount_minor', 1000,
        'source_account_id', %L,
        'category_id', %L
      ),
      p_frequency => 'monthly',
      p_start_date => current_date + 365
    )$$,
    (select value from recurring_quota_ids where key = 'alpha_org'),
    (select value from recurring_quota_ids where key = 'bank'),
    (select value from recurring_quota_ids where key = 'rent_category')
  ),
  'Solo permits its fifth counted recurring rule'
);

select is(
  public.get_usage(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    'max_recurring_rules'
  ),
  5::bigint,
  'Solo reaches its exact recurring-rule boundary'
);

select throws_ok(
  format(
    $$select public.create_recurring_rule(
      p_organization_id => %L,
      p_name => 'Quota sixth rule',
      p_transaction_type => 'expense',
      p_template => jsonb_build_object(
        'amount_minor', 1000,
        'source_account_id', %L,
        'category_id', %L
      ),
      p_frequency => 'monthly',
      p_start_date => current_date + 365
    )$$,
    (select value from recurring_quota_ids where key = 'alpha_org'),
    (select value from recurring_quota_ids where key = 'bank'),
    (select value from recurring_quota_ids where key = 'rent_category')
  ),
  'P0001',
  'PLAN_RECURRING_LIMIT_REACHED: usage 5, requested 1, limit 5',
  'creation above the Solo limit returns the stable quota error'
);

reset role;
select throws_ok(
  format(
    $$insert into public.recurring_rules (
      organization_id, name, transaction_type, template, frequency,
      start_date, next_run_on, status
    ) values (%L, 'Privileged live bypass', 'expense', '{}', 'monthly',
      current_date + 365, current_date + 365, 'active')$$,
    (select value from recurring_quota_ids where key = 'alpha_org')
  ),
  'P0001',
  'PLAN_RECURRING_LIMIT_REACHED: usage 5, requested 1, limit 5',
  'the table trigger blocks privileged live-rule inserts at the exact limit'
);

select lives_ok(
  format(
    $$insert into public.recurring_rules (
      organization_id, name, transaction_type, template, frequency,
      start_date, next_run_on, status
    ) values (%L, 'Quota completed history', 'expense', '{}', 'monthly',
      current_date + 365, current_date + 365, 'completed')$$,
    (select value from recurring_quota_ids where key = 'alpha_org')
  ),
  'completed history can be inserted without consuming capacity'
);

select is(
  app.plan_quota_usage(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    'max_recurring_rules'
  ),
  5::bigint,
  'completed history remains excluded from usage'
);

set local role authenticated;
select lives_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota active A'),
    'paused'
  ),
  'active-to-paused remains allowed at the limit'
);

select is(
  public.get_usage(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    'max_recurring_rules'
  ),
  5::bigint,
  'active-to-paused does not change usage'
);

select lives_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota active A'),
    'failed'
  ),
  'paused-to-failed remains allowed at the limit'
);

select is(
  public.get_usage(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    'max_recurring_rules'
  ),
  5::bigint,
  'paused-to-failed does not change usage'
);

select lives_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota active A'),
    'completed'
  ),
  'failed-to-completed releases capacity'
);

select is(
  public.get_usage(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    'max_recurring_rules'
  ),
  4::bigint,
  'completed transition reduces usage'
);

select lives_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota active A'),
    'active'
  ),
  'completed-to-active reactivation succeeds when capacity exists'
);

select is(
  public.get_usage(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    'max_recurring_rules'
  ),
  5::bigint,
  'reactivation consumes the released capacity'
);

select throws_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota completed E'),
    'active'
  ),
  'P0001',
  'PLAN_RECURRING_LIMIT_REACHED: usage 5, requested 1, limit 5',
  'completed-to-active is blocked at the limit'
);

select throws_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota completed E'),
    'paused'
  ),
  'P0001',
  'PLAN_RECURRING_LIMIT_REACHED: usage 5, requested 1, limit 5',
  'completed-to-paused is blocked at the limit'
);

select throws_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota completed E'),
    'failed'
  ),
  'P0001',
  'PLAN_RECURRING_LIMIT_REACHED: usage 5, requested 1, limit 5',
  'completed-to-failed is blocked at the limit'
);

select lives_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota active D'),
    'completed'
  ),
  'active-to-completed is always allowed'
);

select is(
  public.get_usage(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    'max_recurring_rules'
  ),
  4::bigint,
  'active-to-completed releases one slot'
);

select lives_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota completed E'),
    'paused'
  ),
  'completed-to-paused consumes available capacity'
);

select is(
  public.get_usage(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    'max_recurring_rules'
  ),
  5::bigint,
  'completed-to-paused counts as a live rule'
);

select lives_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota completed E'),
    'completed'
  ),
  'paused-to-completed releases capacity for scheduler coverage'
);

select lives_ok(
  format(
    $$select public.create_recurring_rule(
      p_organization_id => %L,
      p_name => 'Quota scheduler rule',
      p_transaction_type => 'expense',
      p_template => jsonb_build_object(
        'amount_minor', 1000,
        'source_account_id', %L,
        'category_id', %L,
        'description', 'Quota scheduler expense'
      ),
      p_frequency => 'monthly',
      p_start_date => current_date,
      p_max_occurrences => 1,
      p_mode => 'auto_post'
    )$$,
    (select value from recurring_quota_ids where key = 'alpha_org'),
    (select value from recurring_quota_ids where key = 'bank'),
    (select value from recurring_quota_ids where key = 'rent_category')
  ),
  'a scheduler-compatible rule can consume the available slot'
);

select is(
  (select count(*) from public.run_recurring_schedule(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    current_date
  )),
  1::bigint,
  'the scheduler processes the quota-protected rule normally'
);

select is(
  (select status from public.recurring_rules where name = 'Quota scheduler rule'),
  'completed'::public.recurring_status,
  'the scheduler can complete a rule and release capacity'
);

select ok(
  (select status = 'posted' and transaction_id is not null
   from public.recurring_occurrences
   where rule_id = (select id from public.recurring_rules
                    where name = 'Quota scheduler rule')),
  'the scheduler still creates and posts its occurrence'
);

select lives_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota scheduler rule'),
    'active'
  ),
  'a completed scheduler rule can reactivate when capacity exists'
);

select is(
  (select count(*) from public.recurring_occurrences
   where rule_id = (select id from public.recurring_rules
                    where name = 'Quota scheduler rule')),
  1::bigint,
  'reactivation preserves the generated occurrence'
);

select is(
  (select count(*) from public.transactions
   where id = (select transaction_id from public.recurring_occurrences
               where rule_id = (select id from public.recurring_rules
                                where name = 'Quota scheduler rule'))),
  1::bigint,
  'reactivation preserves the generated transaction'
);

select public.set_recurring_rule_status(
  (select id from public.recurring_rules where name = 'Quota scheduler rule'),
  'completed'
);

reset role;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from recurring_quota_ids where key = 'alpha_org');

insert into public.recurring_rules (
  organization_id, name, transaction_type, template, frequency,
  start_date, next_run_on, status, created_by
)
values
  ((select value from recurring_quota_ids where key = 'alpha_org'),
   'Quota downgrade active', 'expense', '{}'::jsonb, 'monthly', current_date + 365,
   current_date + 365, 'active', 'a0000000-0000-4000-8000-000000000001'),
  ((select value from recurring_quota_ids where key = 'alpha_org'),
   'Quota downgrade second', 'expense', '{}'::jsonb, 'monthly', current_date + 365,
   current_date + 365, 'active', 'a0000000-0000-4000-8000-000000000001');

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from recurring_quota_ids where key = 'alpha_org');

set local role authenticated;
select is(
  public.get_usage(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    'max_recurring_rules'
  ),
  6::bigint,
  'downgrade reports existing live usage above the new limit'
);

select lives_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota downgrade active'),
    'paused'
  ),
  'live-to-live status changes remain available while over limit'
);

select is(
  public.get_usage(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    'max_recurring_rules'
  ),
  6::bigint,
  'live-to-live changes do not alter over-limit usage'
);

select throws_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota scheduler rule'),
    'active'
  ),
  'P0001',
  'PLAN_RECURRING_LIMIT_REACHED: usage 6, requested 1, limit 5',
  'downgrade blocks completed-to-live reactivation while over limit'
);

select lives_ok(
  format(
    'select public.set_recurring_rule_status(%L, %L)',
    (select id from public.recurring_rules where name = 'Quota downgrade second'),
    'completed'
  ),
  'a status change that reduces usage remains available after downgrade'
);

select is(
  public.get_usage(
    (select value from recurring_quota_ids where key = 'alpha_org'),
    'max_recurring_rules'
  ),
  5::bigint,
  'usage reduction returns the downgraded organization to its limit'
);

select is(
  (select count(*) from public.recurring_rules
   where organization_id = (select value from recurring_quota_ids where key = 'alpha_org')
     and name like 'Quota %'),
  10::bigint,
  'all recurring-rule history remains readable after downgrade'
);

select is(
  (select count(*) from public.recurring_occurrences occurrence
   join public.transactions transaction on transaction.id = occurrence.transaction_id
   where occurrence.rule_id = (select id from public.recurring_rules
                               where name = 'Quota scheduler rule')),
  1::bigint,
  'downgrade preserves generated occurrences and transactions'
);

-- Two sessions compete to reactivate the final two completed rules for a
-- four-of-five Solo tenant. Only the lock owner can consume the last slot.
reset role;
select extensions.dblink_connect(
  'recurring_race_1',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_connect(
  'recurring_race_2',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);

select extensions.dblink_exec(
  'recurring_race_1',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
      where organization_id = %L$$,
    (select value from recurring_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_exec(
  'recurring_race_1',
  format(
    $$insert into public.recurring_rules (
      organization_id, name, transaction_type, template, frequency,
      start_date, next_run_on, status, created_by
    )
    select %L, format('Race recurring %%s', n), 'expense', '{}', 'monthly',
      current_date + 365, current_date + 365,
      case when n <= 4 then 'active'::public.recurring_status
           else 'completed'::public.recurring_status end,
      'b0000000-0000-4000-8000-000000000001'
    from generate_series(1, 6) n$$,
    (select value from recurring_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_exec(
  'recurring_race_1',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'solo')
      where organization_id = %L$$,
    (select value from recurring_quota_ids where key = 'beta_org')
  )
);

select extensions.dblink_exec('recurring_race_1', 'begin');
select extensions.dblink_exec(
  'recurring_race_1',
  format(
    $$do $block$ begin
      perform app.lock_plan_quota(%L, 'max_recurring_rules');
    end $block$;$$,
    (select value from recurring_quota_ids where key = 'beta_org')
  )
);

select extensions.dblink_exec(
  'recurring_race_1',
  $$do $block$ begin
      perform set_config(
        'request.jwt.claims',
        '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
        false
      );
    end $block$;$$
);
select extensions.dblink_exec('recurring_race_1', 'set role authenticated');
select extensions.dblink_exec(
  'recurring_race_2',
  $$do $block$ begin
      perform set_config(
        'request.jwt.claims',
        '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
        false
      );
    end $block$;$$
);
select extensions.dblink_exec('recurring_race_2', 'set role authenticated');

select extensions.dblink_send_query(
  'recurring_race_2',
  format(
    $$select public.set_recurring_rule_status(
      (select id from public.recurring_rules
       where organization_id = %L and name = 'Race recurring 6'),
      'active'
    )$$,
    (select value from recurring_quota_ids where key = 'beta_org')
  )
);

select is(
  extensions.dblink_is_busy('recurring_race_2'),
  1,
  'a concurrent completed-to-live transition waits on the quota lock'
);

select lives_ok(
  format(
    $$select * from extensions.dblink('recurring_race_1', %L)
      as transition(rule_id uuid)$$,
    format(
      $$select public.set_recurring_rule_status(
        (select id from public.recurring_rules
         where organization_id = %L and name = 'Race recurring 5'),
        'active'
      )$$,
      (select value from recurring_quota_ids where key = 'beta_org')
    )
  ),
  'the lock owner consumes the final recurring-rule slot'
);

select extensions.dblink_exec('recurring_race_1', 'commit');
select *
from extensions.dblink_get_result('recurring_race_2', false)
  as result(rule_id uuid);

select is(
  (select count(*) from public.recurring_rules
   where organization_id = (select value from recurring_quota_ids where key = 'beta_org')
     and name like 'Race recurring %'
     and status in ('active', 'paused', 'failed')),
  5::bigint,
  'only one concurrent reactivation consumes the final slot'
);

select ok(
  extensions.dblink_error_message('recurring_race_2')
    like '%PLAN_RECURRING_LIMIT_REACHED:%',
  'the losing reactivation receives the stable recurring-limit error'
);

select is(
  (select status from public.recurring_rules
   where organization_id = (select value from recurring_quota_ids where key = 'beta_org')
     and name = 'Race recurring 6'),
  'completed'::public.recurring_status,
  'the losing rule remains completed'
);

select is(
  app.plan_quota_usage(
    (select value from recurring_quota_ids where key = 'beta_org'),
    'max_recurring_rules'
  ),
  5::bigint,
  'concurrent reactivation cannot overbook recurring-rule capacity'
);

select extensions.dblink_exec('recurring_race_1', 'reset role');
select extensions.dblink_exec(
  'recurring_race_1',
  format(
    $$delete from public.recurring_rules
      where organization_id = %L and name like 'Race recurring %%'$$,
    (select value from recurring_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_exec(
  'recurring_race_1',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
      where organization_id = %L$$,
    (select value from recurring_quota_ids where key = 'beta_org')
  )
);
select extensions.dblink_disconnect('recurring_race_1');
select extensions.dblink_disconnect('recurring_race_2');

select * from finish();
rollback;
