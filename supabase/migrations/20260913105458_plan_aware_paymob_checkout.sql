-- Resolve checkout amounts from the launch catalog and bind webhook updates to
-- the selected plan. Provider plan identifiers remain Edge Function secrets.

drop function if exists public.billing_checkout_context(uuid, public.billing_interval);
drop function if exists public.billing_checkout_context(uuid, text, public.billing_interval);

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
drop function if exists public.apply_paymob_subscription_event(
  text, text, jsonb, uuid, text, text, public.billing_interval, text,
  timestamptz, timestamptz, timestamptz, timestamptz
);
drop function if exists public.apply_paymob_subscription_event(
  text, text, jsonb, uuid, text, text, public.billing_interval, text,
  timestamptz, timestamptz, timestamptz, timestamptz, uuid, bigint
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
  p_payment_failed_at timestamptz default null,
  p_price_id uuid default null,
  p_amount_minor bigint default null
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
  v_mutated integer;
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
    if p_plan_key is not null or p_price_id is not null or p_amount_minor is not null then
      if p_plan_key is null or p_price_id is null or p_amount_minor is null then
        raise exception 'PLAN_PRICE_SNAPSHOT_MISMATCH' using errcode = '22023';
      end if;
      if p_plan_key not in ('solo', 'starter', 'business') then
        raise exception 'PLAN_NOT_AVAILABLE' using errcode = '22023';
      end if;

      -- Fulfil the exact signed checkout snapshot. A price may have been made
      -- inactive after checkout began, so intentionally do not re-check the
      -- current public/purchasable/active catalog flags here.
      select plan.id, price.id into v_plan, v_price
      from public.subscription_plans plan
      join public.subscription_plan_prices price on price.plan_id = plan.id
      where plan.key = p_plan_key
        and price.id = p_price_id
        and price.interval = p_interval
        and price.currency_code = 'EGP'
        and price.amount_minor = p_amount_minor;
      if v_plan is null then
        raise exception 'PLAN_PRICE_SNAPSHOT_MISMATCH' using errcode = '22023';
      end if;

      if p_provider_status = 'active' then
        if nullif(p_subscription_id, '') is null then
          raise exception 'PROVIDER_SUBSCRIPTION_REQUIRED' using errcode = '22023';
        end if;

        insert into public.subscriptions (
          organization_id, plan_id, price_id, status, provider,
          provider_subscription_id, provider_status, billing_interval,
          current_period_start, current_period_end, checkout_completed_at,
          last_payment_at, payment_failed_at, grace_period_ends_at, cancelled_at
        ) values (
          p_organization_id, v_plan, v_price, 'active', 'paymob',
          p_subscription_id, p_provider_status, p_interval,
          p_period_start, p_period_end, now(), p_last_payment_at, null, null, null
        )
        on conflict (organization_id) do update
        set plan_id = excluded.plan_id,
            price_id = excluded.price_id,
            status = excluded.status,
            provider = excluded.provider,
            provider_subscription_id = excluded.provider_subscription_id,
            provider_status = excluded.provider_status,
            billing_interval = excluded.billing_interval,
            current_period_start = coalesce(excluded.current_period_start, public.subscriptions.current_period_start),
            current_period_end = coalesce(excluded.current_period_end, public.subscriptions.current_period_end),
            grace_period_ends_at = null,
            cancelled_at = null,
            checkout_completed_at = coalesce(public.subscriptions.checkout_completed_at, now()),
            last_payment_at = coalesce(excluded.last_payment_at, public.subscriptions.last_payment_at),
            payment_failed_at = null;
        get diagnostics v_mutated = row_count;
        if v_mutated <> 1 then
          raise exception 'SUBSCRIPTION_MUTATION_FAILED';
        end if;
      else
        -- A declined initial payment is a recorded attempt, not a plan
        -- transition. In particular, an unexpired trial remains trialing.
        update public.subscriptions s
        set provider_status = p_provider_status,
            payment_failed_at = coalesce(p_payment_failed_at, now())
        where s.organization_id = p_organization_id;
      end if;
    else
      select s.plan_id, s.price_id into v_plan, v_price
      from public.subscriptions s
      where s.organization_id = p_organization_id
        and s.provider = 'paymob'
        and s.provider_subscription_id = p_subscription_id;
      if v_plan is null then
        raise exception 'PLAN_METADATA_REQUIRED' using errcode = '22023';
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
      set status = v_status,
          provider_status = p_provider_status,
          current_period_start = coalesce(p_period_start, s.current_period_start),
          current_period_end = coalesce(p_period_end, s.current_period_end),
          grace_period_ends_at = case
            when p_provider_status = 'past_due' and v_checkout_completed then now() + interval '3 days'
            else null
          end,
          cancelled_at = case when p_provider_status = 'cancelled' then now() else null end,
          last_payment_at = coalesce(p_last_payment_at, s.last_payment_at),
          payment_failed_at = case
            when p_last_payment_at is not null then null
            else coalesce(p_payment_failed_at, s.payment_failed_at)
          end
      where s.organization_id = p_organization_id;
      get diagnostics v_mutated = row_count;
      if v_mutated <> 1 then
        raise exception 'SUBSCRIPTION_MUTATION_FAILED';
      end if;
    end if;

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
  timestamptz, timestamptz, timestamptz, timestamptz, uuid, bigint
) from public, anon, authenticated;
grant execute on function public.apply_paymob_subscription_event(
  text, text, jsonb, uuid, text, text, public.billing_interval, text,
  timestamptz, timestamptz, timestamptz, timestamptz, uuid, bigint
) to service_role;
