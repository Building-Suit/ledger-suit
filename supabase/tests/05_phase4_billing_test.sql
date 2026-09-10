-- Phase 4 billing access, tenant isolation, and webhook idempotency.
begin;

create extension if not exists pgtap with schema extensions;
select plan(18);

select ok(
  (select is_active and not is_public and not is_purchasable
   from public.subscription_plans where key = 'ledger_suit'),
  'the legacy Ledger Suit plan remains active and private'
);

select is(
  (select count(*) from public.subscription_plans where key = 'ledger_suit'),
  1::bigint,
  'the billing compatibility plan remains unique'
);

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

create temp table billing_ids (key text primary key, value text);
grant all on billing_ids to authenticated, service_role;

insert into billing_ids values (
  'org', public.create_organization('Checkout Required Co', 'EGP')::text
);

select is(
  public.subscription_access_state(
    (select value::uuid from billing_ids where key = 'org')
  ),
  'trialing',
  'creating an organization starts the cardless trial'
);

select ok(
  'organization.read' = any(public.my_capabilities(
    (select value::uuid from billing_ids where key = 'org')
  )),
  'financial history remains readable before checkout'
);

select ok(
  'billing.manage' = any(public.my_capabilities(
    (select value::uuid from billing_ids where key = 'org')
  )),
  'the owner can reach checkout before activation'
);

select ok(
  'transactions.post' = any(public.my_capabilities(
    (select value::uuid from billing_ids where key = 'org')
  )),
  'write capabilities are available during the trial'
);

select lives_ok(
  format(
    'select public.create_account(%L, %L, %L, %L)',
    (select value from billing_ids where key = 'org'),
    'Trial account', 'asset', 'bank'
  ),
  'writes succeed during the cardless trial'
);

select lives_ok(
  format(
    'select * from public.billing_checkout_context(%L, %L)',
    (select value from billing_ids where key = 'org'), 'monthly'
  ),
  'an owner can request an authorized checkout context'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
set local role service_role;

update public.subscriptions
set trial_ends_at = now() - interval '1 second'
where organization_id = (select value::uuid from billing_ids where key = 'org');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select is(
  public.subscription_access_state(
    (select value::uuid from billing_ids where key = 'org')
  ),
  'checkout_required',
  'an expired trial requires payment'
);

select ok(
  not ('organization.read' = any(public.my_capabilities(
    (select value::uuid from billing_ids where key = 'org')
  ))),
  'product read capabilities are removed after trial expiry'
);

select ok(
  'billing.manage' = any(public.my_capabilities(
    (select value::uuid from billing_ids where key = 'org')
  )),
  'billing remains reachable after trial expiry'
);

select throws_ok(
  format(
    'select public.create_account(%L, %L, %L, %L)',
    (select value from billing_ids where key = 'org'),
    'Expired account', 'asset', 'bank'
  ),
  '42501', null,
  'the database blocks product changes after trial expiry'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
set local role service_role;

select is(
  public.apply_paymob_subscription_event(
    'txn_phase4_test', 'transaction.succeeded', '{"test":true}',
    (select value::uuid from billing_ids where key = 'org'),
    'subscription_phase4_test', 'active', 'monthly',
    now(), now() + interval '1 month',
    null, null
  ),
  true,
  'a verified Paymob event activates the paid plan'
);

select is(
  public.apply_paymob_subscription_event(
    'txn_phase4_test', 'transaction.succeeded', '{"test":true}',
    (select value::uuid from billing_ids where key = 'org'),
    'subscription_phase4_test', 'active', 'monthly',
    now(), now() + interval '1 month',
    null, null
  ),
  false,
  'replayed Paymob events are idempotent'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select is(
  public.subscription_access_state(
    (select value::uuid from billing_ids where key = 'org')
  ),
  'active',
  'checkout restores access with a paid subscription'
);

select ok(
  'transactions.post' = any(public.my_capabilities(
    (select value::uuid from billing_ids where key = 'org')
  )),
  'write capabilities return with the paid subscription'
);

select lives_ok(
  format(
    'select public.create_account(%L, %L, %L, %L)',
    (select value from billing_ids where key = 'org'),
    'Allowed account', 'asset', 'bank'
  ),
  'writes succeed atomically after paid Paymob activation'
);

select set_config('request.jwt.claims',
  '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select throws_ok(
  format(
    'select public.subscription_access_state(%L)',
    (select value from billing_ids where key = 'org')
  ),
  '42501', null,
  'another tenant cannot inspect subscription state'
);

select * from finish();
rollback;
