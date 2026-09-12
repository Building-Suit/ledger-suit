-- Tenant-safe, recoverable CSV import staging, validation, and confirmation.
begin;

create extension if not exists pgtap with schema extensions;
select plan(34);

create temp table import_test_ids (key text primary key, value uuid not null);
grant all on import_test_ids to authenticated, service_role;

insert into import_test_ids select 'alpha_org', id from public.organizations where name = 'Alpha Trading';
insert into import_test_ids select 'beta_org', id from public.organizations where name = 'Beta Supplies';

update public.subscriptions set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id in (
  (select value from import_test_ids where key = 'alpha_org'),
  (select value from import_test_ids where key = 'beta_org')
);
select app.seed_chart_of_accounts((select value from import_test_ids where key = 'alpha_org'));
select app.seed_categories((select value from import_test_ids where key = 'alpha_org'));
select app.seed_chart_of_accounts((select value from import_test_ids where key = 'beta_org'));

insert into import_test_ids
select 'alpha_bank', id from public.accounts
where organization_id = (select value from import_test_ids where key = 'alpha_org') and system_key = 'bank';
insert into import_test_ids
select 'beta_bank', id from public.accounts
where organization_id = (select value from import_test_ids where key = 'beta_org') and system_key = 'bank';
insert into import_test_ids
select 'income_category', id from public.categories
where organization_id = (select value from import_test_ids where key = 'alpha_org')
  and kind = 'income' and is_active order by name limit 1;
insert into import_test_ids
select 'income_account', default_account_id from public.categories
where id = (select value from import_test_ids where key = 'income_category');
insert into import_test_ids
select 'expense_account', default_account_id from public.categories
where organization_id = (select value from import_test_ids where key = 'alpha_org')
  and kind = 'expense' and is_active and default_account_id is not null
order by name limit 1;

update public.subscriptions set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from import_test_ids where key = 'alpha_org');

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true
);
set local role authenticated;

select throws_ok(
  format($sql$select public.create_csv_import_batch(%L, 'solo.csv', '[{}]'::jsonb)$sql$,
    (select value from import_test_ids where key = 'alpha_org')),
  'P0001', 'FEATURE_NOT_AVAILABLE_ON_PLAN: imports',
  'Solo cannot stage a CSV import through the server API');

reset role;
update public.subscriptions set plan_id = (select id from public.subscription_plans where key = 'starter')
where organization_id = (select value from import_test_ids where key = 'alpha_org');
set local role authenticated;

select throws_ok(
  format($sql$select public.create_csv_import_batch(%L, 'not-csv.txt', '[{}]'::jsonb)$sql$,
    (select value from import_test_ids where key = 'alpha_org')),
  '22023', 'IMPORT_FILE_INVALID: a CSV filename is required',
  'non-CSV input is rejected before staging');
select throws_ok(
  format($sql$select public.create_csv_import_batch(%L, 'bad-row.csv', '[1]'::jsonb)$sql$,
    (select value from import_test_ids where key = 'alpha_org')),
  '22023', 'IMPORT_FILE_INVALID: row 1 must be an object under 64 KiB',
  'malformed row payloads fail atomically');

insert into import_test_ids
select 'mixed_batch', public.create_csv_import_batch(
  (select value from import_test_ids where key = 'alpha_org'), 'mixed.csv',
  jsonb_build_array(
    jsonb_build_object('kind', 'income', 'date', '2026-09-01', 'amount', '10.00',
      'account', (select value from import_test_ids where key = 'alpha_bank'),
      'category', (select value from import_test_ids where key = 'income_category'),
      'description', 'Valid imported income', 'currency', 'EGP'),
    jsonb_build_object('kind', 'income', 'date', '2026-09-02', 'amount', 'bad',
      'account', (select value from import_test_ids where key = 'alpha_bank'),
      'category', (select value from import_test_ids where key = 'income_category')),
    jsonb_build_object('kind', 'income', 'date', '2026-09-01', 'amount', '10.00',
      'account', (select value from import_test_ids where key = 'alpha_bank'),
      'category', (select value from import_test_ids where key = 'income_category'),
      'description', 'Valid imported income', 'currency', 'EGP'),
    jsonb_build_object('kind', 'income', 'date', '2026-09-03', 'amount', '1.00',
      'account', (select value from import_test_ids where key = 'alpha_bank'),
      'category', (select value from import_test_ids where key = 'income_category'),
      'currency', 'USD', 'rate', '50'),
    jsonb_build_object('kind', 'income', 'date', '2026-09-04', 'amount', '1.00',
      'account', (select value from import_test_ids where key = 'beta_bank'),
      'category', (select value from import_test_ids where key = 'income_category'))
  )
);

select is((select total_rows from public.import_batches where id =
  (select value from import_test_ids where key = 'mixed_batch')), 5,
  'staging preserves every source row for preview');
select is((select status from public.import_batches where id =
  (select value from import_test_ids where key = 'mixed_batch')),
  'staged', 'new batches remain staged until an explicit mapping is validated');
select throws_ok(
  format($sql$select public.validate_csv_import_batch(%L, '{"type":"kind"}'::jsonb)$sql$,
    (select value from import_test_ids where key = 'mixed_batch')),
  '22023', 'IMPORT_MAPPING_INVALID: date is required',
  'mapping validation requires the supported transaction schema');
select lives_ok(
  format($sql$select public.validate_csv_import_batch(%L,
    '{"type":"kind","date":"date","amount":"amount","account":"account",
      "category":"category","description":"description","currency":"currency",
      "exchange_rate":"rate"}'::jsonb)$sql$,
    (select value from import_test_ids where key = 'mixed_batch')),
  'a valid mapping performs row-level validation');
select results_eq(
  format($sql$select valid_rows, invalid_rows, duplicate_rows from public.import_batches where id = %L$sql$,
    (select value from import_test_ids where key = 'mixed_batch')),
  $$values (1, 3, 1)$$,
  'validation separates valid, invalid, and deterministic duplicate rows');
select is((select error_code from public.import_rows where batch_id =
  (select value from import_test_ids where key = 'mixed_batch') and row_number = 2),
  'IMPORT_ROW_AMOUNT_INVALID', 'malformed amounts retain a stable row error');
select is((select error_code from public.import_rows where batch_id =
  (select value from import_test_ids where key = 'mixed_batch') and row_number = 4),
  'MULTI_CURRENCY_REQUIRES_BUSINESS', 'Starter rows cannot bypass multi-currency enforcement');
select is((select error_code from public.import_rows where batch_id =
  (select value from import_test_ids where key = 'mixed_batch') and row_number = 5),
  'IMPORT_ROW_ACCOUNT_INVALID', 'foreign-tenant account references become row errors');
select throws_ok(
  format('update public.import_batches set filename = %L where id = %L', 'tampered.csv',
    (select value from import_test_ids where key = 'mixed_batch')),
  '42501', null, 'clients cannot mutate staged batch state directly');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}', true
);
set local role authenticated;
select is((select count(*) from public.import_batches where id =
  (select value from import_test_ids where key = 'mixed_batch')), 0::bigint,
  'RLS hides another tenant import batch');
select throws_ok(
  format($sql$select public.validate_csv_import_batch(%L, '{}'::jsonb)$sql$,
    (select value from import_test_ids where key = 'mixed_batch')),
  '42501', 'TENANT_ACCESS_DENIED: not a member of this organization',
  'the validation RPC rejects cross-tenant access');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true
);
update public.subscriptions set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from import_test_ids where key = 'alpha_org');
set local role authenticated;

select is((public.confirm_csv_import_batch(
  (select value from import_test_ids where key = 'mixed_batch')) ->> 'status'),
  'partial', 'confirmation posts valid rows while preserving invalid rows');
select is((select count(*) from public.import_rows where batch_id =
  (select value from import_test_ids where key = 'mixed_batch') and status = 'posted'),
  1::bigint, 'exactly one valid mixed-batch row posts');
select is((select source::text from public.transactions where id =
  (select transaction_id from public.import_rows where batch_id =
    (select value from import_test_ids where key = 'mixed_batch') and status = 'posted')),
  'import', 'confirmed rows reuse the ordinary import posting source');
select is((select count(*) from public.import_rows where batch_id =
  (select value from import_test_ids where key = 'mixed_batch')
  and status = 'invalid' and transaction_id is null), 3::bigint,
  'invalid rows never reach the ledger');
select is((select count(*) from public.audit_logs where entity_id =
  (select value from import_test_ids where key = 'mixed_batch') and action = 'import.confirmed'),
  1::bigint, 'confirmation writes a tenant audit event');
select is((select posted_rows from public.import_batches where id =
  (select value from import_test_ids where key = 'mixed_batch')),
  1, 'confirmed batch counters reflect durable outcomes');

reset role;
update public.subscriptions set plan_id = (select id from public.subscription_plans where key = 'starter')
where organization_id = (select value from import_test_ids where key = 'alpha_org');
update public.subscription_entitlements
set limit_value = app.plan_quota_usage(
  (select value from import_test_ids where key = 'alpha_org'), 'max_monthly_transactions') + 1
where plan_id = (select id from public.subscription_plans where key = 'starter')
  and feature_key = 'max_monthly_transactions';
set local role authenticated;

insert into import_test_ids
select 'quota_batch', public.create_csv_import_batch(
  (select value from import_test_ids where key = 'alpha_org'), 'quota.csv',
  jsonb_build_array(
    jsonb_build_object('kind', 'income', 'date', '2026-09-05', 'amount', '11.00',
      'account', (select value from import_test_ids where key = 'alpha_bank'),
      'category', (select value from import_test_ids where key = 'income_category')),
    jsonb_build_object('kind', 'income', 'date', '2026-09-06', 'amount', '12.00',
      'account', (select value from import_test_ids where key = 'alpha_bank'),
      'category', (select value from import_test_ids where key = 'income_category'))
  )
);
select lives_ok(
  format($sql$select public.validate_csv_import_batch(%L,
    '{"type":"kind","date":"date","amount":"amount","account":"account",
      "category":"category"}'::jsonb)$sql$,
    (select value from import_test_ids where key = 'quota_batch')),
  'quota batch validates before confirmation');
select is((public.confirm_csv_import_batch(
  (select value from import_test_ids where key = 'quota_batch')) ->> 'status'),
  'partial', 'quota exhaustion produces a recoverable partial batch');
select results_eq(
  format($sql$select posted_rows, failed_rows from public.import_batches where id = %L$sql$,
    (select value from import_test_ids where key = 'quota_batch')),
  $$values (1, 1)$$, 'confirmation preserves the successful prefix and failed row');
select is((select error_code from public.import_rows where batch_id =
  (select value from import_test_ids where key = 'quota_batch') and status = 'failed'),
  'PLAN_TRANSACTION_LIMIT_REACHED', 'quota failures remain identifiable for retry');

reset role;
update public.subscription_entitlements set limit_value = limit_value + 1
where plan_id = (select id from public.subscription_plans where key = 'starter')
  and feature_key = 'max_monthly_transactions';
set local role authenticated;
select is((public.confirm_csv_import_batch(
  (select value from import_test_ids where key = 'quota_batch')) ->> 'status'),
  'completed', 'retry posts only the previously failed row when capacity returns');
select results_eq(
  format($sql$select posted_rows, failed_rows from public.import_batches where id = %L$sql$,
    (select value from import_test_ids where key = 'quota_batch')),
  $$values (2, 0)$$, 'retry completes the batch without duplicating its first posting');
select is((select max(attempt_count) from public.import_rows where batch_id =
  (select value from import_test_ids where key = 'quota_batch')),
  2, 'only the failed row records a second posting attempt');

insert into import_test_ids
select 'duplicate_batch', public.create_csv_import_batch(
  (select value from import_test_ids where key = 'alpha_org'), 'duplicate.csv',
  jsonb_build_array(jsonb_build_object(
    'kind', 'income', 'date', '2026-09-05', 'amount', '11.00',
    'account', (select value from import_test_ids where key = 'alpha_bank'),
    'category', (select value from import_test_ids where key = 'income_category')))
);
select public.validate_csv_import_batch(
  (select value from import_test_ids where key = 'duplicate_batch'),
  '{"type":"kind","date":"date","amount":"amount","account":"account",
    "category":"category"}'::jsonb
);
select is((select status from public.import_rows where batch_id =
  (select value from import_test_ids where key = 'duplicate_batch')),
  'duplicate', 'a later batch deterministically recognizes an already-posted row');
select is((public.confirm_csv_import_batch(
  (select value from import_test_ids where key = 'duplicate_batch')) ->> 'status'),
  'completed', 'an all-duplicate batch confirms without posting');
select is((select count(*) from public.transactions where organization_id =
  (select value from import_test_ids where key = 'alpha_org')
  and idempotency_key like 'csv-import:%'), 3::bigint,
  'confirmation and retries produce exactly one transaction per deterministic key');

reset role;
update public.subscriptions set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from import_test_ids where key = 'alpha_org');
set local role authenticated;
insert into import_test_ids
select 'semantic_batch', public.create_csv_import_batch(
  (select value from import_test_ids where key = 'alpha_org'), 'semantic.csv',
  jsonb_build_array(jsonb_build_object(
    'kind', 'income', 'date', '2026-09-07', 'amount', '13.00',
    'account', (select value from import_test_ids where key = 'alpha_bank'),
    'category', (select value from import_test_ids where key = 'income_category')))
);
select public.validate_csv_import_batch(
  (select value from import_test_ids where key = 'semantic_batch'),
  '{"type":"kind","date":"date","amount":"amount","account":"account",
    "category":"category"}'::jsonb
);
reset role;
update public.categories set default_account_id =
  (select value from import_test_ids where key = 'expense_account')
where id = (select value from import_test_ids where key = 'income_category');
set local role authenticated;
select public.confirm_csv_import_batch(
  (select value from import_test_ids where key = 'semantic_batch'));
select is((select error_code from public.import_rows where batch_id =
  (select value from import_test_ids where key = 'semantic_batch')),
  'IMPORT_ROW_CATEGORY_INVALID',
  'confirmation rejects a category whose current ledger account has the wrong type');
select is((select count(*) from public.import_rows where batch_id =
  (select value from import_test_ids where key = 'semantic_batch')
  and transaction_id is not null), 0::bigint,
  'a mutated category relationship cannot produce an imported transaction');

reset role;
update public.categories set default_account_id =
  (select value from import_test_ids where key = 'income_account')
where id = (select value from import_test_ids where key = 'income_category');
update public.subscriptions set plan_id = (select id from public.subscription_plans where key = 'starter')
where organization_id = (select value from import_test_ids where key = 'alpha_org');
set local role authenticated;
insert into import_test_ids
select 'downgrade_batch', public.create_csv_import_batch(
  (select value from import_test_ids where key = 'alpha_org'), 'downgrade.csv',
  jsonb_build_array(jsonb_build_object(
    'kind', 'income', 'date', '2026-09-08', 'amount', '14.00',
    'account', (select value from import_test_ids where key = 'alpha_bank'),
    'category', (select value from import_test_ids where key = 'income_category')))
);
select public.validate_csv_import_batch(
  (select value from import_test_ids where key = 'downgrade_batch'),
  '{"type":"kind","date":"date","amount":"amount","account":"account",
    "category":"category"}'::jsonb
);
reset role;
update public.subscriptions set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from import_test_ids where key = 'alpha_org');
set local role authenticated;
select throws_ok(
  format('select public.confirm_csv_import_batch(%L)',
    (select value from import_test_ids where key = 'downgrade_batch')),
  'P0001', 'FEATURE_NOT_AVAILABLE_ON_PLAN: imports',
  'a batch validated on Starter cannot confirm after downgrade to Solo');
select results_eq(
  format($sql$select status, transaction_id is null from public.import_rows where batch_id = %L$sql$,
    (select value from import_test_ids where key = 'downgrade_batch')),
  $$values ('valid'::text, true)$$,
  'downgrade rejection occurs before any validated row posts');

select * from finish();
rollback;
