-- Step 22: cross-resource plan-transition locking and bypass inventory.
begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select plan(33);

create temp table hardening_ids (key text primary key, value uuid not null);
insert into hardening_ids
select 'organization', id from public.organizations where name = 'Alpha Trading';
grant select on hardening_ids to authenticated;

select has_function(
  'app', 'lock_all_plan_quotas', array['uuid'],
  'a canonical all-quota transition lock exists'
);

select trigger_is(
  'public', 'subscriptions', 'subscriptions_lock_plan_change',
  'app', 'lock_subscription_plan_change',
  'subscription plan changes use the transition lock trigger'
);

select ok(
  not has_function_privilege(
    'authenticated', 'app.lock_all_plan_quotas(uuid)', 'EXECUTE'
  ),
  'clients cannot invoke the internal all-quota lock'
);

select ok(
  not has_function_privilege(
    'authenticated', 'app.lock_subscription_plan_change()', 'EXECUTE'
  ),
  'clients cannot invoke the subscription trigger function'
);

select has_function(
  'app', 'plan_feature_transition_lock_key', array['uuid'],
  'an organization-scoped feature transition lock key exists'
);

select has_function(
  'app', 'lock_plan_feature_transition', array['uuid'],
  'an organization-scoped feature transition lock exists'
);

select ok(
  not has_function_privilege(
    'authenticated', 'app.plan_feature_transition_lock_key(uuid)', 'EXECUTE'
  ) and not has_function_privilege(
    'authenticated', 'app.lock_plan_feature_transition(uuid)', 'EXECUTE'
  ),
  'clients cannot invoke internal feature-transition lock helpers'
);

select is(
  (select count(*)
   from pg_catalog.pg_proc function
   join pg_catalog.pg_namespace namespace on namespace.oid = function.pronamespace
   where namespace.nspname || '.' || function.proname in (
     'app.assert_plan_feature',
     'app.assert_write_currency',
     'app.assert_recurring_template_currency',
     'app.validate_csv_import_row',
     'public.export_financial_report_csv'
   ) and function.provolatile = 'v'),
  5::bigint,
  'every function that transitively takes the feature lock is volatile'
);

select ok(
  app.plan_feature_transition_lock_key(
    (select value from hardening_ids where key = 'organization')
  ) <> all (array(
    select app.plan_quota_lock_key(
      (select value from hardening_ids where key = 'organization'), quota_key
    )
    from unnest(array[
      'max_accounts', 'max_counterparties', 'max_custom_roles', 'max_members',
      'max_monthly_transactions', 'max_recurring_rules', 'max_storage_bytes'
    ]) quota_key
  )),
  'the feature-transition lock is distinct from all seven quota locks'
);

select is(
  (select count(distinct app.plan_quota_lock_key(
     (select value from hardening_ids where key = 'organization'), quota_key
   ))
   from unnest(array[
     'max_accounts', 'max_counterparties', 'max_custom_roles', 'max_members',
     'max_monthly_transactions', 'max_recurring_rules', 'max_storage_bytes'
   ]) quota_key),
  7::bigint,
  'all seven resources use distinct organization quota locks'
);

select is(
  (select count(*)
   from pg_catalog.pg_trigger trigger
   join pg_catalog.pg_class relation on relation.oid = trigger.tgrelid
   join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
   where namespace.nspname = 'public'
     and relation.relname in (
       'organization_members', 'organization_invitations', 'accounts',
       'counterparties', 'recurring_rules', 'organization_roles', 'transactions'
     )
     and trigger.tgname in (
       'organization_members_enforce_seat_quota',
       'organization_invitations_enforce_seat_quota',
       'accounts_enforce_plan_quota',
       'counterparties_enforce_plan_quota',
       'recurring_rules_enforce_plan_quota',
       'organization_roles_enforce_plan_quota',
       'transactions_enforce_monthly_quota'
     )
     and trigger.tgenabled = 'O'
     and not trigger.tgisinternal),
  7::bigint,
  'every row-based quota boundary keeps its authoritative trigger enabled'
);

select ok(
  not has_table_privilege('authenticated', 'public.attachments', 'INSERT')
    and not has_table_privilege('authenticated', 'public.attachments', 'DELETE'),
  'attachment storage cannot bypass its reservation lifecycle through REST'
);

select ok(
  not has_table_privilege('authenticated', 'public.subscriptions', 'UPDATE'),
  'clients cannot bypass provider and service boundaries with direct plan updates'
);

select extensions.dblink_connect(
  'hardening_account_lock',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_connect(
  'hardening_role_lock',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_connect(
  'hardening_plan_change',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_connect(
  'hardening_feature_write',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_connect(
  'hardening_import',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_connect(
  'hardening_scheduler',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);

select extensions.dblink_exec(
  'hardening_plan_change',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'business')
      where organization_id = %L$$,
    (select value from hardening_ids where key = 'organization')
  )
);

select extensions.dblink_exec('hardening_account_lock', 'begin');
select extensions.dblink_exec(
  'hardening_account_lock',
  format(
    $$do $block$ begin
      perform app.lock_plan_quota(%L, 'max_accounts');
    end $block$;$$,
    (select value from hardening_ids where key = 'organization')
  )
);
select extensions.dblink_exec('hardening_role_lock', 'begin');
select extensions.dblink_exec(
  'hardening_role_lock',
  format(
    $$do $block$ begin
      perform app.lock_plan_quota(%L, 'max_custom_roles');
    end $block$;$$,
    (select value from hardening_ids where key = 'organization')
  )
);

select extensions.dblink_send_query(
  'hardening_plan_change',
  format(
    $$with changed as (
      update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'solo')
      where organization_id = %L
      returning 1
    ) select count(*)::bigint from changed$$,
    (select value from hardening_ids where key = 'organization')
  )
);

select is(
  extensions.dblink_is_busy('hardening_plan_change'),
  1,
  'a plan transition waits for an in-flight account quota operation'
);

select extensions.dblink_exec('hardening_account_lock', 'commit');

select is(
  extensions.dblink_is_busy('hardening_plan_change'),
  1,
  'the same transition also waits for a different resource quota operation'
);

select extensions.dblink_exec('hardening_role_lock', 'commit');

select is(
  (select changed from extensions.dblink_get_result('hardening_plan_change')
    as result(changed bigint)),
  1::bigint,
  'the plan transition completes after every resource lock is released'
);
select extensions.dblink_get_result('hardening_plan_change');

select is(
  (select plan.key
   from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   where subscription.organization_id =
     (select value from hardening_ids where key = 'organization')),
  'solo',
  'the serialized transition applies the target plan once'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  format(
    $$select public.create_organization_role(
      %L, 'stale_client_role', 'Stale client role', 'دور عميل قديم',
      array['organization.read']
    )$$,
    (select value from hardening_ids where key = 'organization')
  ),
  'P0001', 'PLAN_CUSTOM_ROLE_LIMIT_REACHED: usage 0, requested 1, limit 0',
  'a stale client is evaluated against the newly committed Solo boundary'
);

reset role;
select is(
  (select count(*) from public.organization_roles
   where organization_id = (select value from hardening_ids where key = 'organization')
     and key = 'stale_client_role'),
  0::bigint,
  'the rejected stale write creates no resource row'
);

-- Build committed fixtures through a trusted session so the independent race
-- sessions can see them. Everything is removed again before the test ends.
select extensions.dblink_exec(
  'hardening_plan_change',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'business')
      where organization_id = %L$$,
    (select value from hardening_ids where key = 'organization')
  )
);
select extensions.dblink_exec(
  'hardening_plan_change',
  format(
    $$do $block$ begin
      insert into public.accounts (
        id, organization_id, code, name, type, subtype, currency, created_by
      ) values
        (
          '26000000-0000-4000-8000-000000000001', %L, 'S22USD',
          'Step 22 USD bank', 'asset', 'bank', 'USD',
          'a0000000-0000-4000-8000-000000000001'
        ),
        (
          '26000000-0000-4000-8000-000000000005', %L, 'S22RENT',
          'Step 22 rent expense', 'expense', 'rent', 'EGP',
          'a0000000-0000-4000-8000-000000000001'
        );
      insert into public.categories (
        id, organization_id, name, kind, default_account_id, created_by
      ) values (
        '26000000-0000-4000-8000-000000000006', %L,
        'Step 22 Rent', 'expense',
        '26000000-0000-4000-8000-000000000005',
        'a0000000-0000-4000-8000-000000000001'
      );
      insert into public.import_batches (
        id, organization_id, filename, status, created_by, validated_at
      ) values (
        '26000000-0000-4000-8000-000000000002', %L,
        'step22-confirm.csv', 'validated',
        'a0000000-0000-4000-8000-000000000001', now()
      );
      insert into public.recurring_rules (
        id, organization_id, name, transaction_type, template, frequency,
        start_date, max_occurrences, mode, status, created_by
      ) values (
        '26000000-0000-4000-8000-000000000003', %L,
        'Step 22 foreign scheduler', 'expense',
        jsonb_build_object(
          'amount_minor', 1000,
          'source_account_id', '26000000-0000-4000-8000-000000000001',
          'category_id', '26000000-0000-4000-8000-000000000006',
          'currency_code', 'USD', 'exchange_rate', 50
        ),
        'monthly', current_date, 1, 'auto_post', 'active',
        'a0000000-0000-4000-8000-000000000001'
      );
    end $block$;$$,
    (select value from hardening_ids where key = 'organization'),
    (select value from hardening_ids where key = 'organization'),
    (select value from hardening_ids where key = 'organization'),
    (select value from hardening_ids where key = 'organization'),
    (select value from hardening_ids where key = 'organization')
  )
);

select extensions.dblink_exec(
  'hardening_import',
  $$set "request.jwt.claims" =
    '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}'$$
);
select extensions.dblink_exec('hardening_import', 'set role authenticated');
select extensions.dblink_exec(
  'hardening_scheduler',
  $$set "request.jwt.claims" =
    '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}'$$
);
select extensions.dblink_exec('hardening_scheduler', 'set role authenticated');

-- A physical downgrade that owns the canonical locks goes first. The real
-- commitment insert must wait, then evaluate multi-currency against Starter.
select extensions.dblink_exec('hardening_plan_change', 'begin');
select extensions.dblink_exec(
  'hardening_plan_change',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'starter')
      where organization_id = %L$$,
    (select value from hardening_ids where key = 'organization')
  )
);
select extensions.dblink_send_query(
  'hardening_feature_write',
  format(
    $$insert into public.commitments (
        id, organization_id, type, status, title, amount_minor,
        currency_code, due_date, original_due_date
      ) values (
        '26000000-0000-4000-8000-000000000004', %L, 'payable',
        'upcoming', 'Forbidden racing USD commitment', 1000,
        'USD', current_date + 1, current_date + 1
      ) returning id$$,
    (select value from hardening_ids where key = 'organization')
  )
);
select is(
  extensions.dblink_is_busy('hardening_feature_write'), 1,
  'a foreign-currency commitment waits behind an in-flight downgrade'
);
select extensions.dblink_exec('hardening_plan_change', 'commit');
select throws_ok(
  $$select * from extensions.dblink_get_result('hardening_feature_write')
    as result(id uuid)$$,
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'the waiting commitment is evaluated against Starter and rejected'
);
select is(
  (select count(*) from public.commitments
   where id = '26000000-0000-4000-8000-000000000004'),
  0::bigint,
  'no forbidden FX commitment commits after the downgrade'
);

-- CSV staging is feature-only and therefore waits on the shared feature lock.
select extensions.dblink_exec(
  'hardening_plan_change',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'starter')
      where organization_id = %L$$,
    (select value from hardening_ids where key = 'organization')
  )
);
select extensions.dblink_exec('hardening_plan_change', 'begin');
select extensions.dblink_exec(
  'hardening_plan_change',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'solo')
      where organization_id = %L$$,
    (select value from hardening_ids where key = 'organization')
  )
);
select extensions.dblink_send_query(
  'hardening_import',
  format(
    $$select public.create_csv_import_batch(
      %L, 'step22-stage.csv', '[{"kind":"income"}]'::jsonb
    )$$,
    (select value from hardening_ids where key = 'organization')
  )
);
select is(
  extensions.dblink_is_busy('hardening_import'), 1,
  'CSV staging waits behind an in-flight imports downgrade'
);
select extensions.dblink_exec('hardening_plan_change', 'commit');
select throws_ok(
  $$select * from extensions.dblink_get_result('hardening_import')
    as result(batch_id uuid)$$,
  'P0001', 'FEATURE_NOT_AVAILABLE_ON_PLAN: imports',
  'waiting CSV staging is rejected against the downgraded plan'
);
select is(
  (select count(*) from public.import_batches where filename = 'step22-stage.csv'),
  0::bigint,
  'the rejected staging call persists no import batch'
);

-- A failed asynchronous query must be fully cleared before this connection is
-- reused for the independent confirmation race.
select extensions.dblink_disconnect('hardening_import');
select extensions.dblink_connect(
  'hardening_import',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_exec(
  'hardening_import',
  $$set "request.jwt.claims" =
    '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}'$$
);
select extensions.dblink_exec('hardening_import', 'set role authenticated');

-- Confirmation takes the transaction quota lock before the imports feature
-- lock, so it shares the transition's deadlock-safe canonical order.
select extensions.dblink_exec(
  'hardening_plan_change',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'starter')
      where organization_id = %L$$,
    (select value from hardening_ids where key = 'organization')
  )
);
select extensions.dblink_exec('hardening_plan_change', 'begin');
select extensions.dblink_exec(
  'hardening_plan_change',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'solo')
      where organization_id = %L$$,
    (select value from hardening_ids where key = 'organization')
  )
);
select extensions.dblink_send_query(
  'hardening_import',
  $$select public.confirm_csv_import_batch(
    '26000000-0000-4000-8000-000000000002'
  )$$
);
select is(
  extensions.dblink_is_busy('hardening_import'), 1,
  'CSV confirmation waits behind the transition quota locks'
);
select extensions.dblink_exec('hardening_plan_change', 'commit');
select throws_ok(
  $$select * from extensions.dblink_get_result('hardening_import')
    as result(summary jsonb)$$,
  'P0001', 'FEATURE_NOT_AVAILABLE_ON_PLAN: imports',
  'waiting CSV confirmation rechecks imports after the downgrade'
);
select is(
  (select status from public.import_batches
   where id = '26000000-0000-4000-8000-000000000002'),
  'validated',
  'rejected confirmation leaves the validated batch unmodified'
);

-- The actual scheduler reaches the ordinary transaction quota and currency
-- guards. It waits for the transition, then records a failed occurrence rather
-- than committing a foreign transaction under Starter.
select extensions.dblink_exec(
  'hardening_plan_change',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'business')
      where organization_id = %L$$,
    (select value from hardening_ids where key = 'organization')
  )
);
select extensions.dblink_exec('hardening_plan_change', 'begin');
select extensions.dblink_exec(
  'hardening_plan_change',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'starter')
      where organization_id = %L$$,
    (select value from hardening_ids where key = 'organization')
  )
);
select extensions.dblink_send_query(
  'hardening_scheduler',
  format(
    $$select * from public.run_recurring_schedule(%L, current_date)$$,
    (select value from hardening_ids where key = 'organization')
  )
);
select is(
  extensions.dblink_is_busy('hardening_scheduler'), 1,
  'the recurring scheduler waits behind an in-flight plan transition'
);
select extensions.dblink_exec('hardening_plan_change', 'commit');
select throws_ok(
  $$select * from extensions.dblink_get_result('hardening_scheduler') as result(
    rule_id uuid,
    occurrence_date date,
    status public.occurrence_status,
    transaction_id uuid,
    message text
  )$$,
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'the resumed scheduler is rejected against the target plan'
);
select is(
  (select count(*) from public.recurring_occurrences
   where rule_id = '26000000-0000-4000-8000-000000000003'),
  0::bigint,
  'the rejected scheduler call leaves no occurrence behind'
);
select is(
  (select count(*) from public.transactions
   where idempotency_key like
     'recurring:26000000-0000-4000-8000-000000000003:%'),
  0::bigint,
  'the scheduler race commits no forbidden foreign transaction'
);

-- Remove committed cross-session fixtures before restoring the compatibility
-- subscription used by the shared seed.
select extensions.dblink_exec(
  'hardening_plan_change',
  format(
    $$do $block$ begin
      delete from public.notifications
      where organization_id = %L and entity_id = '26000000-0000-4000-8000-000000000003';
      delete from public.recurring_rules
      where id = '26000000-0000-4000-8000-000000000003';
      delete from public.import_batches
      where id = '26000000-0000-4000-8000-000000000002';
      delete from public.commitments
      where organization_id = %L and title like '%%Step 22%%';
      delete from public.categories
      where id = '26000000-0000-4000-8000-000000000006';
      delete from public.accounts
      where id in (
        '26000000-0000-4000-8000-000000000001',
        '26000000-0000-4000-8000-000000000005'
      );
    end $block$;$$,
    (select value from hardening_ids where key = 'organization'),
    (select value from hardening_ids where key = 'organization')
  )
);

select extensions.dblink_exec(
  'hardening_plan_change',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
      where organization_id = %L$$,
    (select value from hardening_ids where key = 'organization')
  )
);

select is(
  (select plan.key
   from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   where subscription.organization_id =
     (select value from hardening_ids where key = 'organization')),
  'ledger_suit',
  'the committed seed subscription is restored after the race test'
);

select extensions.dblink_disconnect('hardening_account_lock');
select extensions.dblink_disconnect('hardening_role_lock');
select extensions.dblink_disconnect('hardening_plan_change');
select extensions.dblink_disconnect('hardening_feature_write');
select extensions.dblink_disconnect('hardening_import');
select extensions.dblink_disconnect('hardening_scheduler');

select * from finish();
rollback;
