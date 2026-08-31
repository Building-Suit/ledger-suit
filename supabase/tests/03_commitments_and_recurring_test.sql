-- Phase 3: commitments and recurring rules.
--
-- The two claims that matter here are that settling a commitment produces a
-- real balanced journal, and that the scheduler cannot post the same occurrence
-- twice however often it runs.

begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

create temp table ids (key text primary key, id uuid);
grant all on ids to authenticated;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change,
                        phone_change_token, reauthentication_token)
values
  ('dddddddd-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'owner-t3@ledgersuit.test',
   extensions.crypt('pw', extensions.gen_salt('bf')), now(),
   '{"provider":"email"}'::jsonb, '{"full_name":"Phase3 Owner"}'::jsonb, now(), now(),
   '', '', '', '', '', '', '', ''),
  ('eeeeeeee-2222-4222-8222-222222222222', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'outsider-t3@ledgersuit.test',
   extensions.crypt('pw', extensions.gen_salt('bf')), now(),
   '{"provider":"email"}'::jsonb, '{"full_name":"Outsider"}'::jsonb, now(), now(),
   '', '', '', '', '', '', '', '');

select set_config('request.jwt.claims',
  '{"sub":"dddddddd-1111-4111-8111-111111111111","role":"authenticated"}', true);
set local role authenticated;

insert into ids (key, id) values ('org', public.create_organization('Phase Three Co', 'EGP'));

insert into ids (key, id)
select 'bank', a.id from public.accounts a
where a.organization_id = (select id from ids where key = 'org') and a.system_key = 'bank';

insert into ids (key, id)
select 'rent_cat', c.id from public.categories c
where c.organization_id = (select id from ids where key = 'org') and c.name = 'Rent';

insert into ids (key, id)
select 'sales_cat', c.id from public.categories c
where c.organization_id = (select id from ids where key = 'org') and c.name = 'Sales';

-- Fund the bank so settlements have something to draw on.
select public.post_opening_balance(
  (select id from ids where key = 'org'), date '2026-01-01',
  jsonb_build_array(jsonb_build_object(
    'account_id', (select id from ids where key = 'bank'), 'amount_minor', 50000000))
);

-- ---------------------------------------------------------------------------
-- Commitments are forecasting only until settled
-- ---------------------------------------------------------------------------
insert into ids (key, id) values ('rent_commitment', public.create_commitment(
  p_organization_id    => (select id from ids where key = 'org'),
  p_type               => 'payable',
  p_title              => 'April rent',
  p_amount_minor       => 1500000,
  p_due_date           => date '2026-04-05',
  p_linked_category_id => (select id from ids where key = 'rent_cat')
));

select is(
  (select status from public.commitments where id = (select id from ids where key = 'rent_commitment')),
  'upcoming'::public.commitment_status,
  'a new commitment starts as upcoming'
);

select is(
  (select count(*) from public.transaction_entries e
   where e.organization_id = (select id from ids where key = 'org')
     and e.entry_date = date '2026-04-05'),
  0::bigint,
  'creating a commitment posts nothing to the ledger'
);

select is(
  (select display_status from public.commitment_states
   where id = (select id from ids where key = 'rent_commitment')),
  'overdue',
  'a commitment past its due date reads as overdue without any job running'
);

-- ---------------------------------------------------------------------------
-- Partial settlement
-- ---------------------------------------------------------------------------
select lives_ok(
  format($fmt$select public.settle_commitment(
      p_commitment_id      => %L,
      p_payment_account_id => %L,
      p_amount_minor       => 500000,
      p_settled_on         => date '2026-04-05')$fmt$,
    (select id from ids where key = 'rent_commitment'),
    (select id from ids where key = 'bank')),
  'a partial settlement is accepted'
);

select is(
  (select settled_amount_minor from public.commitments
   where id = (select id from ids where key = 'rent_commitment')),
  500000::bigint,
  'the settled total reflects the partial payment'
);

select is(
  (select status from public.commitments where id = (select id from ids where key = 'rent_commitment')),
  'partially_paid'::public.commitment_status,
  'a part-paid commitment is marked partially_paid'
);

select is(
  (select outstanding_minor from public.commitment_states
   where id = (select id from ids where key = 'rent_commitment')),
  1000000::bigint,
  'the outstanding balance is the remainder'
);

-- The settlement must be a real, balanced journal.
select is(
  (select (coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)
         - coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0))::bigint
   from public.transaction_entries e
   join public.commitment_settlements s on s.transaction_id = e.transaction_id
   where s.commitment_id = (select id from ids where key = 'rent_commitment')),
  0::bigint,
  'the settlement posts a balanced journal'
);

select is(
  (select ab.balance_minor from public.account_balances ab
   join public.accounts a on a.id = ab.account_id
   where a.organization_id = (select id from ids where key = 'org') and a.system_key = 'rent'),
  500000::bigint,
  'the settlement lands on the expense account behind the category'
);

select throws_ok(
  format($fmt$select public.settle_commitment(
      p_commitment_id      => %L,
      p_payment_account_id => %L,
      p_amount_minor       => 9999999)$fmt$,
    (select id from ids where key = 'rent_commitment'),
    (select id from ids where key = 'bank')),
  '22023',
  null,
  'settling more than the outstanding amount is refused'
);

-- Settle the rest.
select lives_ok(
  format($fmt$select public.settle_commitment(
      p_commitment_id      => %L,
      p_payment_account_id => %L,
      p_settled_on         => date '2026-04-20')$fmt$,
    (select id from ids where key = 'rent_commitment'),
    (select id from ids where key = 'bank')),
  'the remainder settles without an explicit amount'
);

select is(
  (select status from public.commitments where id = (select id from ids where key = 'rent_commitment')),
  'paid'::public.commitment_status,
  'a fully settled commitment is marked paid'
);

select throws_ok(
  format($fmt$select public.settle_commitment(%L, %L)$fmt$,
    (select id from ids where key = 'rent_commitment'),
    (select id from ids where key = 'bank')),
  '23514',
  null,
  'a settled commitment cannot be settled again'
);

select throws_ok(
  format($fmt$select public.cancel_commitment(%L, 'nope')$fmt$,
    (select id from ids where key = 'rent_commitment')),
  '23514',
  null,
  'a settled commitment cannot be cancelled'
);

-- ---------------------------------------------------------------------------
-- Recurring rules: the idempotency guarantee
-- ---------------------------------------------------------------------------
insert into ids (key, id) values ('salary_rule', public.create_recurring_rule(
  p_organization_id  => (select id from ids where key = 'org'),
  p_name             => 'Monthly rent',
  p_transaction_type => 'expense',
  p_template         => jsonb_build_object(
    'amount_minor', 1200000,
    'source_account_id', (select id from ids where key = 'bank'),
    'category_id', (select id from ids where key = 'rent_cat'),
    'description', 'Rent by standing order'
  ),
  p_frequency        => 'monthly',
  p_start_date       => date '2026-01-31',
  p_mode             => 'auto_post'
));

select is(
  (select count(*) from public.run_recurring_schedule(
     (select id from ids where key = 'org'), date '2026-04-30')),
  4::bigint,
  'the first run generates one occurrence per elapsed period'
);

select is(
  (select count(*) from public.run_recurring_schedule(
     (select id from ids where key = 'org'), date '2026-04-30')),
  0::bigint,
  'running the scheduler again generates nothing — it is idempotent'
);

select is(
  (select count(*) from public.recurring_occurrences
   where rule_id = (select id from ids where key = 'salary_rule')),
  4::bigint,
  'no duplicate occurrence rows exist after repeated runs'
);

select is(
  (select count(distinct transaction_id) from public.recurring_occurrences
   where rule_id = (select id from ids where key = 'salary_rule') and status = 'posted'),
  4::bigint,
  'each occurrence posted exactly one distinct transaction'
);

-- Anchoring on the start date rather than stepping from the previous
-- occurrence: a rule on the 31st must not drift to the 28th after February.
select results_eq(
  format($fmt$select occurrence_date from public.recurring_occurrences
          where rule_id = %L order by occurrence_date$fmt$,
    (select id from ids where key = 'salary_rule')),
  $$values (date '2026-01-31'), (date '2026-02-28'),
           (date '2026-03-31'), (date '2026-04-30')$$,
  'monthly occurrences anchor on the start date instead of drifting'
);

select is(
  (public.check_balance_sheet_integrity((select id from ids where key = 'org')) ->> 'balanced')::boolean,
  true,
  'the books still balance after commitments and recurring postings'
);

-- ---------------------------------------------------------------------------
-- Tenant isolation
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims',
  '{"sub":"eeeeeeee-2222-4222-8222-222222222222","role":"authenticated"}', true);
set local role authenticated;

select is(
  (select count(*) from public.commitments
   where organization_id = (select id from ids where key = 'org')),
  0::bigint,
  'a non-member cannot read another organization''s commitments'
);

select throws_ok(
  format($fmt$select public.settle_commitment(%L, %L)$fmt$,
    (select id from ids where key = 'rent_commitment'),
    (select id from ids where key = 'bank')),
  '42501',
  null,
  'a non-member cannot settle another organization''s commitment'
);

select throws_ok(
  format($fmt$select public.run_recurring_schedule(%L)$fmt$,
    (select id from ids where key = 'org')),
  '42501',
  null,
  'a non-member cannot run another organization''s recurring schedule'
);

select * from finish();

rollback;
