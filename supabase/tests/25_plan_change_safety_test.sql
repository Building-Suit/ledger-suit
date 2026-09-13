-- Step 20: authorized, non-mutating plan-change preflight and safe downgrade.
begin;

create extension if not exists pgtap with schema extensions;
select plan(34);

create temp table plan_change_ids (key text primary key, value uuid not null);
grant all on plan_change_ids to authenticated, service_role;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'd0000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'owner-step20@ledgersuit.test',
  extensions.crypt('pw', extensions.gen_salt('bf')), now(),
  '{"provider":"email"}'::jsonb, '{"full_name":"Step 20 Owner"}'::jsonb,
  now(), now()
);

select set_config('request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

insert into plan_change_ids values (
  'organization',
  public.create_organization('Plan Change Safety Co', 'EGP')
);

select throws_ok(
  format(
    $$select * from public.plan_change_impact(%L, 'solo', 'monthly')$$,
    (select value from plan_change_ids where key = 'organization')
  ),
  'P0001', 'TRIAL_PLAN_CHANGE_REQUIRES_CHECKOUT',
  'the dedicated trial converts only through signed checkout'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
set local role service_role;

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from plan_change_ids where key = 'organization');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select throws_ok(
  format(
    $$select * from public.plan_change_impact(%L, 'solo', 'monthly')$$,
    (select value from plan_change_ids where key = 'organization')
  ),
  'P0001', 'LEGACY_PLAN_TRANSITION_NOT_APPROVED',
  'a real ledger_suit fixture cannot enter Step 20 transition handling'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000000","role":"service_role"}', true);
set local role service_role;

select is(
  (select plan.key from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   where subscription.organization_id =
     (select value from plan_change_ids where key = 'organization')),
  'ledger_suit',
  'a rejected legacy preflight leaves the compatibility subscription unchanged'
);

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'business'),
    billing_interval = 'monthly',
    status = 'active',
    provider = 'paymob',
    provider_subscription_id = 'step20-existing-subscription',
    provider_status = 'active',
    checkout_completed_at = now()
where organization_id = (select value from plan_change_ids where key = 'organization');

insert into public.organization_invitations (
  organization_id, email, token_hash, invited_by
) values (
  (select value from plan_change_ids where key = 'organization'),
  'reserved-step20@example.com', 'step20-reserved-seat',
  'd0000000-0000-4000-8000-000000000001'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select public.create_organization_role(
  (select value from plan_change_ids where key = 'organization'),
  'step20_role', 'Step 20 role', 'دور الخطوة ٢٠',
  array['organization.read']
);

select has_function(
  'public', 'plan_change_impact',
  array['uuid', 'text', 'billing_interval'],
  'plan-change preflight is exposed as an RPC'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.plan_change_impact(uuid,text,public.billing_interval)',
    'EXECUTE'
  ),
  'authenticated callers can execute the preflight boundary'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.plan_change_impact(uuid,text,public.billing_interval)',
    'EXECUTE'
  ),
  'anonymous callers cannot execute plan-change preflight'
);

select throws_ok(
  $$select * from public.plan_change_impact(
    '10000000-0000-4000-8000-000000000002', 'solo', 'monthly'
  )$$,
  '42501', null,
  'preflight preserves tenant and billing-capability authorization'
);

select throws_ok(
  format(
    $$select * from public.plan_change_impact(%L, 'scale', 'monthly')$$,
    (select value from plan_change_ids where key = 'organization')
  ),
  '22023', 'PLAN_NOT_AVAILABLE',
  'non-purchasable preview plans cannot be preflight targets'
);

create temp table plan_change_impact_snapshot as
select * from public.plan_change_impact(
  (select value from plan_change_ids where key = 'organization'),
  'solo', 'monthly'
);

select is(
  (select current_plan_key from plan_change_impact_snapshot),
  'business',
  'preflight identifies the current plan'
);

select is(
  (select target_plan_key || ':' || target_amount_minor
   from plan_change_impact_snapshot),
  'solo:39900',
  'preflight resolves the target plan and server-authoritative price'
);

select ok(
  (select change_direction = 'downgrade'
      and not provider_change_supported
      and requires_manual_handoff
   from plan_change_impact_snapshot),
  'Paymob changes are explicitly handed off instead of fabricated'
);

select is(
  jsonb_array_length((select quota_impacts from plan_change_impact_snapshot)),
  7,
  'all seven enforced quotas are compared'
);

select ok(
  (select (impact->>'used_value')::bigint = 2
      and (impact->>'target_limit_value')::bigint = 1
      and (impact->>'is_over_target')::boolean
      and (impact->>'will_block_new_activity')::boolean
   from plan_change_impact_snapshot,
        jsonb_array_elements(quota_impacts) impact
   where impact->>'quota_key' = 'max_members'),
  'reserved seats are included in member downgrade consequences'
);

select is(
  (select (impact->>'target_limit_value')::bigint
   from plan_change_impact_snapshot,
        jsonb_array_elements(quota_impacts) impact
   where impact->>'quota_key' = 'max_accounts'),
  30::bigint,
  'account consequences report the Solo boundary'
);

select is(
  (select (impact->>'target_limit_value')::bigint
   from plan_change_impact_snapshot,
        jsonb_array_elements(quota_impacts) impact
   where impact->>'quota_key' = 'max_storage_bytes'),
  1073741824::bigint,
  'storage consequences report the Solo byte boundary'
);

select ok(
  (select (impact->>'used_value')::bigint = 1
      and (impact->>'target_limit_value')::bigint = 0
      and (impact->>'is_over_target')::boolean
   from plan_change_impact_snapshot,
        jsonb_array_elements(quota_impacts) impact
   where impact->>'quota_key' = 'max_custom_roles'),
  'custom-role usage is reported as over the Solo boundary'
);

select is(
  (select count(*)::integer
   from plan_change_impact_snapshot,
        jsonb_array_elements(feature_impacts) impact
   where (impact->>'will_lose')::boolean),
  3,
  'imports, multi-currency, and priority support are identified as losses'
);

select ok(
  (select audit_history_current_days = 1095
      and audit_history_target_days = 90
      and audit_history_reduced
   from plan_change_impact_snapshot),
  'the shorter target audit-history window is explicit'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
set local role service_role;

select is(
  (select plan.key || ':' || subscription.provider_subscription_id
   from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   where subscription.organization_id =
     (select value from plan_change_ids where key = 'organization')),
  'business:step20-existing-subscription',
  'preflight does not mutate the subscription or provider identity'
);

select is(
  (select count(*)::integer from public.billing_events
   where organization_id = (select value from plan_change_ids where key = 'organization')),
  0,
  'preflight does not fabricate a provider event'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
set local role service_role;

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from plan_change_ids where key = 'organization');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select is(
  (select count(*)::integer from public.organization_roles
   where organization_id = (select value from plan_change_ids where key = 'organization')),
  1,
  'downgrade preserves readable over-limit custom-role history'
);

select throws_ok(
  format(
    $$select public.create_organization_role(%L, 'blocked_role',
      'Blocked role', 'دور محظور', array['organization.read'])$$,
    (select value from plan_change_ids where key = 'organization')
  ),
  'P0001',
  'PLAN_CUSTOM_ROLE_LIMIT_REACHED: usage 1, requested 1, limit 0',
  'downgrade blocks only a new quota-increasing custom role'
);

select throws_ok(
  format(
    $$select public.create_csv_import_batch(%L, 'blocked.csv', '[]'::jsonb)$$,
    (select value from plan_change_ids where key = 'organization')
  ),
  'P0001', 'FEATURE_NOT_AVAILABLE_ON_PLAN: imports',
  'downgrade applies the target feature boundary without deleting history'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
set local role service_role;

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'business')
where organization_id = (select value from plan_change_ids where key = 'organization');

select is(
  (select plan.key from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   where subscription.organization_id =
     (select value from plan_change_ids where key = 'organization')),
  'business',
  'an operational rollback restores the prior plan'
);

select is(
  (select count(*)::integer from public.organization_roles
   where organization_id = (select value from plan_change_ids where key = 'organization')),
  1,
  'rollback requires no accounting or resource restoration'
);

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from plan_change_ids where key = 'organization');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

create temp table plan_upgrade_impact_snapshot as
select * from public.plan_change_impact(
  (select value from plan_change_ids where key = 'organization'),
  'business', 'monthly'
);

select is(
  (select change_direction from plan_upgrade_impact_snapshot),
  'upgrade',
  'Solo to Business is classified as an upgrade'
);

select ok(
  (select bool_and(
      (impact->>'target_limit_value')::bigint
        > (impact->>'current_limit_value')::bigint
    )
   from plan_upgrade_impact_snapshot,
        jsonb_array_elements(quota_impacts) impact),
  'Business has a higher target allowance for every enforced quota'
);

select is(
  (select string_agg(impact->>'feature_key', ',' order by impact->>'feature_key')
   from plan_upgrade_impact_snapshot,
        jsonb_array_elements(feature_impacts) impact
   where (impact->>'will_gain')::boolean),
  'imports,multi_currency,priority_support',
  'Solo to Business identifies imports, multi-currency, and priority support as gains'
);

select ok(
  (select audit_history_current_days = 90
      and audit_history_target_days = 1095
      and not audit_history_reduced
   from plan_upgrade_impact_snapshot),
  'Solo to Business reports increased audit-history visibility'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
set local role service_role;

select is(
  (select plan.key || ':' || subscription.provider_subscription_id
   from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   where subscription.organization_id =
     (select value from plan_change_ids where key = 'organization')),
  'solo:step20-existing-subscription',
  'upgrade preflight does not mutate the subscription or provider identity'
);

select ok(
  public.apply_paymob_subscription_event(
    p_event_id => 'step20-idempotent-event',
    p_event_type => 'transaction.processed',
    p_payload => '{"step":20}'::jsonb,
    p_organization_id => (select value from plan_change_ids where key = 'organization'),
    p_subscription_id => 'step20-existing-subscription',
    p_provider_status => 'active',
    p_interval => 'monthly',
    p_plan_key => 'business',
    p_price_id => (select price.id from public.subscription_plan_prices price
      join public.subscription_plans plan on plan.id = price.plan_id
      where plan.key = 'business' and price.interval = 'monthly' and price.is_active),
    p_amount_minor => 109900
  ),
  'a verified provider event still processes after preflight'
);

select is(
  public.apply_paymob_subscription_event(
    p_event_id => 'step20-idempotent-event',
    p_event_type => 'transaction.processed',
    p_payload => '{"step":20}'::jsonb,
    p_organization_id => (select value from plan_change_ids where key = 'organization'),
    p_subscription_id => 'step20-existing-subscription',
    p_provider_status => 'active',
    p_interval => 'monthly',
    p_plan_key => 'business',
    p_price_id => (select price.id from public.subscription_plan_prices price
      join public.subscription_plans plan on plan.id = price.plan_id
      where plan.key = 'business' and price.interval = 'monthly' and price.is_active),
    p_amount_minor => 109900
  ),
  false,
  'provider-event replay remains idempotent'
);

select is(
  (select count(*)::integer from public.billing_events
   where provider = 'paymob' and provider_event_id = 'step20-idempotent-event'),
  1,
  'idempotent provider processing leaves one physical event'
);

select is(
  (select plan.key || ':' || subscription.provider_subscription_id
   from public.subscriptions subscription
   join public.subscription_plans plan on plan.id = subscription.plan_id
   where subscription.organization_id =
     (select value from plan_change_ids where key = 'organization')),
  'business:step20-existing-subscription',
  'verified replay preserves the exact subscription identity'
);

select * from finish();
rollback;
