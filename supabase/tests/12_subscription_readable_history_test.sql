-- Lapsed subscriptions preserve accounting reads and block every mutation.
begin;

create extension if not exists pgtap with schema extensions;
select plan(26);

create temp table readable_history_ids (key text primary key, value uuid not null);
grant all on readable_history_ids to authenticated, service_role;

insert into readable_history_ids
select 'org', id
from public.organizations
where name = 'Alpha Trading';

insert into public.accounts (
  organization_id, name, type, subtype, currency, created_by
) values (
  (select value from readable_history_ids where key = 'org'),
  'Historical bank account',
  'asset',
  'bank',
  'EGP',
  'a0000000-0000-4000-8000-000000000001'
);

insert into public.transactions (
  organization_id, type, status, transaction_date, posting_date,
  currency_code, exchange_rate, description, posted_at, created_by, posted_by
) values (
  (select value from readable_history_ids where key = 'org'),
  'income',
  'posted',
  current_date,
  current_date,
  'EGP',
  1,
  'Historical posted transaction',
  now(),
  'a0000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000001'
);

insert into public.attachments (
  organization_id,
  entity_type,
  entity_id,
  file_name,
  mime_type,
  size_bytes,
  storage_key,
  uploaded_by
) values (
  (select value from readable_history_ids where key = 'org'),
  'organization',
  (select value from readable_history_ids where key = 'org'),
  'historical-invoice.pdf',
  'application/pdf',
  128,
  (select value::text from readable_history_ids where key = 'org')
    || '/organization/'
    || (select value::text from readable_history_ids where key = 'org')
    || '/historical-invoice.pdf',
  'a0000000-0000-4000-8000-000000000001'
);

update public.subscriptions
set status = 'cancelled',
    trial_ends_at = now() - interval '1 day',
    current_period_end = now() - interval '1 day',
    grace_period_ends_at = now() - interval '1 day',
    cancelled_at = now()
where organization_id = (select value from readable_history_ids where key = 'org');

select is(
  app.subscription_access_state('ffffffff-ffff-4fff-8fff-ffffffffffff'),
  'checkout_required',
  'checkout-only access is reserved for an organization without a subscription'
);

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select is(
  public.subscription_access_state(
    (select value from readable_history_ids where key = 'org')
  ),
  'read_only',
  'a lapsed subscription enters read-only access instead of checkout-only access'
);

select ok(
  not (select writes_allowed
       from public.subscription_usage_summary(
         (select value from readable_history_ids where key = 'org')
       )
       limit 1),
  'read-only subscription state denies product writes'
);

select ok(
  'transactions.read' = any(public.my_capabilities(
    (select value from readable_history_ids where key = 'org')
  )),
  'transaction history remains in the effective capability set'
);

select ok(
  'accounts.read' = any(public.my_capabilities(
    (select value from readable_history_ids where key = 'org')
  )),
  'account history remains in the effective capability set'
);

select ok(
  'attachments.read' = any(public.my_capabilities(
    (select value from readable_history_ids where key = 'org')
  )),
  'attachment metadata remains in the effective capability set'
);

select ok(
  'reports.read' = any(public.my_capabilities(
    (select value from readable_history_ids where key = 'org')
  )),
  'financial reports remain in the effective capability set'
);

select ok(
  'billing.manage' = any(public.my_capabilities(
    (select value from readable_history_ids where key = 'org')
  )),
  'billing management remains available to restore the subscription'
);

select ok(
  not ('transactions.create' = any(public.my_capabilities(
    (select value from readable_history_ids where key = 'org')
  ))),
  'transaction creation is removed from the effective capability set'
);

select ok(
  not ('accounts.create' = any(public.my_capabilities(
    (select value from readable_history_ids where key = 'org')
  ))),
  'account creation is removed from the effective capability set'
);

select ok(
  not ('attachments.create' = any(public.my_capabilities(
    (select value from readable_history_ids where key = 'org')
  ))),
  'attachment creation is removed from the effective capability set'
);

select ok(
  (select count(*) > 0 from public.accounts
   where organization_id = (select value from readable_history_ids where key = 'org')),
  'account rows remain readable through RLS'
);

select ok(
  (select count(*) > 0 from public.transactions
   where organization_id = (select value from readable_history_ids where key = 'org')),
  'transaction rows remain readable through RLS'
);

select is(
  (select count(*) from public.attachments
   where organization_id = (select value from readable_history_ids where key = 'org')
     and file_name = 'historical-invoice.pdf'),
  1::bigint,
  'attachment metadata remains readable through RLS'
);

select lives_ok(
  format(
    'select * from public.report_profit_and_loss(%L, %L, %L)',
    (select value from readable_history_ids where key = 'org'),
    (current_date - interval '1 month')::date,
    current_date
  ),
  'financial report RPCs remain readable'
);

select lives_ok(
  format(
    'select * from public.search_transactions(%L)',
    (select value from readable_history_ids where key = 'org')
  ),
  'transaction search remains readable'
);

select lives_ok(
  format(
    'select * from public.billing_checkout_context(%L, %L)',
    (select value from readable_history_ids where key = 'org'),
    'monthly'
  ),
  'billing management remains reachable from read-only mode'
);

select throws_ok(
  format(
    'select public.create_account(%L, %L, %L, %L)',
    (select value from readable_history_ids where key = 'org'),
    'Blocked lapsed account', 'asset', 'bank'
  ),
  '42501', null,
  'controlled account creation remains blocked'
);

select throws_ok(
  format(
    'select public.create_draft_transaction(%L, %L, current_date, %L::jsonb)',
    (select value from readable_history_ids where key = 'org'),
    'income', '[]'
  ),
  '42501', null,
  'controlled transaction creation remains blocked before payload validation'
);

select throws_ok(
  format(
    'select * from public.create_organization_invitation(%L, %L, %L)',
    (select value from readable_history_ids where key = 'org'),
    'blocked-lapsed-invite@example.com', 'viewer'
  ),
  '42501', null,
  'member invitations remain blocked'
);

update public.accounts
set name = 'Blocked lapsed edit'
where organization_id = (select value from readable_history_ids where key = 'org')
  and name = 'Historical bank account';

select is(
  (select name from public.accounts
   where organization_id = (select value from readable_history_ids where key = 'org')),
  'Historical bank account',
  'direct account updates remain blocked by RLS'
);

select throws_ok(
  format(
    $$insert into public.attachments (
        organization_id, entity_type, entity_id, file_name, mime_type,
        size_bytes, storage_key, uploaded_by
      ) values (%L, 'organization', %L, 'blocked.pdf', 'application/pdf',
        64, %L, %L)$$,
    (select value from readable_history_ids where key = 'org'),
    (select value from readable_history_ids where key = 'org'),
    (select value::text from readable_history_ids where key = 'org')
      || '/organization/blocked.pdf',
    'a0000000-0000-4000-8000-000000000001'
  ),
  '42501', null,
  'direct attachment metadata creation remains blocked by RLS'
);

delete from public.attachments
where organization_id = (select value from readable_history_ids where key = 'org')
  and file_name = 'historical-invoice.pdf';

select is(
  (select count(*) from public.attachments
   where organization_id = (select value from readable_history_ids where key = 'org')
     and file_name = 'historical-invoice.pdf'),
  1::bigint,
  'attachment metadata deletion remains blocked by RLS'
);

select ok(
  not public.can_use_feature(
    (select value from readable_history_ids where key = 'org'),
    'exports'
  ),
  'feature checks remain disabled when subscription writes are blocked'
);

select is(
  public.get_limit(
    (select value from readable_history_ids where key = 'org'),
    'max_accounts'
  ),
  0::bigint,
  'public quota lookup remains write-state compatible in read-only mode'
);

select is(
  (select count(*) from public.subscriptions
   where organization_id = (select value from readable_history_ids where key = 'org')),
  1::bigint,
  'the lapsed subscription row remains readable for billing recovery'
);

reset role;
select * from finish();
rollback;
