-- Plan-aware checkout resolves catalog prices and applies only verified plan identity.
begin;

create extension if not exists pgtap with schema extensions;
select plan(24);

create temp table checkout_ids (key text primary key, value uuid not null);
grant all on checkout_ids to authenticated, service_role;
insert into checkout_ids
select 'org', id from public.organizations where name = 'Alpha Trading';

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;
insert into checkout_ids values
  ('trial_org', public.create_organization('Step 17 Trial Co', 'EGP'));

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;
insert into checkout_ids values
  ('missing_org', public.create_organization('Step 17 Checkout Required Co', 'EGP'));

reset role;
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

create temp table checkout_snapshots as
select plan.key as plan_key, price.interval, price.id as price_id,
       price.plan_id, price.amount_minor
from public.subscription_plan_prices price
join public.subscription_plans plan on plan.id = price.plan_id
where plan.key in ('solo', 'starter', 'business') and price.is_active;
grant all on checkout_snapshots to service_role;

-- A replacement catalog price must not invalidate an already-signed snapshot.
update public.subscription_plan_prices price set is_active = false
from public.subscription_plans plan
where price.plan_id = plan.id and plan.key = 'business' and price.interval = 'yearly';
insert into public.subscription_plan_prices (
  plan_id, interval, currency_code, amount_minor, is_active
)
select plan_id, interval, 'EGP', amount_minor + 100, true
from checkout_snapshots where plan_key = 'business' and interval = 'yearly';

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
set local role service_role;

select is(
  public.apply_paymob_subscription_event(
    p_event_id => 'step17-mismatched-snapshot',
    p_event_type => 'transaction.succeeded',
    p_payload => '{"verified":true}',
    p_organization_id => (select value from checkout_ids where key = 'org'),
    p_subscription_id => 'step17-subscription',
    p_provider_status => 'active',
    p_interval => 'yearly',
    p_plan_key => 'business',
    p_price_id => (select price_id from checkout_snapshots where plan_key = 'business' and interval = 'yearly'),
    p_amount_minor => (select amount_minor + 1 from checkout_snapshots where plan_key = 'business' and interval = 'yearly')
  ), false, 'a mismatched signed price and amount identity is rejected'
);
select is(
  (select processing_error from public.billing_events
   where provider = 'paymob' and provider_event_id = 'step17-mismatched-snapshot'),
  'PLAN_PRICE_SNAPSHOT_MISMATCH', 'snapshot mismatch records a stable processing error'
);
select is(
  public.apply_paymob_subscription_event(
    p_event_id => 'step17-initial',
    p_event_type => 'transaction.succeeded',
    p_payload => '{"verified":true}',
    p_organization_id => (select value from checkout_ids where key = 'org'),
    p_subscription_id => 'step17-subscription',
    p_provider_status => 'active',
    p_interval => 'yearly',
    p_plan_key => 'business',
    p_period_start => now(),
    p_period_end => now() + interval '1 year',
    p_last_payment_at => now(),
    p_price_id => (select price_id from checkout_snapshots where plan_key = 'business' and interval = 'yearly'),
    p_amount_minor => (select amount_minor from checkout_snapshots where plan_key = 'business' and interval = 'yearly')
  ), true, 'an inactive exact signed price snapshot still fulfills'
);
select is(
  (select jsonb_build_object(
     'plan', plan.key, 'price', subscription.price_id,
     'interval', subscription.billing_interval,
     'provider_subscription_id', subscription.provider_subscription_id
   )
   from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   where subscription.organization_id = (select value from checkout_ids where key = 'org')),
  (select jsonb_build_object(
     'plan', 'business', 'price', price_id,
     'interval', 'yearly', 'provider_subscription_id', 'step17-subscription'
   ) from checkout_snapshots where plan_key = 'business' and interval = 'yearly'),
  'fulfillment persists the exact signed plan, price, interval and provider id'
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

create temp table trial_before as
select plan_id, status, trial_ends_at
from public.subscriptions
where organization_id = (select value from checkout_ids where key = 'trial_org');
grant all on trial_before to service_role;

select is(
  public.apply_paymob_subscription_event(
    p_event_id => 'step17-trial-failure',
    p_event_type => 'transaction.failed',
    p_payload => '{"verified":true}',
    p_organization_id => (select value from checkout_ids where key = 'trial_org'),
    p_subscription_id => 'step17-trial-attempt',
    p_provider_status => 'past_due',
    p_interval => 'monthly',
    p_plan_key => 'starter',
    p_payment_failed_at => now(),
    p_price_id => (select price_id from checkout_snapshots where plan_key = 'starter' and interval = 'monthly'),
    p_amount_minor => (select amount_minor from checkout_snapshots where plan_key = 'starter' and interval = 'monthly')
  ), true, 'a failed initial payment is recorded without rejecting the event'
);
select is(
  (select plan_id from public.subscriptions where organization_id = (select value from checkout_ids where key = 'trial_org')),
  (select plan_id from trial_before), 'a failed initial payment preserves the trial plan'
);
select is(
  (select status from public.subscriptions where organization_id = (select value from checkout_ids where key = 'trial_org')),
  (select status from trial_before), 'a failed initial payment preserves trialing status'
);
select is(
  (select trial_ends_at from public.subscriptions where organization_id = (select value from checkout_ids where key = 'trial_org')),
  (select trial_ends_at from trial_before), 'a failed initial payment preserves the remaining trial'
);
select is(
  (select jsonb_build_object(
     'price', price_id, 'provider', provider,
     'provider_subscription_id', provider_subscription_id,
     'interval', billing_interval, 'checkout_completed_at', checkout_completed_at
   ) from public.subscriptions where organization_id = (select value from checkout_ids where key = 'trial_org')),
  jsonb_build_object(
    'price', null, 'provider', null,
    'provider_subscription_id', null, 'interval', null,
    'checkout_completed_at', null
  ),
  'a failed initial payment does not bind checkout identity'
);
select ok(
  (select payment_failed_at is not null and provider_status = 'past_due'
   from public.subscriptions where organization_id = (select value from checkout_ids where key = 'trial_org')),
  'the failed initial payment is recorded without ending the trial'
);
select is(
  public.apply_paymob_subscription_event(
    p_event_id => 'step17-trial-success',
    p_event_type => 'transaction.succeeded',
    p_payload => '{"verified":true}',
    p_organization_id => (select value from checkout_ids where key = 'trial_org'),
    p_subscription_id => 'step17-trial-subscription',
    p_provider_status => 'active',
    p_interval => 'monthly',
    p_plan_key => 'starter',
    p_period_start => now(),
    p_period_end => now() + interval '1 month',
    p_last_payment_at => now(),
    p_price_id => (select price_id from checkout_snapshots where plan_key = 'starter' and interval = 'monthly'),
    p_amount_minor => (select amount_minor from checkout_snapshots where plan_key = 'starter' and interval = 'monthly')
  ), true, 'a later successful verified checkout applies after the decline'
);
select is(
  (select jsonb_build_object('plan', plan.key, 'price', subscription.price_id, 'status', subscription.status)
   from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   where subscription.organization_id = (select value from checkout_ids where key = 'trial_org')),
  (select jsonb_build_object('plan', 'starter', 'price', price_id, 'status', 'active')
   from checkout_snapshots where plan_key = 'starter' and interval = 'monthly'),
  'successful retry binds the exact selected launch plan and price'
);

delete from public.subscriptions
where organization_id = (select value from checkout_ids where key = 'missing_org');
reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select is(
  public.subscription_access_state((select value from checkout_ids where key = 'missing_org')),
  'checkout_required', 'an organization without a subscription requires checkout'
);
reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
set local role service_role;
select is(
  public.apply_paymob_subscription_event(
    p_event_id => 'step17-missing-success',
    p_event_type => 'transaction.succeeded',
    p_payload => '{"verified":true}',
    p_organization_id => (select value from checkout_ids where key = 'missing_org'),
    p_subscription_id => 'step17-created-subscription',
    p_provider_status => 'active',
    p_interval => 'monthly',
    p_plan_key => 'solo',
    p_period_start => now(),
    p_period_end => now() + interval '1 month',
    p_last_payment_at => now(),
    p_price_id => (select price_id from checkout_snapshots where plan_key = 'solo' and interval = 'monthly'),
    p_amount_minor => (select amount_minor from checkout_snapshots where plan_key = 'solo' and interval = 'monthly')
  ), true, 'successful checkout creates a missing subscription'
);
select is(
  (select jsonb_build_object(
     'plan', plan.key, 'price', subscription.price_id,
     'interval', subscription.billing_interval,
     'provider_subscription_id', subscription.provider_subscription_id
   )
   from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   where subscription.organization_id = (select value from checkout_ids where key = 'missing_org')),
  (select jsonb_build_object(
     'plan', 'solo', 'price', price_id,
     'interval', 'monthly', 'provider_subscription_id', 'step17-created-subscription'
   ) from checkout_snapshots where plan_key = 'solo' and interval = 'monthly'),
  'the created subscription has the exact signed plan, price, interval and provider id'
);
select is(
  (select count(*) from public.subscriptions where organization_id = (select value from checkout_ids where key = 'missing_org')),
  1::bigint, 'successful checkout creates exactly one subscription row'
);

select * from finish();
rollback;
