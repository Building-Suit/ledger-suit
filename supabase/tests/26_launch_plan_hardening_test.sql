-- Step 22: cross-resource plan-transition locking and bypass inventory.
begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select plan(15);

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

select * from finish();
rollback;
