-- New organizations receive the dedicated Business-level product trial while
-- compatibility subscriptions and the paid checkout boundary remain intact.
begin;

create extension if not exists pgtap with schema extensions;
select plan(27);

select ok(
  (select not is_public and is_active and not is_purchasable
   from public.subscription_plans where key = 'trial'),
  'the trial plan is private, active, and not purchasable'
);

select is(
  (select count(*) from public.subscription_plan_prices price
   join public.subscription_plans plan on plan.id = price.plan_id
   where plan.key = 'trial'),
  0::bigint,
  'the trial has no price or provider mapping rows'
);

select is(
  (select count(*) from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key = 'trial'),
  17::bigint,
  'the trial has all seventeen explicit entitlements'
);

select is(
  (select jsonb_object_agg(
     entitlement.feature_key,
     jsonb_build_object('enabled', entitlement.is_enabled, 'limit', entitlement.limit_value)
   )
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key = 'trial'),
  jsonb_build_object(
    'max_members', jsonb_build_object('enabled', true, 'limit', 10),
    'max_monthly_transactions', jsonb_build_object('enabled', true, 'limit', 10000),
    'max_storage_bytes', jsonb_build_object('enabled', true, 'limit', 21474836480::bigint),
    'max_accounts', jsonb_build_object('enabled', true, 'limit', 300),
    'max_counterparties', jsonb_build_object('enabled', true, 'limit', 5000),
    'max_recurring_rules', jsonb_build_object('enabled', true, 'limit', 100),
    'max_custom_roles', jsonb_build_object('enabled', true, 'limit', 10),
    'audit_log_retention_days', jsonb_build_object('enabled', true, 'limit', 1095),
    'multi_currency', jsonb_build_object('enabled', true, 'limit', null),
    'imports', jsonb_build_object('enabled', true, 'limit', null),
    'exports', jsonb_build_object('enabled', true, 'limit', null),
    'core_reports', jsonb_build_object('enabled', true, 'limit', null),
    'priority_support', jsonb_build_object('enabled', false, 'limit', null),
    'branches', jsonb_build_object('enabled', false, 'limit', null),
    'advanced_analytics', jsonb_build_object('enabled', false, 'limit', null),
    'api_access', jsonb_build_object('enabled', false, 'limit', null),
    'max_owned_organizations', jsonb_build_object('enabled', true, 'limit', 1)
  ),
  'the persisted trial entitlement contract is exact'
);

select is(
  (select count(*)
   from public.subscription_entitlements trial
   join public.subscription_plans trial_plan
     on trial_plan.id = trial.plan_id and trial_plan.key = 'trial'
   full join (
     select business.feature_key, business.is_enabled, business.limit_value
     from public.subscription_entitlements business
     join public.subscription_plans business_plan
       on business_plan.id = business.plan_id and business_plan.key = 'business'
     where business.feature_key <> 'priority_support'
   ) business using (feature_key)
   where trial.feature_key <> 'priority_support'
     and (trial.is_enabled is distinct from business.is_enabled
       or trial.limit_value is distinct from business.limit_value)),
  0::bigint,
  'trial product entitlements match Business except Priority Support'
);

select ok(
  (select not trial.is_enabled and business.is_enabled
   from public.subscription_entitlements trial
   join public.subscription_plans trial_plan
     on trial_plan.id = trial.plan_id and trial_plan.key = 'trial'
   join public.subscription_entitlements business
     on business.feature_key = trial.feature_key
   join public.subscription_plans business_plan
     on business_plan.id = business.plan_id and business_plan.key = 'business'
   where trial.feature_key = 'priority_support'),
  'Priority Support is excluded only from the trial'
);

select throws_ok(
  $$select * from app.resolve_purchasable_plan('trial', 'monthly')$$,
  '22023', 'PLAN_NOT_AVAILABLE',
  'the private trial cannot resolve for checkout'
);

select is(
  (select count(*) from public.subscription_plan_catalog() where plan_key = 'trial'),
  0::bigint,
  'the trial does not appear in the public catalog'
);

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (
  select id from public.organizations where name = 'Alpha Trading'
);

create temp table trial_policy_ids (key text primary key, value uuid not null);
grant all on trial_policy_ids to authenticated, service_role;

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

insert into trial_policy_ids values (
  'org', public.create_organization('Business Trial Policy Co', 'EGP')
);

select is(
  (select jsonb_build_object(
     'plan', (select plan_key from public.subscription_usage_summary(subscription.organization_id) limit 1),
     'status', subscription.status,
     'has_start', subscription.trial_started_at is not null,
     'fourteen_days', subscription.trial_ends_at between
       subscription.trial_started_at + interval '13 days 23 hours 59 minutes'
       and subscription.trial_started_at + interval '14 days 1 minute'
   )
   from public.subscriptions subscription
   where subscription.organization_id = (select value from trial_policy_ids where key = 'org')),
  jsonb_build_object('plan', 'trial', 'status', 'trialing', 'has_start', true, 'fourteen_days', true),
  'a new organization receives one 14-day trial subscription'
);

reset role;
select is(
  (select plan.key from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   join public.organizations organization on organization.id = subscription.organization_id
   where organization.name = 'Alpha Trading'),
  'ledger_suit',
  'provisioning a new trial leaves an existing compatibility subscription unchanged'
);
set local role authenticated;

select ok(
  (select price_id is null and provider is null
      and provider_subscription_id is null and billing_interval is null
   from public.subscriptions
   where organization_id = (select value from trial_policy_ids where key = 'org')),
  'signup selects no paid plan, price, provider, or interval'
);

select is(
  public.subscription_access_state((select value from trial_policy_ids where key = 'org')),
  'trialing',
  'the unexpired trial permits normal product access'
);

select is(
  (select jsonb_object_agg(quota_key, limit_value)
   from public.subscription_usage_summary((select value from trial_policy_ids where key = 'org'))),
  jsonb_build_object(
    'max_members', 10,
    'max_monthly_transactions', 10000,
    'max_storage_bytes', 21474836480::bigint,
    'max_accounts', 300,
    'max_counterparties', 5000,
    'max_recurring_rules', 100,
    'max_custom_roles', 10
  ),
  'the authoritative usage summary exposes Business-level trial quotas'
);

select ok(
  public.can_use_feature((select value from trial_policy_ids where key = 'org'), 'multi_currency')
  and public.can_use_feature((select value from trial_policy_ids where key = 'org'), 'imports')
  and public.can_use_feature((select value from trial_policy_ids where key = 'org'), 'exports')
  and public.can_use_feature((select value from trial_policy_ids where key = 'org'), 'core_reports'),
  'Business product features are enabled during the trial'
);

select ok(
  not public.can_use_feature((select value from trial_policy_ids where key = 'org'), 'priority_support'),
  'Priority Support is unavailable during the trial'
);

select ok(
  not public.can_use_feature((select value from trial_policy_ids where key = 'org'), 'branches')
  and not public.can_use_feature((select value from trial_policy_ids where key = 'org'), 'advanced_analytics')
  and not public.can_use_feature((select value from trial_policy_ids where key = 'org'), 'api_access'),
  'Coming Soon features remain disabled during the trial'
);

select lives_ok(
  format(
    'select * from public.billing_checkout_context(%L, %L, %L)',
    (select value from trial_policy_ids where key = 'org'), 'solo', 'monthly'
  ),
  'an owner may voluntarily start safe paid checkout during the trial'
);

reset role;
create temp table trial_before_failure as
select plan_id, status, trial_started_at, trial_ends_at
from public.subscriptions
where organization_id = (select value from trial_policy_ids where key = 'org');
grant all on trial_before_failure to service_role;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000000","role":"service_role"}', true);
set local role service_role;

select is(
  public.apply_paymob_subscription_event(
    p_event_id => 'business-trial-failure',
    p_event_type => 'transaction.failed',
    p_payload => '{"verified":true}',
    p_organization_id => (select value from trial_policy_ids where key = 'org'),
    p_subscription_id => 'business-trial-attempt',
    p_provider_status => 'past_due',
    p_interval => 'monthly',
    p_plan_key => 'starter',
    p_payment_failed_at => now(),
    p_price_id => (select price.id from public.subscription_plan_prices price
      join public.subscription_plans plan on plan.id = price.plan_id
      where plan.key = 'starter' and price.interval = 'monthly' and price.is_active),
    p_amount_minor => 59900
  ),
  true,
  'a failed voluntary checkout is recorded'
);

select is(
  (select jsonb_build_object(
     'plan_id', plan_id, 'status', status,
     'trial_started_at', trial_started_at, 'trial_ends_at', trial_ends_at
   ) from public.subscriptions
   where organization_id = (select value from trial_policy_ids where key = 'org')),
  (select jsonb_build_object(
     'plan_id', plan_id, 'status', status,
     'trial_started_at', trial_started_at, 'trial_ends_at', trial_ends_at
   ) from trial_before_failure),
  'failed checkout preserves the original trial plan, status, and dates'
);

select ok(
  (select price_id is null and provider is null
      and provider_subscription_id is null and billing_interval is null
      and checkout_completed_at is null and payment_failed_at is not null
   from public.subscriptions
   where organization_id = (select value from trial_policy_ids where key = 'org')),
  'failed checkout does not bind paid identity or restart the trial'
);

reset role;
update public.subscriptions
set trial_ends_at = now() - interval '1 second'
where organization_id = (select value from trial_policy_ids where key = 'org');

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

select is(
  public.subscription_access_state((select value from trial_policy_ids where key = 'org')),
  'read_only',
  'an expired trial resolves to read-only without a status scheduler'
);

select ok(
  'transactions.read' = any(public.my_capabilities((select value from trial_policy_ids where key = 'org')))
  and 'billing.manage' = any(public.my_capabilities((select value from trial_policy_ids where key = 'org'))),
  'expired trials retain role-granted reads and billing management'
);

select ok(
  not ('transactions.create' = any(public.my_capabilities((select value from trial_policy_ids where key = 'org')))),
  'expired trials lose product mutation capabilities'
);

select throws_ok(
  format(
    'select public.create_account(%L, %L, %L, %L)',
    (select value from trial_policy_ids where key = 'org'),
    'Blocked expired trial account', 'asset', 'bank'
  ),
  '42501', null,
  'the authoritative write boundary blocks expired-trial mutations'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000000","role":"service_role"}', true);
set local role service_role;

select is(
  public.apply_paymob_subscription_event(
    p_event_id => 'business-trial-success',
    p_event_type => 'transaction.succeeded',
    p_payload => '{"verified":true}',
    p_organization_id => (select value from trial_policy_ids where key = 'org'),
    p_subscription_id => 'business-trial-subscription',
    p_provider_status => 'active',
    p_interval => 'monthly',
    p_plan_key => 'starter',
    p_period_start => now(),
    p_period_end => now() + interval '1 month',
    p_last_payment_at => now(),
    p_price_id => (select price.id from public.subscription_plan_prices price
      join public.subscription_plans plan on plan.id = price.plan_id
      where plan.key = 'starter' and price.interval = 'monthly' and price.is_active),
    p_amount_minor => 59900
  ),
  true,
  'a verified checkout activates a selected paid plan after expiry'
);

select is(
  (select jsonb_build_object(
     'plan', plan.key, 'status', subscription.status,
     'price', price.amount_minor, 'interval', subscription.billing_interval,
     'provider', subscription.provider,
     'provider_subscription_id', subscription.provider_subscription_id
   )
   from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   join public.subscription_plan_prices price on price.id = subscription.price_id
   where subscription.organization_id = (select value from trial_policy_ids where key = 'org')),
  jsonb_build_object(
    'plan', 'starter', 'status', 'active', 'price', 59900,
    'interval', 'monthly', 'provider', 'paymob',
    'provider_subscription_id', 'business-trial-subscription'
  ),
  'successful fulfillment replaces trial with the exact paid plan and identity'
);

select is(
  (select count(*) from public.subscriptions
   where organization_id = (select value from trial_policy_ids where key = 'org')),
  1::bigint,
  'conversion updates the single subscription instead of creating a second trial'
);

select * from finish();
rollback;
