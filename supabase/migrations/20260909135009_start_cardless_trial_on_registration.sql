-- Start the product trial when an organization is provisioned. Stripe is only
-- involved after the trial, when the owner chooses a billing interval.

update public.subscriptions
set status = 'trialing',
    trial_started_at = now(),
    trial_ends_at = now() + interval '14 days'
where status = 'suspended'
  and checkout_completed_at is null
  and provider_subscription_id is null
  and trial_started_at is null;

create or replace function app.start_default_subscription()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_plan uuid;
begin
  select id into v_plan
  from public.subscription_plans
  where key = 'ledger_suit' and is_active;

  if v_plan is null then
    raise exception 'BILLING_CONFIGURATION_ERROR: Ledger Suit plan is missing';
  end if;

  insert into public.subscriptions (
    organization_id, plan_id, status, trial_started_at, trial_ends_at
  ) values (
    new.id, v_plan, 'trialing', now(), now() + interval '14 days'
  )
  on conflict (organization_id) do nothing;
  return new;
end;
$$;

create or replace function app.subscription_access_state(p_organization_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case
      when s.status = 'trialing'
        and s.trial_ends_at is not null
        and s.trial_ends_at > now()
        then 'trialing'
      when s.status = 'active'
        and (s.current_period_end is null or s.current_period_end > now())
        then 'active'
      when s.status in ('past_due', 'grace_period')
        and s.grace_period_ends_at is not null
        and s.grace_period_ends_at > now()
        then 'grace_period'
      else 'checkout_required'
    end
    from public.subscriptions s
    where s.organization_id = p_organization_id
  ), 'checkout_required');
$$;

-- Once access expires, retain only the two billing capabilities needed to
-- inspect the subscription and open Checkout. Product reads and writes are
-- both denied at the database authorization boundary.
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
      p_capability in ('billing.read', 'billing.manage')
      or app.subscription_writes_allowed(p_organization_id)
    );
$$;

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
      select array_agg(c order by c)
      from unnest(app.capabilities_for(p_organization_id)) c
      where c in ('billing.read', 'billing.manage')
         or app.subscription_writes_allowed(p_organization_id)
    ), '{}'::text[])
  end;
$$;
