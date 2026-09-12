-- Plan-aware, tenant-safe audit history remains backed by immutable records.
begin;

create extension if not exists pgtap with schema extensions;
select plan(17);

create temp table audit_test_ids (key text primary key, value uuid not null);
grant all on audit_test_ids to authenticated, service_role;

insert into audit_test_ids select 'alpha_org', id from public.organizations where name = 'Alpha Trading';
insert into audit_test_ids select 'beta_org', id from public.organizations where name = 'Beta Supplies';

insert into public.audit_logs (
  organization_id, actor_id, actor_email, action, entity_type, entity_id,
  metadata, created_at
)
values
  ((select value from audit_test_ids where key = 'alpha_org'), null, 'recent@example.test',
   'audit.recent', 'test_record', gen_random_uuid(), '{"step16":true}', transaction_timestamp() - interval '1 day'),
  ((select value from audit_test_ids where key = 'alpha_org'), null, 'solo-boundary@example.test',
   'audit.solo_boundary', 'test_record', gen_random_uuid(), '{"step16":true}', transaction_timestamp() - interval '90 days'),
  ((select value from audit_test_ids where key = 'alpha_org'), null, 'solo-old@example.test',
   'audit.solo_old', 'test_record', gen_random_uuid(), '{"step16":true}', transaction_timestamp() - interval '90 days 1 microsecond'),
  ((select value from audit_test_ids where key = 'alpha_org'), null, 'starter-boundary@example.test',
   'audit.starter_boundary', 'test_record', gen_random_uuid(), '{"step16":true}', transaction_timestamp() - interval '365 days'),
  ((select value from audit_test_ids where key = 'alpha_org'), null, 'starter-old@example.test',
   'audit.starter_old', 'test_record', gen_random_uuid(), '{"step16":true}', transaction_timestamp() - interval '365 days 1 microsecond'),
  ((select value from audit_test_ids where key = 'alpha_org'), null, 'business-boundary@example.test',
   'audit.business_boundary', 'test_record', gen_random_uuid(), '{"step16":true}', transaction_timestamp() - interval '1095 days'),
  ((select value from audit_test_ids where key = 'beta_org'), null, 'beta-only@example.test',
   'audit.recent', 'test_record', gen_random_uuid(), '{"step16":true}', transaction_timestamp() - interval '1 day');

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from audit_test_ids where key = 'alpha_org');

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true
);
set local role authenticated;

select is(
  public.audit_history_window_days((select value from audit_test_ids where key = 'alpha_org')),
  90::bigint,
  'Solo exposes a 90-day audit-history window');
select is(
  (select count(*) from public.list_audit_history(
    (select value from audit_test_ids where key = 'alpha_org'), 100
  ) where action = 'audit.recent'),
  1::bigint,
  'the query returns recent records only for the requested tenant');
select is(
  (select count(*) from public.list_audit_history(
    (select value from audit_test_ids where key = 'alpha_org'), 100
  ) where action = 'audit.solo_boundary'),
  1::bigint,
  'the exact Solo boundary timestamp remains visible');
select is(
  (select count(*) from public.list_audit_history(
    (select value from audit_test_ids where key = 'alpha_org'), 100
  ) where action = 'audit.solo_old'),
  0::bigint,
  'a timestamp immediately outside the Solo boundary is hidden');
select is(
  (select count(*) from public.list_audit_history(
    (select value from audit_test_ids where key = 'alpha_org'), 100
  ) where actor_email = 'beta-only@example.test'),
  0::bigint,
  'another tenant audit record never enters the result');
select throws_ok(
  $$select count(*) from public.audit_logs$$,
  '42501', 'permission denied for table audit_logs',
  'authenticated direct table reads cannot bypass the visibility RPC');

reset role;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'starter')
where organization_id = (select value from audit_test_ids where key = 'alpha_org');
set local role authenticated;

select is(
  public.audit_history_window_days((select value from audit_test_ids where key = 'alpha_org')),
  365::bigint,
  'Starter exposes a 365-day audit-history window');
select is(
  (select count(*) from public.list_audit_history(
    (select value from audit_test_ids where key = 'alpha_org'), 100
  ) where action = 'audit.starter_boundary'),
  1::bigint,
  'the exact Starter boundary timestamp remains visible');
select is(
  (select count(*) from public.list_audit_history(
    (select value from audit_test_ids where key = 'alpha_org'), 100
  ) where action = 'audit.starter_old'),
  0::bigint,
  'a timestamp immediately outside the Starter boundary is hidden');

reset role;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'business')
where organization_id = (select value from audit_test_ids where key = 'alpha_org');
set local role authenticated;

select is(
  public.audit_history_window_days((select value from audit_test_ids where key = 'alpha_org')),
  1095::bigint,
  'Business exposes a 1095-day audit-history window');
select is(
  (select count(*) from public.list_audit_history(
    (select value from audit_test_ids where key = 'alpha_org'), 100
  ) where action = 'audit.business_boundary'),
  1::bigint,
  'the exact Business boundary timestamp remains visible');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}', true
);
set local role authenticated;
select throws_ok(
  format($sql$select public.list_audit_history(%L, 50)$sql$,
    (select value from audit_test_ids where key = 'alpha_org')),
  '42501', 'TENANT_ACCESS_DENIED: not a member of this organization',
  'another tenant cannot query the audit history');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}', true
);
set local role authenticated;
select throws_ok(
  format($sql$select public.list_audit_history(%L, 50)$sql$,
    (select value from audit_test_ids where key = 'alpha_org')),
  '42501', 'INSUFFICIENT_PERMISSION: audit.read is required',
  'a role without audit.read cannot query the audit history');

reset role;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from audit_test_ids where key = 'alpha_org');
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true
);
set local role authenticated;
select is(
  (select count(*) from public.list_audit_history(
    (select value from audit_test_ids where key = 'alpha_org'), 100
  ) where action = 'audit.starter_boundary'),
  0::bigint,
  'downgrading immediately narrows visibility without deleting history');

reset role;
select is(
  (select count(*) from public.audit_logs
   where organization_id = (select value from audit_test_ids where key = 'alpha_org')
     and metadata ->> 'step16' = 'true'),
  6::bigint,
  'all underlying audit records remain stored after downgrade');
select throws_ok(
  $$update public.audit_logs set actor_email = 'changed@example.test' where metadata ->> 'step16' = 'true'$$,
  '42501', 'IMMUTABLE_RECORD: audit_logs rows cannot be modified or deleted',
  'underlying audit records remain immutable on update');
select throws_ok(
  $$delete from public.audit_logs where metadata ->> 'step16' = 'true'$$,
  '42501', 'IMMUTABLE_RECORD: audit_logs rows cannot be modified or deleted',
  'underlying audit records remain immutable on delete');

select * from finish();
rollback;
