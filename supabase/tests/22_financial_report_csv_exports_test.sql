-- Honest, permissioned CSV exports for the five launch financial reports.
begin;

create extension if not exists pgtap with schema extensions;
select plan(11);

create temp table export_test_ids (key text primary key, value uuid not null);
grant all on export_test_ids to authenticated, service_role;

insert into export_test_ids select 'alpha_org', id from public.organizations where name = 'Alpha Trading';
insert into export_test_ids select 'beta_org', id from public.organizations where name = 'Beta Supplies';

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from export_test_ids where key = 'alpha_org');

select app.seed_chart_of_accounts((select value from export_test_ids where key = 'alpha_org'));
select app.seed_categories((select value from export_test_ids where key = 'alpha_org'));

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from export_test_ids where key = 'alpha_org');

insert into export_test_ids
select 'bank', id from public.accounts
where organization_id = (select value from export_test_ids where key = 'alpha_org')
  and system_key = 'bank';
insert into export_test_ids
select 'revenue', id from public.accounts
where organization_id = (select value from export_test_ids where key = 'alpha_org')
  and system_key = 'product_sales';

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true
);
set local role authenticated;

select public.record_income(
  (select value from export_test_ids where key = 'alpha_org'),
  10000,
  (select value from export_test_ids where key = 'bank'),
  p_revenue_account_id => (select value from export_test_ids where key = 'revenue'),
  p_transaction_date => '2026-09-10',
  p_description => 'CSV export fixture'
);

reset role;
update public.accounts set name = 'إيرادات, "محلية"'
where id = (select value from export_test_ids where key = 'revenue');
set local role authenticated;

select is(
  (select description from public.capabilities where key = 'exports.create'),
  'Export financial reports to CSV',
  'the sold export capability is described honestly');

select ok(
  public.export_financial_report_csv(
    (select value from export_test_ids where key = 'alpha_org'),
    'profit_loss', '2026-09-01', '2026-09-30'
  ) like
  E'%"إيرادات, ""محلية""",100.00,EGP%',
  'profit and loss CSV preserves UTF-8 names and escapes CSV punctuation');

select ok(
  public.export_financial_report_csv(
    (select value from export_test_ids where key = 'alpha_org'),
    'balance_sheet', p_as_of_date => '2026-09-30'
  ) like
  E'section,code,account,amount,currency\n%',
  'balance sheet CSV is available');

select ok(
  public.export_financial_report_csv(
    (select value from export_test_ids where key = 'alpha_org'),
    'trial_balance', p_as_of_date => '2026-09-30'
  ) like
  E'code,account,type,debit,credit,currency\n%',
  'trial balance CSV is available');

select ok(
  public.export_financial_report_csv(
    (select value from export_test_ids where key = 'alpha_org'),
    'cash_flow', '2026-09-01', '2026-09-30'
  ) like
  E'activity,net_movement,currency\n%',
  'cash flow CSV is available');

select ok(
  public.export_financial_report_csv(
    (select value from export_test_ids where key = 'alpha_org'),
    'general_ledger', '2026-09-01', '2026-09-30',
    p_account_id => (select value from export_test_ids where key = 'bank')
  ) like
  E'date,reference,description,memo,debit,credit,running_balance,currency\n%',
  'general ledger CSV is available');

reset role;
update public.subscription_entitlements
set is_enabled = false
where plan_id = (select id from public.subscription_plans where key = 'solo')
  and feature_key = 'exports';
set local role authenticated;

select lives_ok(
  format($sql$select public.report_profit_and_loss(%L, '2026-09-01', '2026-09-30')$sql$,
    (select value from export_test_ids where key = 'alpha_org')),
  'core report viewing remains available when export entitlement is disabled');
select throws_ok(
  format($sql$select public.export_financial_report_csv(%L, 'profit_loss', '2026-09-01', '2026-09-30')$sql$,
    (select value from export_test_ids where key = 'alpha_org')),
  'P0001', 'FEATURE_NOT_AVAILABLE_ON_PLAN: exports',
  'the server rejects export when the exports entitlement is disabled');

reset role;
update public.subscription_entitlements
set is_enabled = true
where plan_id = (select id from public.subscription_plans where key = 'solo')
  and feature_key = 'exports';
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}', true
);
set local role authenticated;

select lives_ok(
  format($sql$select public.report_profit_and_loss(%L, '2026-09-01', '2026-09-30')$sql$,
    (select value from export_test_ids where key = 'alpha_org')),
  'a viewer can continue reading core financial reports');
select throws_ok(
  format($sql$select public.export_financial_report_csv(%L, 'profit_loss', '2026-09-01', '2026-09-30')$sql$,
    (select value from export_test_ids where key = 'alpha_org')),
  '42501', 'INSUFFICIENT_PERMISSION: reports.export is required',
  'report export requires the dedicated permission');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}', true
);
set local role authenticated;

select throws_ok(
  format($sql$select public.export_financial_report_csv(%L, 'profit_loss', '2026-09-01', '2026-09-30')$sql$,
    (select value from export_test_ids where key = 'alpha_org')),
  '42501', 'TENANT_ACCESS_DENIED: not a member of this organization',
  'another tenant cannot export the report');

select * from finish();
rollback;
