-- Read-only launch verification. Run as a trusted database operator after the
-- production migration deploy. Every row in the first result set must pass.
begin transaction read only;

-- This operator-only script must exercise the same public diagnostic contract
-- used by authorized customers for every organization without depending on one
-- particular member session.
set local app.bypass_authz = 'on';

with expected_prices(plan_key, interval, amount_minor) as (
  values
    ('solo', 'monthly'::public.billing_interval, 39900::bigint),
    ('solo', 'yearly'::public.billing_interval, 325584::bigint),
    ('starter', 'monthly'::public.billing_interval, 59900::bigint),
    ('starter', 'yearly'::public.billing_interval, 488784::bigint),
    ('business', 'monthly'::public.billing_interval, 109900::bigint),
    ('business', 'yearly'::public.billing_interval, 896784::bigint)
), launch_prices as (
  select plan.key as plan_key, price.interval, price.amount_minor,
         btrim(price.currency_code) as currency_code
  from public.subscription_plans plan
  join public.subscription_plan_prices price on price.plan_id = plan.id
  where plan.key in ('solo', 'starter', 'business') and price.is_active
), expected_entitlements(plan_key, feature_key, is_enabled, limit_value) as (
  values
    ('solo', 'max_members', true, 1::bigint),
    ('solo', 'max_monthly_transactions', true, 500::bigint),
    ('solo', 'max_storage_bytes', true, 1073741824::bigint),
    ('solo', 'max_accounts', true, 30::bigint),
    ('solo', 'max_counterparties', true, 100::bigint),
    ('solo', 'max_recurring_rules', true, 5::bigint),
    ('solo', 'max_custom_roles', true, 0::bigint),
    ('solo', 'audit_log_retention_days', true, 90::bigint),
    ('solo', 'multi_currency', false, null::bigint),
    ('solo', 'imports', false, null::bigint),
    ('solo', 'exports', true, null::bigint),
    ('solo', 'core_reports', true, null::bigint),
    ('solo', 'priority_support', false, null::bigint),
    ('solo', 'branches', false, null::bigint),
    ('solo', 'advanced_analytics', false, null::bigint),
    ('solo', 'api_access', false, null::bigint),
    ('solo', 'max_owned_organizations', true, 1::bigint),
    ('starter', 'max_members', true, 3::bigint),
    ('starter', 'max_monthly_transactions', true, 2500::bigint),
    ('starter', 'max_storage_bytes', true, 5368709120::bigint),
    ('starter', 'max_accounts', true, 100::bigint),
    ('starter', 'max_counterparties', true, 1000::bigint),
    ('starter', 'max_recurring_rules', true, 25::bigint),
    ('starter', 'max_custom_roles', true, 3::bigint),
    ('starter', 'audit_log_retention_days', true, 365::bigint),
    ('starter', 'multi_currency', false, null::bigint),
    ('starter', 'imports', true, null::bigint),
    ('starter', 'exports', true, null::bigint),
    ('starter', 'core_reports', true, null::bigint),
    ('starter', 'priority_support', false, null::bigint),
    ('starter', 'branches', false, null::bigint),
    ('starter', 'advanced_analytics', false, null::bigint),
    ('starter', 'api_access', false, null::bigint),
    ('starter', 'max_owned_organizations', true, 1::bigint),
    ('business', 'max_members', true, 10::bigint),
    ('business', 'max_monthly_transactions', true, 10000::bigint),
    ('business', 'max_storage_bytes', true, 21474836480::bigint),
    ('business', 'max_accounts', true, 300::bigint),
    ('business', 'max_counterparties', true, 5000::bigint),
    ('business', 'max_recurring_rules', true, 100::bigint),
    ('business', 'max_custom_roles', true, 10::bigint),
    ('business', 'audit_log_retention_days', true, 1095::bigint),
    ('business', 'multi_currency', true, null::bigint),
    ('business', 'imports', true, null::bigint),
    ('business', 'exports', true, null::bigint),
    ('business', 'core_reports', true, null::bigint),
    ('business', 'priority_support', true, null::bigint),
    ('business', 'branches', false, null::bigint),
    ('business', 'advanced_analytics', false, null::bigint),
    ('business', 'api_access', false, null::bigint),
    ('business', 'max_owned_organizations', true, 1::bigint)
), launch_entitlements as (
  select plan.key as plan_key, entitlement.feature_key,
         entitlement.is_enabled, entitlement.limit_value
  from public.subscription_plans plan
  join public.subscription_entitlements entitlement
    on entitlement.plan_id = plan.id
  where plan.key in ('solo', 'starter', 'business')
), trial_entitlements as (
  select entitlement.feature_key, entitlement.is_enabled,
         entitlement.limit_value
  from public.subscription_plans plan
  join public.subscription_entitlements entitlement
    on entitlement.plan_id = plan.id
  where plan.key = 'trial'
), business_entitlements as (
  select entitlement.feature_key, entitlement.is_enabled,
         entitlement.limit_value
  from public.subscription_plans plan
  join public.subscription_entitlements entitlement
    on entitlement.plan_id = plan.id
  where plan.key = 'business'
), trial_business_drift as (
  select coalesce(trial.feature_key, business.feature_key) as feature_key
  from trial_entitlements trial
  full join business_entitlements business using (feature_key)
  where coalesce(trial.feature_key, business.feature_key) <> 'priority_support'
    and (
      trial.feature_key is null
      or business.feature_key is null
      or trial.is_enabled is distinct from business.is_enabled
      or trial.limit_value is distinct from business.limit_value
    )
), checks(check_name, passed, details) as (
  select 'launch catalog flags',
    count(*) = 3 and bool_and(is_public and is_active and is_purchasable),
    format('%s qualifying plans', count(*))
  from public.subscription_plans
  where key in ('solo', 'starter', 'business')
  union all
  select 'only launch plans are purchasable',
    not exists (
      select 1 from public.subscription_plans
      where is_purchasable and key not in ('solo', 'starter', 'business')
    ), 'no compatibility, preview, or future plan may be purchasable'
  union all
  select 'public commercial catalog is exact',
    not exists (
      select 1 from public.subscription_plans
      where is_public and is_active
        and key not in ('solo', 'starter', 'business', 'scale')
    ), 'active public plans are limited to launch plans and the Scale preview'
  union all
  select 'six exact EGP prices',
    count(*) = 6 and bool_and(
      actual.amount_minor = expected.amount_minor
      and actual.currency_code = 'EGP'
    ), format('%s matching prices', count(*))
  from expected_prices expected
  join launch_prices actual using (plan_key, interval)
  union all
  select 'annual discount formula',
    count(*) = 3 and bool_and(yearly.amount_minor * 100 = monthly.amount_minor * 12 * 68),
    'yearly = monthly x 12 x 0.68 in integer minor units'
  from launch_prices monthly
  join launch_prices yearly using (plan_key)
  where monthly.interval = 'monthly' and yearly.interval = 'yearly'
  union all
  select 'exact launch entitlements',
    count(*) = 51 and bool_and(
      actual.is_enabled = expected.is_enabled
      and actual.limit_value is not distinct from expected.limit_value
    ), format('%s matching entitlements', count(*))
  from expected_entitlements expected
  join launch_entitlements actual using (plan_key, feature_key)
  union all
  select 'no unexpected launch entitlements',
    count(*) = 51, format('%s actual entitlements', count(*))
  from launch_entitlements
  union all
  select 'Scale is preview-only',
    count(*) = 1 and bool_and(
      plan.is_public and plan.is_active and not plan.is_purchasable
      and not exists (
        select 1 from public.subscription_plan_prices price
        where price.plan_id = plan.id and price.is_active
      )
      and not exists (
        select 1 from public.subscription_entitlements entitlement
        where entitlement.plan_id = plan.id
      )
    ), 'Scale must have no active price or entitlement rows'
  from public.subscription_plans plan where plan.key = 'scale'
  union all
  select 'Enterprise remains presentation-only',
    not exists (
      select 1 from public.subscription_plans plan
      where plan.key = 'enterprise'
    ), 'no fabricated Enterprise subscription-plan row exists'
  union all
  select 'ledger_suit remains private compatibility',
    count(*) = 1 and bool_and(not is_public and is_active and not is_purchasable),
    'Step 21 migration was intentionally skipped'
  from public.subscription_plans where key = 'ledger_suit'
  union all
  select 'dedicated trial plan contract',
    count(*) = 1 and bool_and(
      not plan.is_public and plan.is_active and not plan.is_purchasable
      and not exists (
        select 1 from public.subscription_plan_prices price
        where price.plan_id = plan.id
      )
      and (select count(*) from trial_entitlements) = 17
      and not exists (select 1 from trial_business_drift)
      and exists (
        select 1 from trial_entitlements entitlement
        where entitlement.feature_key = 'priority_support'
          and not entitlement.is_enabled
          and entitlement.limit_value is null
      )
  ),
    'private 14-day trial matches Business product entitlements except Priority Support'
  from public.subscription_plans plan where plan.key = 'trial'
  union all
  select 'sensitive direct access remains revoked',
    not has_table_privilege('authenticated', 'public.subscriptions', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.audit_logs', 'SELECT')
    and not has_table_privilege('authenticated', 'public.attachments', 'INSERT')
    and not has_table_privilege('authenticated', 'public.attachments', 'DELETE'),
    'subscriptions, audit logs, and attachment lifecycle use trusted boundaries'
  union all
  select 'attachment bucket is private',
    count(*) = 1 and bool_and(not public and file_size_limit = 26214400),
    'attachments: private, 25 MiB object limit'
  from storage.buckets where id = 'attachments'
  union all
  select 'scheduled jobs are active on exact schedules',
    count(*) = 2 and bool_and(
      active and schedule = case jobname
        when 'ledger-suit-notification-email' then '*/5 * * * *'
        when 'ledger-suit-storage-cleanup' then '*/10 * * * *'
      end
    ),
    string_agg(jobname || '=' || schedule, ', ' order by jobname)
  from cron.job
  where jobname in ('ledger-suit-notification-email', 'ledger-suit-storage-cleanup')
  union all
  select 'scheduler Vault names exist',
    count(*) = 2,
    format('%s required Vault entries found; values intentionally hidden', count(*))
  from vault.secrets
  where name in ('ledger_suit_project_url', 'ledger_suit_service_role_key')
  union all
  select 'balance-sheet integrity contract passes',
    coalesce(bool_and(
      (public.check_balance_sheet_integrity(organization.id) ->> 'balanced')::boolean
    ), true),
    format('%s organizations checked through public.check_balance_sheet_integrity', count(*))
  from public.organizations organization
)
select check_name, passed, details
from checks
order by passed, check_name;

-- Review subscription distribution before launch. New organizations use trial;
-- Step 21 was skipped, so ledger_suit and legacy_* rows remain unchanged.
select plan.key as plan_key, subscription.status, count(*) as subscriptions
from public.subscriptions subscription
join public.subscription_plans plan on plan.id = subscription.plan_id
group by plan.key, subscription.status
order by plan.key, subscription.status;

-- Trusted, membership-independent physical journal integrity. Every row must
-- show zero unbalanced journals.
with journals as (
  select entry.organization_id, entry.transaction_id,
         coalesce(sum(entry.base_amount_minor) filter (where entry.side = 'debit'), 0) as debits,
         coalesce(sum(entry.base_amount_minor) filter (where entry.side = 'credit'), 0) as credits
  from public.transaction_entries entry
  group by entry.organization_id, entry.transaction_id
)
select organization.id, organization.name,
       count(journal.transaction_id) as journals,
       count(journal.transaction_id) filter (
         where journal.debits <> journal.credits
       ) as unbalanced_journals,
       public.check_balance_sheet_integrity(organization.id) as balance_sheet_integrity
from public.organizations organization
left join journals journal on journal.organization_id = organization.id
group by organization.id, organization.name, organization.created_at
order by organization.created_at;

rollback;
