-- Multi-tenant isolation tests.
--
-- The governing rule: knowing another organization's UUID must never grant
-- access to anything. Every test below hands a real, valid foreign id to a
-- caller who has no membership, and requires it to fail.

begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

create temp table ids (key text primary key, id uuid);
grant all on ids to authenticated;

-- Three users: an owner in each of two organizations, plus a viewer in the first.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values
  ('aaaaaaaa-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'owner-t2@ledgersuit.test',
   extensions.crypt('pw', extensions.gen_salt('bf')), now(),
   '{"provider":"email"}'::jsonb, '{"full_name":"Alpha Owner"}'::jsonb, now(), now()),
  ('bbbbbbbb-2222-4222-8222-222222222222', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'beta-t2@ledgersuit.test',
   extensions.crypt('pw', extensions.gen_salt('bf')), now(),
   '{"provider":"email"}'::jsonb, '{"full_name":"Beta Owner"}'::jsonb, now(), now()),
  ('cccccccc-3333-4333-8333-333333333333', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'viewer-t2@ledgersuit.test',
   extensions.crypt('pw', extensions.gen_salt('bf')), now(),
   '{"provider":"email"}'::jsonb, '{"full_name":"Alpha Viewer"}'::jsonb, now(), now());

-- --- Organization Alpha, owned by user A -----------------------------------
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-1111-4111-8111-111111111111","role":"authenticated"}', true);
set local role authenticated;

insert into ids (key, id) values ('org_a', public.create_organization('Alpha Trading', 'EGP'));

insert into ids (key, id)
select 'bank_a', a.id from public.accounts a
where a.organization_id = (select id from ids where key = 'org_a') and a.system_key = 'bank';

insert into ids (key, id)
select 'rent_a', c.id from public.categories c
where c.organization_id = (select id from ids where key = 'org_a') and c.name = 'Rent';

insert into ids (key, id) values ('txn_a', public.record_expense(
  p_organization_id   => (select id from ids where key = 'org_a'),
  p_amount_minor      => 250000,
  p_source_account_id => (select id from ids where key = 'bank_a'),
  p_category_id       => (select id from ids where key = 'rent_a'),
  p_transaction_date  => date '2026-02-01',
  p_description       => 'Alpha private rent'
));

-- --- Organization Beta, owned by user B -------------------------------------
reset role;
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-2222-4222-8222-222222222222","role":"authenticated"}', true);
set local role authenticated;

insert into ids (key, id) values ('org_b', public.create_organization('Beta Supplies', 'EGP'));

insert into ids (key, id)
select 'bank_b', a.id from public.accounts a
where a.organization_id = (select id from ids where key = 'org_b') and a.system_key = 'bank';

insert into ids (key, id)
select 'rent_b', c.id from public.categories c
where c.organization_id = (select id from ids where key = 'org_b') and c.name = 'Rent';

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from public.transactions
   where organization_id = (select id from ids where key = 'org_a')),
  0::bigint,
  'a user cannot read another organization''s transactions'
);

select is(
  (select count(*) from public.transaction_entries
   where organization_id = (select id from ids where key = 'org_a')),
  0::bigint,
  'a user cannot read another organization''s ledger entries'
);

select is(
  (select count(*) from public.accounts
   where organization_id = (select id from ids where key = 'org_a')),
  0::bigint,
  'a user cannot read another organization''s chart of accounts'
);

select is(
  (select count(*) from public.account_balances
   where organization_id = (select id from ids where key = 'org_a')),
  0::bigint,
  'the balances view does not leak across tenants'
);

select is(
  (select count(*) from public.organizations
   where id = (select id from ids where key = 'org_a')),
  0::bigint,
  'a user cannot read another organization''s profile'
);

select is(
  (select count(*) from public.audit_logs
   where organization_id = (select id from ids where key = 'org_a')),
  0::bigint,
  'a user cannot read another organization''s audit log'
);

select is(
  (select count(*) from public.categories
   where organization_id = (select id from ids where key = 'org_a')),
  0::bigint,
  'a user cannot read another organization''s categories'
);

select is(
  public.my_capabilities((select id from ids where key = 'org_a')),
  '{}'::text[],
  'a non-member has no capabilities in an organization they can name'
);

-- ---------------------------------------------------------------------------
-- Writes with an injected organization id
-- ---------------------------------------------------------------------------
select throws_ok(
  format($fmt$select public.record_expense(
      p_organization_id   => %L,
      p_amount_minor      => 100,
      p_source_account_id => %L,
      p_category_id       => %L)$fmt$,
    (select id from ids where key = 'org_a'),
    (select id from ids where key = 'bank_a'),
    (select id from ids where key = 'rent_a')),
  '42501',
  null,
  'posting into another organization is refused even with all its real ids'
);

-- An UPDATE the caller holds the grant for, but which RLS does not match, must
-- quietly affect nothing. Verified from outside the policy, as the superuser.
update public.organizations set name = 'Renamed by an outsider'
where id = (select id from ids where key = 'org_a');

reset role;
select is(
  (select name from public.organizations where id = (select id from ids where key = 'org_a')),
  'Alpha Trading',
  'a non-member''s update of another organization changes nothing'
);
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-2222-4222-8222-222222222222","role":"authenticated"}', true);
set local role authenticated;

-- The dangerous case: caller''s own organization, but a foreign account id.
select throws_ok(
  format($fmt$select public.record_expense(
      p_organization_id   => %L,
      p_amount_minor      => 100,
      p_source_account_id => %L,
      p_category_id       => %L)$fmt$,
    (select id from ids where key = 'org_b'),
    (select id from ids where key = 'bank_a'),
    (select id from ids where key = 'rent_b')),
  '42501',
  null,
  'a foreign account id cannot be smuggled into your own organization''s posting'
);

select throws_ok(
  format($fmt$select public.reverse_transaction(%L, 'nope')$fmt$,
    (select id from ids where key = 'txn_a')),
  '42501',
  null,
  'a non-member cannot reverse another organization''s transaction'
);

select throws_ok(
  format('select public.dashboard_summary(%L)', (select id from ids where key = 'org_a')),
  '42501',
  null,
  'a non-member cannot read another organization''s dashboard'
);

select throws_ok(
  format('select public.report_balance_sheet(%L)', (select id from ids where key = 'org_a')),
  '42501',
  null,
  'a non-member cannot read another organization''s balance sheet'
);

-- Cross-tenant foreign key: Beta's category pointing at Alpha's account.
select throws_ok(
  format($fmt$insert into public.categories (organization_id, name, kind, default_account_id)
          values (%L, 'Smuggled', 'expense', %L)$fmt$,
    (select id from ids where key = 'org_b'),
    (select id from ids where key = 'bank_a')),
  '23503',
  null,
  'a category cannot point at an account owned by another organization'
);

-- Storage keys are pinned to the owning organization prefix.
select throws_ok(
  format($fmt$insert into public.attachments
            (organization_id, entity_type, entity_id, file_name, mime_type,
             size_bytes, storage_key, uploaded_by)
          values (%L, 'transaction', %L, 'x.pdf', 'application/pdf', 10,
                  %L || '/transaction/x.pdf', %L)$fmt$,
    (select id from ids where key = 'org_b'),
    (select id from ids where key = 'txn_a'),
    (select id from ids where key = 'org_a'),
    'bbbbbbbb-2222-4222-8222-222222222222'),
  '23514',
  null,
  'an attachment cannot be filed under another organization''s storage prefix'
);

select is(
  (select count(*) from public.subscriptions
   where organization_id = (select id from ids where key = 'org_a')),
  0::bigint,
  'a user cannot read another organization''s subscription'
);

-- ---------------------------------------------------------------------------
-- Role restrictions inside a shared organization
-- ---------------------------------------------------------------------------
reset role;
insert into public.organization_members (organization_id, user_id, role)
values ((select id from ids where key = 'org_a'),
        'cccccccc-3333-4333-8333-333333333333', 'viewer');

select set_config('request.jwt.claims',
  '{"sub":"cccccccc-3333-4333-8333-333333333333","role":"authenticated"}', true);
set local role authenticated;

select is(
  (select count(*) from public.transactions
   where organization_id = (select id from ids where key = 'org_a')),
  1::bigint,
  'a viewer can read the transactions of the organization they belong to'
);

select throws_ok(
  format($fmt$select public.record_expense(
      p_organization_id   => %L,
      p_amount_minor      => 100,
      p_source_account_id => %L,
      p_category_id       => %L)$fmt$,
    (select id from ids where key = 'org_a'),
    (select id from ids where key = 'bank_a'),
    (select id from ids where key = 'rent_a')),
  '42501',
  null,
  'a viewer cannot create transactions'
);

select throws_ok(
  format($fmt$select public.reverse_transaction(%L, 'viewer attempt')$fmt$,
    (select id from ids where key = 'txn_a')),
  '42501',
  null,
  'a viewer cannot reverse a posted transaction'
);

select * from finish();

rollback;
