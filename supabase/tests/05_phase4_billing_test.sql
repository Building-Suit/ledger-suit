-- Phase 4 billing access, tenant isolation, and webhook idempotency.
begin;

create extension if not exists pgtap with schema extensions;
select plan(14);

select is(
  (select count(*) from public.subscription_plans where is_public and is_active),
  1::bigint,
  'exactly one subscription plan is available'
);

select is(
  (select key from public.subscription_plans where is_public and is_active),
  'ledger_suit',
  'the single plan is Ledger Suit'
);

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
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
  'checkout_required',
  'creating an organization does not start the trial'
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
  not ('transactions.post' = any(public.my_capabilities(
    (select value::uuid from billing_ids where key = 'org')
  ))),
  'write capabilities are removed before checkout'
);

select throws_ok(
  format(
    'select public.create_account(%L, %L, %L, %L)',
    (select value from billing_ids where key = 'org'),
    'Blocked account', 'asset', 'bank'
  ),
  '42501', null,
  'the database blocks writes before checkout'
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

select is(
  public.apply_stripe_subscription_event(
    'evt_phase4_test', 'checkout.session.completed', '{"test":true}',
    (select value::uuid from billing_ids where key = 'org'),
    'cus_phase4_test', 'sub_phase4_test', 'trialing', 'monthly',
    now(), now() + interval '14 days', now(), now() + interval '14 days', false,
    null, null
  ),
  true,
  'a verified Stripe event activates the trial'
);

select is(
  public.apply_stripe_subscription_event(
    'evt_phase4_test', 'checkout.session.completed', '{"test":true}',
    (select value::uuid from billing_ids where key = 'org'),
    'cus_phase4_test', 'sub_phase4_test', 'trialing', 'monthly',
    now(), now() + interval '14 days', now(), now() + interval '14 days', false,
    null, null
  ),
  false,
  'replayed Stripe events are idempotent'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select is(
  public.subscription_access_state(
    (select value::uuid from billing_ids where key = 'org')
  ),
  'trialing',
  'checkout starts the 14-day trial'
);

select ok(
  'transactions.post' = any(public.my_capabilities(
    (select value::uuid from billing_ids where key = 'org')
  )),
  'write capabilities return during the trial'
);

select lives_ok(
  format(
    'select public.create_account(%L, %L, %L, %L)',
    (select value from billing_ids where key = 'org'),
    'Allowed account', 'asset', 'bank'
  ),
  'writes succeed atomically after Stripe activation'
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
