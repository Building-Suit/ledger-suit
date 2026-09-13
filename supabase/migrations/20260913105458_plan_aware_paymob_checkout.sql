-- Resolve checkout amounts from the launch catalog and bind webhook updates to
-- the selected plan. Provider plan identifiers remain Edge Function secrets.

drop function if exists public.billing_checkout_context(uuid, public.billing_interval);

create function public.billing_checkout_context(
  p_organization_id uuid,
  p_plan_key text,
  p_interval public.billing_interval
)
returns table (
  organization_id uuid,
  organization_name text,
  billing_email text,
  billing_name text,
  billing_phone text,
  provider_customer_id text,
  access_state text,
  billing_interval public.billing_interval,
  plan_id uuid,
  plan_key text,
  price_id uuid,
  amount_minor bigint,
  currency_code char(3)
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_plan record;
begin
  perform app.require_capability(p_organization_id, 'billing.manage');

  if p_plan_key not in ('solo', 'starter', 'business') then
    raise exception 'PLAN_NOT_AVAILABLE' using errcode = '22023';
  end if;

  select * into strict v_plan
  from app.resolve_purchasable_plan(p_plan_key, p_interval, 'EGP');

  return query
  select o.id,
         o.name,
         p.email::text,
         p.full_name,
         p.phone,
         c.provider_customer_id,
         app.subscription_access_state(o.id),
         p_interval,
         v_plan.plan_id,
         p_plan_key,
         v_plan.price_id,
         v_plan.amount_minor,
         'EGP'::char(3)
  from public.organizations o
  join public.profiles p on p.id = auth.uid()
  left join public.subscription_customers c
    on c.organization_id = o.id and c.provider = 'paymob'
  where o.id = p_organization_id;
end;
$$;

drop function if exists public.apply_paymob_subscription_event(
  text, text, jsonb, uuid, text, text, public.billing_interval,
  timestamptz, timestamptz, timestamptz, timestamptz
);

create function public.apply_paymob_subscription_event(
  p_event_id text,
  p_event_type text,
  p_payload jsonb,
  p_organization_id uuid,
  p_subscription_id text,
  p_provider_status text,
  p_interval public.billing_interval,
  p_plan_key text default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null,
  p_last_payment_at timestamptz default null,
  p_payment_failed_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan uuid;
  v_price uuid;
  v_status public.billing_status;
  v_inserted integer;
  v_checkout_completed boolean;
begin
  if not app.is_service_context() then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if p_event_id is null or p_event_type is null or p_payload is null then
    raise exception 'INVALID_PAYMOB_EVENT' using errcode = '22023';
  end if;

  insert into public.billing_events (
    provider, provider_event_id, event_type, organization_id, payload,
    signature_verified
  )
  values ('paymob', p_event_id, p_event_type, p_organization_id, p_payload, true)
  on conflict (provider, provider_event_id) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    if exists (
      select 1 from public.billing_events e
      where e.provider = 'paymob'
        and e.provider_event_id = p_event_id
        and e.processed_at is not null
    ) then
      return false;
    end if;
    update public.billing_events
    set payload = p_payload, signature_verified = true, processing_error = null
    where provider = 'paymob' and provider_event_id = p_event_id;
  end if;

  if p_organization_id is null
     or not exists (select 1 from public.organizations o where o.id = p_organization_id) then
    update public.billing_events
    set processing_error = 'Missing or invalid organization metadata'
    where provider = 'paymob' and provider_event_id = p_event_id;
    return false;
  end if;

  begin
    if p_plan_key is not null then
      if p_plan_key not in ('solo', 'starter', 'business') then
        raise exception 'PLAN_NOT_AVAILABLE' using errcode = '22023';
      end if;
      select r.plan_id, r.price_id into strict v_plan, v_price
      from app.resolve_purchasable_plan(p_plan_key, p_interval, 'EGP') r;
    else
      select s.plan_id, s.price_id into v_plan, v_price
      from public.subscriptions s
      where s.organization_id = p_organization_id
        and s.provider = 'paymob'
        and s.provider_subscription_id = p_subscription_id;
      if v_plan is null then
        raise exception 'PLAN_METADATA_REQUIRED' using errcode = '22023';
      end if;
    end if;

    select s.checkout_completed_at is not null into v_checkout_completed
    from public.subscriptions s where s.organization_id = p_organization_id;

    v_status := case p_provider_status
      when 'active' then 'active'::public.billing_status
      when 'past_due' then case when v_checkout_completed
        then 'grace_period'::public.billing_status
        else 'suspended'::public.billing_status
      end
      when 'cancelled' then 'cancelled'::public.billing_status
      else 'suspended'::public.billing_status
    end;

    update public.subscriptions s
    set plan_id = v_plan,
        price_id = v_price,
        status = v_status,
        provider = 'paymob',
        provider_subscription_id = case
          when p_provider_status = 'active' then coalesce(p_subscription_id, s.provider_subscription_id)
          else s.provider_subscription_id
        end,
        provider_status = p_provider_status,
        billing_interval = coalesce(p_interval, s.billing_interval),
        current_period_start = coalesce(p_period_start, s.current_period_start),
        current_period_end = coalesce(p_period_end, s.current_period_end),
        grace_period_ends_at = case
          when p_provider_status = 'past_due' and v_checkout_completed then now() + interval '3 days'
          else null
        end,
        cancelled_at = case when p_provider_status = 'cancelled' then now() else null end,
        checkout_completed_at = case
          when p_provider_status = 'active' and p_subscription_id is not null
            then coalesce(s.checkout_completed_at, now())
          else s.checkout_completed_at
        end,
        last_payment_at = coalesce(p_last_payment_at, s.last_payment_at),
        payment_failed_at = case
          when p_last_payment_at is not null then null
          else coalesce(p_payment_failed_at, s.payment_failed_at)
        end
    where s.organization_id = p_organization_id;

    update public.billing_events
    set processed_at = now(), processing_error = null
    where provider = 'paymob' and provider_event_id = p_event_id;
    return true;
  exception when others then
    update public.billing_events
    set processing_error = sqlerrm
    where provider = 'paymob' and provider_event_id = p_event_id;
    return false;
  end;
end;
$$;

revoke all on function public.billing_checkout_context(uuid, text, public.billing_interval)
  from public, anon;
grant execute on function public.billing_checkout_context(uuid, text, public.billing_interval)
  to authenticated, service_role;

revoke all on function public.apply_paymob_subscription_event(
  text, text, jsonb, uuid, text, text, public.billing_interval, text,
  timestamptz, timestamptz, timestamptz, timestamptz
) from public, anon, authenticated;
grant execute on function public.apply_paymob_subscription_event(
  text, text, jsonb, uuid, text, text, public.billing_interval, text,
  timestamptz, timestamptz, timestamptz, timestamptz
) to service_role;
