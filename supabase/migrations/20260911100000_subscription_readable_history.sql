-- Preserve readable accounting history when a subscription can no longer
-- write. Subscription state gates mutations; it must never erase a member's
-- role-granted read access to existing tenant data.

create or replace function app.subscription_access_state(p_organization_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case
      when subscription.status = 'trialing'
        and subscription.trial_ends_at is not null
        and subscription.trial_ends_at > now()
        then 'trialing'
      when subscription.status = 'active'
        and (
          subscription.current_period_end is null
          or subscription.current_period_end > now()
        )
        then 'active'
      when subscription.status in ('past_due', 'grace_period')
        and subscription.grace_period_ends_at is not null
        and subscription.grace_period_ends_at > now()
        then 'grace_period'
      else 'read_only'
    end
    from public.subscriptions subscription
    where subscription.organization_id = p_organization_id
  ), 'checkout_required');
$$;

comment on function app.subscription_access_state(uuid) is
  'Returns checkout_required only when no subscription exists; lapsed, suspended, or cancelled subscriptions retain read_only accounting access.';

create or replace function app.capability_available(
  p_organization_id uuid,
  p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_capability = any (app.capabilities_for(p_organization_id))
    and (
      p_capability like '%.read'
      or p_capability = 'billing.manage'
      or app.subscription_writes_allowed(p_organization_id)
    );
$$;

comment on function app.capability_available(uuid, text) is
  'Applies subscription state after membership and role resolution: reads and billing management survive lapse, while product mutations require write access.';

create or replace function public.my_capabilities(p_organization_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not app.is_org_member(p_organization_id) then '{}'::text[]
    else coalesce((
      select array_agg(capability order by capability)
      from unnest(app.capabilities_for(p_organization_id)) capability
      where capability like '%.read'
         or capability = 'billing.manage'
         or app.subscription_writes_allowed(p_organization_id)
    ), '{}'::text[])
  end;
$$;

comment on function public.my_capabilities(uuid) is
  'Tenant-checked effective capabilities. Lapsed subscriptions retain role-granted reads and billing management but no product mutation capabilities.';
