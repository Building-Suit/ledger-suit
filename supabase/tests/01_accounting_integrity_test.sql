-- Accounting integrity tests.
--
-- Proves the claims the product rests on: every posting balances, reversals
-- neutralise exactly, the balance sheet equation holds, and posted history
-- cannot be edited.
--
-- Note on impersonation: SET LOCAL issued inside a function is undone when the
-- function returns, so the role switches below are written inline on purpose.

begin;

create extension if not exists pgtap with schema extensions;

select plan(25);

-- ---------------------------------------------------------------------------
-- Fixtures (created as the superuser, before dropping into the app role)
-- ---------------------------------------------------------------------------
create temp table ids (key text primary key, id uuid);
-- The scratch table has to be usable after the role switch below.
grant all on ids to authenticated;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values (
  '11111111-1111-4111-8111-111111111111',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'owner-t1@ledgersuit.test',
  extensions.crypt('password', extensions.gen_salt('bf')),
  now(), '{"provider":"email"}'::jsonb, '{"full_name":"Alpha Owner"}'::jsonb, now(), now()
);

select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}',
  true
);
set local role authenticated;

insert into ids (key, id)
values ('org', public.create_organization('Alpha Trading', 'EGP', 'EG', 'Africa/Cairo'));

reset role;
update public.subscriptions
set status = 'active', provider = 'stripe', provider_subscription_id = 'sub_test_integrity',
    provider_status = 'active', billing_interval = 'monthly', checkout_completed_at = now(),
    current_period_start = now(), current_period_end = now() + interval '30 days'
where organization_id = (select id from ids where key = 'org');
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Onboarding produces a working chart of accounts
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from public.accounts where organization_id = (select id from ids where key = 'org')),
  40::bigint,
  'a new organization gets the full default chart of accounts'
);

select is(
  (select count(*) from public.accounts
   where organization_id = (select id from ids where key = 'org') and system_key is not null),
  22::bigint,
  'every system account the posting engine looks up exists'
);

select is(
  (select count(*) from public.categories where organization_id = (select id from ids where key = 'org')),
  12::bigint,
  'starter categories are created and mapped to accounts'
);

select is(
  (select a.normal_balance from public.accounts a
   where a.organization_id = (select id from ids where key = 'org') and a.system_key = 'bank'),
  'debit'::public.normal_balance,
  'asset accounts are debit-normal'
);

select is(
  (select a.normal_balance from public.accounts a
   where a.organization_id = (select id from ids where key = 'org') and a.system_key = 'product_sales'),
  'credit'::public.normal_balance,
  'revenue accounts are credit-normal'
);

-- ---------------------------------------------------------------------------
-- Opening balance, income and expense
-- ---------------------------------------------------------------------------
insert into ids (key, id)
select 'bank', a.id from public.accounts a
where a.organization_id = (select id from ids where key = 'org') and a.system_key = 'bank';

insert into ids (key, id)
select 'cash', a.id from public.accounts a
where a.organization_id = (select id from ids where key = 'org') and a.system_key = 'cash';

insert into ids (key, id)
select 'rent', c.id from public.categories c
where c.organization_id = (select id from ids where key = 'org') and c.name = 'Rent';

insert into ids (key, id)
select 'sales', c.id from public.categories c
where c.organization_id = (select id from ids where key = 'org') and c.name = 'Sales';

-- 100,000.00 EGP opening bank balance.
insert into ids (key, id)
values ('opening', public.post_opening_balance(
  (select id from ids where key = 'org'),
  date '2026-01-01',
  jsonb_build_array(jsonb_build_object(
    'account_id', (select id from ids where key = 'bank'),
    'amount_minor', 10000000
  ))
));

select is(
  (select balance_minor from public.account_balances
   where account_id = (select id from ids where key = 'bank')),
  10000000::bigint,
  'the opening balance lands on the bank account'
);

select is(
  (select ab.balance_minor from public.account_balances ab
   join public.accounts a on a.id = ab.account_id
   where a.organization_id = (select id from ids where key = 'org')
     and a.system_key = 'opening_balance_equity'),
  10000000::bigint,
  'the balancing figure goes to opening balance equity, not to a plug'
);

-- Rent 15,000.00 EGP paid from the bank.
insert into ids (key, id)
values ('rent_txn', public.record_expense(
  p_organization_id   => (select id from ids where key = 'org'),
  p_amount_minor      => 1500000,
  p_source_account_id => (select id from ids where key = 'bank'),
  p_category_id       => (select id from ids where key = 'rent'),
  p_transaction_date  => date '2026-02-05',
  p_description       => 'February rent'
));

select is(
  (select (coalesce(sum(base_amount_minor) filter (where side = 'debit'), 0)
         - coalesce(sum(base_amount_minor) filter (where side = 'credit'), 0))::bigint
   from public.transaction_entries
   where transaction_id = (select id from ids where key = 'rent_txn')),
  0::bigint,
  'the expense posting is balanced: debits equal credits'
);

select is(
  (select count(*) from public.transaction_entries
   where transaction_id = (select id from ids where key = 'rent_txn')),
  2::bigint,
  'the expense produced exactly two ledger lines'
);

select is(
  (select balance_minor from public.account_balances
   where account_id = (select id from ids where key = 'bank')),
  8500000::bigint,
  'paying rent reduces the bank balance by the amount paid'
);

-- Revenue 40,000.00 EGP received into the bank.
insert into ids (key, id)
values ('income_txn', public.record_income(
  p_organization_id        => (select id from ids where key = 'org'),
  p_amount_minor           => 4000000,
  p_destination_account_id => (select id from ids where key = 'bank'),
  p_category_id            => (select id from ids where key = 'sales'),
  p_transaction_date       => date '2026-02-10',
  p_description            => 'Invoice 001'
));

select is(
  (select balance_minor from public.account_balances
   where account_id = (select id from ids where key = 'bank')),
  12500000::bigint,
  'revenue received increases the bank balance'
);

-- ---------------------------------------------------------------------------
-- Transfers must not create revenue or expense
-- ---------------------------------------------------------------------------
insert into ids (key, id)
values ('transfer_txn', public.record_transfer(
  p_organization_id  => (select id from ids where key = 'org'),
  p_amount_minor     => 500000,
  p_from_account_id  => (select id from ids where key = 'bank'),
  p_to_account_id    => (select id from ids where key = 'cash'),
  p_transaction_date => date '2026-02-11'
));

select is(
  (select count(*) from public.transaction_entries e
   join public.accounts a on a.id = e.account_id
   where e.transaction_id = (select id from ids where key = 'transfer_txn')
     and a.type in ('revenue', 'expense')),
  0::bigint,
  'a transfer without a fee touches no revenue or expense account'
);

select is(
  (select balance_minor from public.account_balances
   where account_id = (select id from ids where key = 'cash')),
  500000::bigint,
  'the transfer arrives in the destination account'
);

-- ---------------------------------------------------------------------------
-- The balance sheet equation
-- ---------------------------------------------------------------------------
select is(
  (public.check_balance_sheet_integrity((select id from ids where key = 'org')) ->> 'balanced')::boolean,
  true,
  'Assets = Liabilities + Equity after every posting so far'
);

select is(
  (public.dashboard_summary((select id from ids where key = 'org'), date '2026-02-28')
     ->> 'net_profit_this_month_minor')::bigint,
  2500000::bigint,
  'net profit for the month is revenue minus expenses'
);

-- ---------------------------------------------------------------------------
-- Reversal neutralises exactly
-- ---------------------------------------------------------------------------
insert into ids (key, id)
values ('reversal', public.reverse_transaction(
  (select id from ids where key = 'rent_txn'),
  'Rent was billed to the wrong month'
));

select is(
  (select status from public.transactions where id = (select id from ids where key = 'rent_txn')),
  'reversed'::public.transaction_status,
  'the original transaction is marked reversed'
);

select is(
  (select ab.balance_minor from public.account_balances ab
   join public.accounts a on a.id = ab.account_id
   where a.organization_id = (select id from ids where key = 'org') and a.system_key = 'rent'),
  0::bigint,
  'the reversal returns the expense account to exactly zero'
);

select is(
  (public.check_balance_sheet_integrity((select id from ids where key = 'org')) ->> 'balanced')::boolean,
  true,
  'the balance sheet still balances after a reversal'
);

select throws_ok(
  format('select public.reverse_transaction(%L, %L)',
         (select id from ids where key = 'rent_txn'), 'again'),
  '23514',
  null,
  'a transaction cannot be reversed twice'
);

-- ---------------------------------------------------------------------------
-- Immutability of posted records.
--
-- Run as the superuser on purpose: this must prove the triggers hold, not just
-- that the client role lacks the grant.
-- ---------------------------------------------------------------------------
reset role;

select throws_ok(
  format('update public.transactions set transaction_date = date ''2026-03-01'' where id = %L',
         (select id from ids where key = 'income_txn')),
  '42501',
  null,
  'a posted transaction cannot be edited in place, even by a superuser'
);

select throws_ok(
  format('delete from public.transaction_entries where transaction_id = %L',
         (select id from ids where key = 'income_txn')),
  '42501',
  null,
  'posted ledger entries cannot be deleted, even by a superuser'
);

select throws_ok(
  format('delete from public.transactions where id = %L',
         (select id from ids where key = 'income_txn')),
  '42501',
  null,
  'a posted transaction cannot be deleted, even by a superuser'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}',
  true
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Unbalanced journals are refused
-- ---------------------------------------------------------------------------
select throws_ok(
  format($fmt$select public.create_adjustment(
      %L, date '2026-02-20',
      jsonb_build_array(
        jsonb_build_object('account_id', %L, 'side', 'debit',  'amount_minor', 1000),
        jsonb_build_object('account_id', %L, 'side', 'credit', 'amount_minor', 900)
      ),
      'Deliberately lopsided', 'testing')$fmt$,
    (select id from ids where key = 'org'),
    (select id from ids where key = 'bank'),
    (select id from ids where key = 'cash')),
  '23514',
  null,
  'an unbalanced manual journal is refused'
);

-- ---------------------------------------------------------------------------
-- Books lock
-- ---------------------------------------------------------------------------
update public.organization_settings
set books_locked_until = date '2026-03-31'
where organization_id = (select id from ids where key = 'org');

-- The owner holds books.override_lock, so revoke it for this member: the point
-- is to test the lock, not the role.
update public.organization_members
set revoked_capabilities = array['books.override_lock']
where organization_id = (select id from ids where key = 'org');

select throws_ok(
  format($fmt$select public.record_expense(
      p_organization_id   => %L,
      p_amount_minor      => 100,
      p_source_account_id => %L,
      p_category_id       => %L,
      p_transaction_date  => date '2026-03-01')$fmt$,
    (select id from ids where key = 'org'),
    (select id from ids where key = 'bank'),
    (select id from ids where key = 'rent')),
  '42501',
  null,
  'posting into a locked period is refused without books.override_lock'
);

update public.organization_members
set revoked_capabilities = '{}'
where organization_id = (select id from ids where key = 'org');

update public.organization_settings
set books_locked_until = null
where organization_id = (select id from ids where key = 'org');

-- ---------------------------------------------------------------------------
-- Idempotency
-- ---------------------------------------------------------------------------
select is(
  public.record_expense(
    p_organization_id   => (select id from ids where key = 'org'),
    p_amount_minor      => 25000,
    p_source_account_id => (select id from ids where key = 'cash'),
    p_category_id       => (select id from ids where key = 'rent'),
    p_transaction_date  => date '2026-02-15',
    p_idempotency_key   => 'retry-me'
  ),
  public.record_expense(
    p_organization_id   => (select id from ids where key = 'org'),
    p_amount_minor      => 25000,
    p_source_account_id => (select id from ids where key = 'cash'),
    p_category_id       => (select id from ids where key = 'rent'),
    p_transaction_date  => date '2026-02-15',
    p_idempotency_key   => 'retry-me'
  ),
  'replaying a posting with the same idempotency key returns the original id'
);

select * from finish();

rollback;
