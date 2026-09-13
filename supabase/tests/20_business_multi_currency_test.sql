-- Business-only multi-currency enforcement at every persistent write boundary.
begin;

create extension if not exists pgtap with schema extensions;
select plan(31);

create temp table multi_currency_ids (key text primary key, value uuid not null);
grant all on multi_currency_ids to authenticated, service_role;

insert into multi_currency_ids
select 'org', id from public.organizations where name = 'Alpha Trading';

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from multi_currency_ids where key = 'org');

select app.seed_chart_of_accounts((select value from multi_currency_ids where key = 'org'));
select app.seed_categories((select value from multi_currency_ids where key = 'org'));

insert into public.accounts (
  id, organization_id, code, name, type, subtype, currency, created_by
) values (
  '20000000-0000-4000-8000-000000000001',
  (select value from multi_currency_ids where key = 'org'), 'MCUSD',
  'Legacy USD bank', 'asset', 'bank', 'USD',
  'a0000000-0000-4000-8000-000000000001'
) ;

insert into multi_currency_ids values
  ('usd_account', '20000000-0000-4000-8000-000000000001');
insert into multi_currency_ids
select 'bank', id from public.accounts
where organization_id = (select value from multi_currency_ids where key = 'org')
  and system_key = 'bank';
insert into multi_currency_ids
select 'revenue', id from public.accounts
where organization_id = (select value from multi_currency_ids where key = 'org')
  and system_key = 'product_sales';
insert into multi_currency_ids
select 'rent_category', id from public.categories
where organization_id = (select value from multi_currency_ids where key = 'org')
  and name = 'Rent';

insert into public.commitments (
  id, organization_id, type, status, title, amount_minor, currency_code,
  due_date, original_due_date, linked_account_id, auto_payment_account_id
) values (
  '20000000-0000-4000-8000-000000000002',
  (select value from multi_currency_ids where key = 'org'), 'payable', 'upcoming',
  'Legacy USD commitment', 100, 'USD', current_date + 30, current_date + 30,
  (select value from multi_currency_ids where key = 'revenue'),
  (select value from multi_currency_ids where key = 'usd_account')
);
insert into public.commitments (
  id, organization_id, type, status, title, amount_minor, currency_code,
  due_date, original_due_date
) values (
  '20000000-0000-4000-8000-000000000006',
  (select value from multi_currency_ids where key = 'org'), 'payable', 'upcoming',
  'Base commitment', 100, 'EGP', current_date + 30, current_date + 30
);
insert into public.recurring_rules (
  id, organization_id, name, transaction_type, template, frequency, start_date, status
) values
  ('20000000-0000-4000-8000-000000000003',
   (select value from multi_currency_ids where key = 'org'),
   'Legacy USD recurring', 'expense',
   jsonb_build_object('source_account_id',
     (select value from multi_currency_ids where key = 'usd_account'),
     'currency_code', 'USD'),
   'monthly', current_date + 30, 'active'),
  ('20000000-0000-4000-8000-000000000004',
   (select value from multi_currency_ids where key = 'org'),
   'Legacy USD recurring completion', 'expense',
   jsonb_build_object('source_account_id',
     (select value from multi_currency_ids where key = 'usd_account'),
     'currency_code', 'USD'),
   'monthly', current_date + 30, 'active');

select lives_ok(
  format('select app.assert_write_currency(%L, %L)',
    (select value from multi_currency_ids where key = 'org'), 'USD'),
  'the compatibility plan retains multi-currency access');

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'starter')
where organization_id = (select value from multi_currency_ids where key = 'org');

select lives_ok(
  format('select app.assert_write_currency(%L, %L)',
    (select value from multi_currency_ids where key = 'org'), 'EGP'),
  'Starter can write its base currency');
select throws_ok(
  format('select app.assert_write_currency(%L, %L)',
    (select value from multi_currency_ids where key = 'org'), 'USD'),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'Starter receives the stable upgrade error for a foreign currency');

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  format('update public.organizations set base_currency = %L where id = %L',
    'USD', (select value from multi_currency_ids where key = 'org')),
  '42501', null,
  'an authorized PostgREST updater cannot change the base-currency column directly');
select throws_ok(
  format('select public.change_organization_base_currency(%L, %L)',
    (select value from multi_currency_ids where key = 'org'), 'USD'),
  '23514', 'BASE_CURRENCY_LOCKED: accounting state already exists',
  'the controlled correction path refuses a workspace with accounting state');
select is(
  (select base_currency::text from public.organizations
   where id = (select value from multi_currency_ids where key = 'org')),
  'EGP', 'a failed correction cannot make USD appear to be the workspace base currency');

select throws_ok(
  format($sql$select public.create_account(%L, 'Blocked USD account', 'asset', 'bank', 'USD')$sql$,
    (select value from multi_currency_ids where key = 'org')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'the controlled account RPC rejects foreign currency on Starter');

reset role;
select throws_ok(
  format($sql$insert into public.accounts (
    organization_id, name, type, subtype, currency
  ) values (%L, 'Privileged USD bypass', 'asset', 'bank', 'USD')$sql$,
    (select value from multi_currency_ids where key = 'org')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'a privileged direct account insert cannot bypass the plan');
select throws_ok(
  format($sql$insert into public.transactions (
    organization_id, type, status, source, transaction_date, currency_code, exchange_rate
  ) values (%L, 'income', 'draft', 'api', current_date, 'USD', 50)$sql$,
    (select value from multi_currency_ids where key = 'org')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'the transaction table boundary blocks direct API/import-style writes');

set local role authenticated;
select throws_ok(
  format($sql$select public.create_draft_transaction(
    %L, 'income', current_date,
    jsonb_build_array(
      jsonb_build_object('account_id', %L, 'side', 'debit', 'amount_minor', 100, 'currency_code', 'USD', 'exchange_rate', 50),
      jsonb_build_object('account_id', %L, 'side', 'credit', 'amount_minor', 100, 'currency_code', 'USD', 'exchange_rate', 50)
    ), 'USD', 50, p_source => 'import'
  )$sql$,
    (select value from multi_currency_ids where key = 'org'),
    (select value from multi_currency_ids where key = 'usd_account'),
    (select value from multi_currency_ids where key = 'revenue')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'the import draft path cannot post a foreign-currency journal');
select throws_ok(
  format($sql$select public.record_income(%L, 100, %L,
    p_revenue_account_id => %L, p_currency_code => 'USD', p_exchange_rate => 50)$sql$,
    (select value from multi_currency_ids where key = 'org'),
    (select value from multi_currency_ids where key = 'usd_account'),
    (select value from multi_currency_ids where key = 'revenue')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'an ordinary posting RPC cannot use foreign currency');
select throws_ok(
  format($sql$select public.record_transfer(%L, 5000, %L, %L,
    p_destination_amount_minor => 100, p_exchange_rate => 1,
    p_destination_exchange_rate => 50)$sql$,
    (select value from multi_currency_ids where key = 'org'),
    (select value from multi_currency_ids where key = 'bank'),
    (select value from multi_currency_ids where key = 'usd_account')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'the transfer path cannot use a legacy foreign account');
select throws_ok(
  format($sql$select public.create_adjustment(%L, current_date,
    jsonb_build_array(
      jsonb_build_object('account_id', %L, 'side', 'debit', 'amount_minor', 100, 'currency_code', 'USD', 'exchange_rate', 50),
      jsonb_build_object('account_id', %L, 'side', 'credit', 'amount_minor', 5000, 'currency_code', 'EGP')
    ), 'Blocked FX adjustment', 'Plan enforcement', 'EGP', 1)$sql$,
    (select value from multi_currency_ids where key = 'org'),
    (select value from multi_currency_ids where key = 'usd_account'),
    (select value from multi_currency_ids where key = 'revenue')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'the adjustment path cannot introduce a foreign line');
select throws_ok(
  format($sql$select public.post_opening_balance(%L, current_date,
    jsonb_build_array(jsonb_build_object(
      'account_id', %L, 'amount_minor', 100, 'exchange_rate', 50)))$sql$,
    (select value from multi_currency_ids where key = 'org'),
    (select value from multi_currency_ids where key = 'usd_account')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'the opening-balance path cannot use a legacy foreign account');
select throws_ok(
  format($sql$select public.create_commitment(
    %L, 'payable', 'Blocked USD commitment', 100, current_date + 30, 'USD')$sql$,
    (select value from multi_currency_ids where key = 'org')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'the commitment RPC rejects foreign currency');
select throws_ok(
  format($sql$select public.create_commitment(
    %L, 'payable', 'Blocked base commitment with USD account', 100,
    current_date + 30, 'EGP', p_linked_account_id => %L)$sql$,
    (select value from multi_currency_ids where key = 'org'),
    (select value from multi_currency_ids where key = 'usd_account')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'a base-currency commitment cannot hide a legacy foreign linked account');
select throws_ok(
  format($sql$select public.update_commitment(
    '20000000-0000-4000-8000-000000000006', 'Base commitment',
    p_auto_convert => true, p_auto_payment_account_id => %L)$sql$,
    (select value from multi_currency_ids where key = 'usd_account')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'a base-currency commitment cannot hide a legacy foreign auto-payment account');
select throws_ok(
  format($sql$select public.create_recurring_rule(
    %L, 'Blocked USD recurring', 'expense',
    jsonb_build_object('amount_minor', 100, 'source_account_id', %L,
      'category_id', %L, 'currency_code', 'USD'),
    'monthly', current_date + 30)$sql$,
    (select value from multi_currency_ids where key = 'org'),
    (select value from multi_currency_ids where key = 'usd_account'),
    (select value from multi_currency_ids where key = 'rent_category')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'the recurring RPC rejects a foreign template');

reset role;
select throws_ok(
  format($sql$insert into public.recurring_rules (
    organization_id, name, transaction_type, template, frequency, start_date
  ) values (%L, 'Direct recurring bypass', 'expense',
    jsonb_build_object('source_account_id', %L), 'monthly', current_date + 30)$sql$,
    (select value from multi_currency_ids where key = 'org'),
    (select value from multi_currency_ids where key = 'usd_account')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'the recurring table boundary blocks privileged bypasses');
select is(
  (select currency::text from public.accounts
   where id = (select value from multi_currency_ids where key = 'usd_account')),
  'USD', 'foreign-currency history remains readable after downgrade');
select lives_ok(
  format('select public.archive_account(%L)',
    (select value from multi_currency_ids where key = 'usd_account')),
  'a legacy foreign account can be archived after downgrade');
select throws_ok(
  format('update public.accounts set is_archived = false where id = %L',
    (select value from multi_currency_ids where key = 'usd_account')),
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'an archived foreign account cannot be reactivated after downgrade');
select lives_ok(
  $$select public.cancel_commitment(
    '20000000-0000-4000-8000-000000000002', 'No longer required')$$,
  'a legacy foreign commitment can be cancelled after downgrade');
select throws_ok(
  $$update public.commitments set status = 'upcoming'
    where id = '20000000-0000-4000-8000-000000000002'$$,
  '23514', null,
  'a closed foreign commitment cannot be reactivated');
select lives_ok(
  $$select public.set_recurring_rule_status(
    '20000000-0000-4000-8000-000000000003', 'paused')$$,
  'a legacy foreign recurring rule can be deactivated after downgrade');
select throws_ok(
  $$select public.set_recurring_rule_status(
    '20000000-0000-4000-8000-000000000003', 'active')$$,
  'P0001', 'MULTI_CURRENCY_REQUIRES_BUSINESS: multi_currency',
  'a deactivated foreign recurring rule cannot return to a live state');
select lives_ok(
  $$select public.set_recurring_rule_status(
    '20000000-0000-4000-8000-000000000004', 'completed')$$,
  'a legacy foreign recurring rule can be completed after downgrade');
select is(
  (select count(*) from public.commitments c
   where c.id = '20000000-0000-4000-8000-000000000002'
     and c.status = 'cancelled')
  + (select count(*) from public.recurring_rules r
     where r.id in ('20000000-0000-4000-8000-000000000003',
                    '20000000-0000-4000-8000-000000000004')),
  3::bigint, 'closed foreign commitment and recurring history remains readable');
select lives_ok(
  format('update public.accounts set name = name where id = %L',
    (select value from multi_currency_ids where key = 'bank')),
  'base-currency records remain writable after downgrade');

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'business')
where organization_id = (select value from multi_currency_ids where key = 'org');
select lives_ok(
  format($sql$insert into public.accounts (
    id, organization_id, code, name, type, subtype, currency
  ) values ('20000000-0000-4000-8000-000000000005', %L,
    'MCUSD2', 'Business USD bank', 'asset', 'bank', 'USD')$sql$,
    (select value from multi_currency_ids where key = 'org')),
  'Business can create foreign-currency accounts');
select lives_ok(
  format($sql$select public.record_income(%L, 100, %L,
    p_revenue_account_id => %L, p_currency_code => 'USD', p_exchange_rate => 50)$sql$,
    (select value from multi_currency_ids where key = 'org'),
    '20000000-0000-4000-8000-000000000005',
    (select value from multi_currency_ids where key = 'revenue')),
  'Business may use the existing exchange-rate posting engine');

select * from finish();
rollback;
