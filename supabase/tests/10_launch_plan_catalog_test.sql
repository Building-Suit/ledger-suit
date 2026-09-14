-- Dormant launch catalog, commercial prices, and safe public projection.
begin;

create extension if not exists pgtap with schema extensions;
select plan(33);

select is(
  (select array_agg(key order by sort_order)
   from public.subscription_plans where is_public and is_active),
  array['solo', 'starter', 'business', 'scale']::text[],
  'the public launch catalog contains the three launch plans and Scale preview'
);

select is(
  (select array_agg(key order by sort_order)
   from public.subscription_plans where is_purchasable),
  array['solo', 'starter', 'business']::text[],
  'only Solo, Starter, and Business are purchasable'
);

select ok(
  (select is_active and not is_public and not is_purchasable
   from public.subscription_plans where key = 'ledger_suit'),
  'the current Ledger Suit subscription plan remains active and private'
);

select is(
  (select count(*) from public.subscription_plans where key like 'legacy_%'),
  3::bigint,
  'the three unused original plan rows are preserved as legacy plans'
);

select is(
  (select count(*) from public.subscription_plans where key = 'enterprise'),
  0::bigint,
  'Enterprise is not fabricated as a purchasable catalog plan'
);

select is(
  (select count(*) from public.subscription_plan_prices price
   join public.subscription_plans plan on plan.id = price.plan_id
   where plan.key = 'scale' and price.is_active),
  0::bigint,
  'Scale has no active price'
);

select is(
  (select count(*) from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key = 'scale'),
  0::bigint,
  'Scale has no invented entitlements'
);

select is(
  (select jsonb_object_agg(
     plan.key || ':' || price.interval::text,
     price.amount_minor
   )
   from public.subscription_plan_prices price
   join public.subscription_plans plan on plan.id = price.plan_id
   where plan.key in ('solo', 'starter', 'business') and price.is_active),
  jsonb_build_object(
    'solo:monthly', 39900,
    'solo:yearly', 325584,
    'starter:monthly', 59900,
    'starter:yearly', 488784,
    'business:monthly', 109900,
    'business:yearly', 896784
  ),
  'all six launch prices use the approved monthly and annual amounts'
);

select is(
  (select count(*) from public.subscription_plan_prices price
   join public.subscription_plans plan on plan.id = price.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and (price.provider is not null or price.provider_price_id is not null)),
  0::bigint,
  'launch commercial prices do not embed provider mappings'
);

select is(
  (select count(*)
   from public.subscription_plans plan
   join public.subscription_plan_prices monthly
     on monthly.plan_id = plan.id and monthly.interval = 'monthly' and monthly.is_active
   join public.subscription_plan_prices yearly
     on yearly.plan_id = plan.id and yearly.interval = 'yearly' and yearly.is_active
   where plan.key in ('solo', 'starter', 'business')
     and yearly.amount_minor * 100 = monthly.amount_minor * 12 * 68),
  3::bigint,
  'every annual price is exactly monthly times twelve less 32 percent'
);

select is(
  (select count(*) from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')),
  51::bigint,
  'every launch plan has all seventeen explicit entitlements'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.limit_value)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'max_members'),
  '{"solo": 1, "starter": 3, "business": 10}'::jsonb,
  'member limits match the launch matrix'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.limit_value)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'max_monthly_transactions'),
  '{"solo": 500, "starter": 2500, "business": 10000}'::jsonb,
  'monthly transaction limits match the launch matrix'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.limit_value)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'max_storage_bytes'),
  '{"solo": 1073741824, "starter": 5368709120, "business": 21474836480}'::jsonb,
  'storage limits match the launch matrix'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.limit_value)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'max_accounts'),
  '{"solo": 30, "starter": 100, "business": 300}'::jsonb,
  'account limits match the launch matrix'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.limit_value)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'max_counterparties'),
  '{"solo": 100, "starter": 1000, "business": 5000}'::jsonb,
  'counterparty limits match the launch matrix'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.limit_value)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'max_recurring_rules'),
  '{"solo": 5, "starter": 25, "business": 100}'::jsonb,
  'recurring-rule limits match the launch matrix'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.limit_value)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'max_custom_roles'),
  '{"solo": 0, "starter": 3, "business": 10}'::jsonb,
  'custom-role limits match the launch matrix'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.limit_value)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'audit_log_retention_days'),
  '{"solo": 90, "starter": 365, "business": 1095}'::jsonb,
  'audit visibility windows match the launch matrix'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.is_enabled)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'multi_currency'),
  '{"solo": false, "starter": false, "business": true}'::jsonb,
  'multi-currency is Business-only'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.is_enabled)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'imports'),
  '{"solo": false, "starter": true, "business": true}'::jsonb,
  'imports are Starter and Business only'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.is_enabled)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'exports'),
  '{"solo": true, "starter": true, "business": true}'::jsonb,
  'exports are enabled for every launch plan'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.is_enabled)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'core_reports'),
  '{"solo": true, "starter": true, "business": true}'::jsonb,
  'core financial reports are enabled for every launch plan'
);

select is(
  (select jsonb_object_agg(plan.key, entitlement.is_enabled)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key = 'priority_support'),
  '{"solo": false, "starter": false, "business": true}'::jsonb,
  'priority support is Business-only'
);

select is(
  (select count(*)
   from public.subscription_entitlements entitlement
   join public.subscription_plans plan on plan.id = entitlement.plan_id
   where plan.key in ('solo', 'starter', 'business')
     and entitlement.feature_key in ('branches', 'advanced_analytics', 'api_access')
     and entitlement.is_enabled),
  0::bigint,
  'future-only capabilities are disabled on every launch plan'
);

select is(
  (select amount_minor from app.resolve_purchasable_plan('starter', 'yearly')),
  488784::bigint,
  'the server resolver returns the authoritative Starter annual price'
);

select throws_ok(
  $$select * from app.resolve_purchasable_plan('scale', 'monthly')$$,
  '22023', 'PLAN_NOT_AVAILABLE',
  'Scale cannot resolve for checkout'
);

select throws_ok(
  $$select * from app.resolve_purchasable_plan('ledger_suit', 'monthly')$$,
  '22023', 'PLAN_NOT_AVAILABLE',
  'the private legacy plan cannot resolve for new checkout'
);

select is(
  (select array_agg(plan_key order by sort_order)
   from public.subscription_plan_catalog()),
  array['solo', 'starter', 'business', 'scale']::text[],
  'the safe catalog projection includes launch plans in display order'
);

select is(
  (select prices from public.subscription_plan_catalog()
   where plan_key = 'scale'),
  '{}'::jsonb,
  'the public Scale preview has no fake price'
);

select ok(
  has_function_privilege('anon', 'public.subscription_plan_catalog()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.subscription_plan_catalog()', 'EXECUTE'),
  'anonymous and authenticated clients can read the safe catalog projection'
);

set local role anon;
select is(
  (select count(*) from public.subscription_plan_catalog()),
  4::bigint,
  'an anonymous caller can execute the safe catalog projection'
);
reset role;

select ok(
  not has_table_privilege('anon', 'public.subscription_plan_prices', 'SELECT')
  and not has_table_privilege('authenticated', 'public.subscription_plan_prices', 'SELECT')
  and not has_table_privilege('authenticated', 'public.subscription_plans', 'SELECT')
  and not has_table_privilege('authenticated', 'public.subscription_entitlements', 'SELECT'),
  'clients cannot read raw catalog tables or provider mapping columns'
);

select * from finish();
rollback;
