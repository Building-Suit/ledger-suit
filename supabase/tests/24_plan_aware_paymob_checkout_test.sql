-- Plan-aware checkout resolves catalog prices and applies only verified plan identity.
begin;

create extension if not exists pgtap with schema extensions;
select plan(14);

create temp table checkout_ids (key text primary key, value uuid not null);
grant all on checkout_ids to authenticated, service_role;
insert into checkout_ids
select 'org', id from public.organizations where name = 'Alpha Trading';

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select is(
  (select jsonb_object_agg(
     requested.plan_key || ':' || requested.billing_interval::text,
     context.amount_minor
   )
   from (values
     ('solo', 'monthly'::public.billing_interval), ('solo', 'yearly'),
     ('starter', 'monthly'), ('starter', 'yearly'),
     ('business', 'monthly'), ('business', 'yearly')
   ) requested(plan_key, billing_interval)
   cross join lateral public.billing_checkout_context(
     (select value from checkout_ids where key = 'org'), requested.plan_key, requested.billing_interval
   ) context),
  jsonb_build_object(
    'solo:monthly', 39900, 'solo:yearly', 325584,
    'starter:monthly', 59900, 'starter:yearly', 488784,
    'business:monthly', 109900, 'business:yearly', 896784
  ),
  'checkout resolves all six exact launch prices from the database'
);

select throws_ok(
  format('select * from public.billing_checkout_context(%L, %L, %L)',
    (select value from checkout_ids where key = 'org'), 'scale', 'monthly'),
  '22023', 'PLAN_NOT_AVAILABLE', 'Scale cannot be purchased'
);
select throws_ok(
  format('select * from public.billing_checkout_context(%L, %L, %L)',
    (select value from checkout_ids where key = 'org'), 'enterprise', 'monthly'),
  '22023', 'PLAN_NOT_AVAILABLE', 'Enterprise cannot be fabricated'
);

reset role;
update public.subscription_plans
set is_active = false, is_purchasable = false where key = 'solo';
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  format('select * from public.billing_checkout_context(%L, %L, %L)',
    (select value from checkout_ids where key = 'org'), 'solo', 'monthly'),
  '22023', 'PLAN_NOT_AVAILABLE', 'an inactive plan is rejected'
);

reset role;
update public.subscription_plans
set is_active = true, is_purchasable = true where key = 'solo';
update public.subscription_plan_prices price set is_active = false
from public.subscription_plans plan
where price.plan_id = plan.id and plan.key = 'solo' and price.interval = 'monthly';
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  format('select * from public.billing_checkout_context(%L, %L, %L)',
    (select value from checkout_ids where key = 'org'), 'solo', 'monthly'),
  '22023', 'PLAN_PRICE_NOT_AVAILABLE', 'a missing active interval price is rejected'
);

reset role;
update public.subscription_plan_prices price set is_active = true
from public.subscription_plans plan
where price.plan_id = plan.id and plan.key = 'solo' and price.interval = 'monthly';

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
set local role service_role;

select is(
  public.apply_paymob_subscription_event(
    'step17-initial', 'transaction.succeeded', '{"verified":true}',
    (select value from checkout_ids where key = 'org'),
    'step17-subscription', 'active', 'yearly', 'business',
    now(), now() + interval '1 year', now(), null
  ), true, 'a verified event applies the selected launch plan'
);
select is(
  (select plan.key from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   where subscription.organization_id = (select value from checkout_ids where key = 'org')),
  'business', 'the selected plan identity is persisted'
);
select is(
  (select price.interval from public.subscriptions subscription
   join public.subscription_plan_prices price on price.id = subscription.price_id
   where subscription.organization_id = (select value from checkout_ids where key = 'org')),
  'yearly'::public.billing_interval, 'the selected catalog price is persisted'
);
select is(
  (select provider_subscription_id from public.subscriptions
   where organization_id = (select value from checkout_ids where key = 'org')),
  'step17-subscription', 'the provider subscription identifier is preserved'
);
select is(
  public.apply_paymob_subscription_event(
    'step17-renewal', 'subscription.successful_transaction', '{"verified":true}',
    (select value from checkout_ids where key = 'org'),
    'step17-subscription', 'active', 'yearly', null,
    null, now() + interval '2 years', now(), null
  ), true, 'a later provider callback can preserve the already-bound plan'
);
select is(
  (select plan.key from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   where subscription.organization_id = (select value from checkout_ids where key = 'org')),
  'business', 'a later callback does not replace the selected plan'
);
select is(
  public.apply_paymob_subscription_event(
    'step17-renewal', 'subscription.successful_transaction', '{"verified":true}',
    (select value from checkout_ids where key = 'org'),
    'step17-subscription', 'active', 'yearly', null,
    null, now() + interval '2 years', now(), null
  ), false, 'provider event replay remains idempotent'
);
select is(
  public.apply_paymob_subscription_event(
    'step17-invalid-plan', 'transaction.succeeded', '{"verified":true}',
    (select value from checkout_ids where key = 'org'),
    'step17-subscription', 'active', 'monthly', 'scale'
  ), false, 'an invalid provider plan selection cannot be applied'
);
select is(
  (select processing_error from public.billing_events
   where provider = 'paymob' and provider_event_id = 'step17-invalid-plan'),
  'PLAN_NOT_AVAILABLE', 'invalid plan processing records a stable error'
);

select * from finish();
rollback;
