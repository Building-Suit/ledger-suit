-- Ledger Suit — Phase 4: one paid Stripe subscription
--
-- Checkout owns the start of the 14-day trial. Creating an organization alone
-- never starts access, and a lapsed subscription leaves its books readable but
-- blocks every financial or administrative mutation at the authorization core.

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------------------
-- One product, with Stripe price identifiers kept in server-side secrets.
-- ---------------------------------------------------------------------------
update public.subscription_plans
set is_public = false, is_active = false
where key in ('free', 'starter', 'business');

insert into public.subscription_plans (
  key, name, description, is_public, is_active, sort_order
)
values (
  'ledger_suit',
  'Ledger Suit',
  'Complete multi-tenant financial management with a 14-day trial.',
  true,
  true,
  0
)
on conflict (key) do update
set name = excluded.name,
    description = excluded.description,
    is_public = true,
    is_active = true,
    sort_order = 0;

insert into public.subscription_entitlements (
  plan_id, feature_key, is_enabled, limit_value
)
select p.id, e.feature_key, true, null
from public.subscription_plans p
cross join (
  values
    ('max_members'),
    ('max_monthly_transactions'),
    ('max_storage_bytes'),
    ('max_recurring_rules'),
    ('multi_currency'),
    ('advanced_reports'),
    ('imports'),
    ('exports'),
    ('audit_log_retention_days'),
    ('api_access')
) as e(feature_key)
where p.key = 'ledger_suit'
on conflict (plan_id, feature_key) do update
set is_enabled = true, limit_value = null;

alter table public.subscriptions
  add column billing_interval public.billing_interval,
  add column provider_status text,
  add column checkout_completed_at timestamptz,
  add column last_payment_at timestamptz,
  add column payment_failed_at timestamptz;

alter table public.subscriptions
  add constraint subscriptions_provider_status_length
  check (provider_status is null or char_length(provider_status) between 1 and 40),
  add constraint subscriptions_checkout_requires_provider
  check (
    checkout_completed_at is null
    or (provider = 'stripe' and provider_subscription_id is not null)
  );

create index subscriptions_access_state_idx
  on public.subscriptions (status, trial_ends_at, grace_period_ends_at);

-- Existing organizations that have no Stripe subscription have not passed the
-- new checkout. Preserve every historical provider identifier and billing date
-- in case an installation already populated them before this migration.
update public.subscriptions s
set plan_id = p.id,
    status = 'suspended'
from public.subscription_plans p
where p.key = 'ledger_suit'
  and (s.provider is distinct from 'stripe' or s.provider_subscription_id is null);

-- A pre-existing Stripe subscription is treated as previously checked out;
-- infer only fields introduced by this migration and leave all existing state
-- untouched. Future webhooks move it onto the single Ledger Suit plan.
update public.subscriptions s
set checkout_completed_at = coalesce(
      s.checkout_completed_at, s.trial_started_at, s.current_period_start, s.created_at
    ),
    billing_interval = coalesce(
      s.billing_interval,
      (select pp.interval from public.subscription_plan_prices pp where pp.id = s.price_id)
    )
where s.provider = 'stripe' and s.provider_subscription_id is not null;

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

  insert into public.subscriptions (organization_id, plan_id, status)
  values (new.id, v_plan, 'suspended')
  on conflict (organization_id) do nothing;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Database-authoritative access state and central write gate.
-- ---------------------------------------------------------------------------
create or replace function app.subscription_access_state(p_organization_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case
      when s.provider <> 'stripe'
        or s.provider_subscription_id is null
        or s.checkout_completed_at is null
        then 'checkout_required'
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
      else 'read_only'
    end
    from public.subscriptions s
    where s.organization_id = p_organization_id
  ), 'checkout_required');
$$;

create or replace function app.subscription_writes_allowed(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.subscription_access_state(p_organization_id)
    in ('trialing', 'active', 'grace_period');
$$;

create or replace function public.subscription_access_state(p_organization_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app.is_org_member(p_organization_id) then
    raise exception 'TENANT_ACCESS_DENIED: not a member of this organization'
      using errcode = '42501';
  end if;
  return app.subscription_access_state(p_organization_id);
end;
$$;

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

create or replace function app.has_capability(
  p_organization_id uuid,
  p_capability text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.is_service_context()
      or app.capability_available(p_organization_id, p_capability);
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
      where c like '%.read'
         or c = 'billing.manage'
         or app.subscription_writes_allowed(p_organization_id)
    ), '{}'::text[])
  end;
$$;

create or replace function public.can_use_feature(
  p_organization_id uuid,
  p_feature_key text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.is_org_member(p_organization_id)
    and app.subscription_writes_allowed(p_organization_id)
    and coalesce((
      select e.is_enabled and coalesce(e.limit_value, 1) <> 0
      from public.subscriptions s
      join public.subscription_entitlements e on e.plan_id = s.plan_id
      where s.organization_id = p_organization_id
        and e.feature_key = p_feature_key
    ), false);
$$;

create or replace function public.get_limit(
  p_organization_id uuid,
  p_limit_key text
)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not app.is_org_member(p_organization_id)
      or not app.subscription_writes_allowed(p_organization_id)
      then 0::bigint
    else (
      select e.limit_value
      from public.subscriptions s
      join public.subscription_entitlements e on e.plan_id = s.plan_id
      where s.organization_id = p_organization_id
        and e.feature_key = p_limit_key
    )
  end;
$$;

-- Checkout and the customer portal use this single authorization boundary.
create or replace function public.billing_checkout_context(
  p_organization_id uuid,
  p_interval public.billing_interval
)
returns table (
  organization_id uuid,
  organization_name text,
  billing_email text,
  provider_customer_id text,
  access_state text,
  billing_interval public.billing_interval
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_capability(p_organization_id, 'billing.manage');

  return query
  select o.id,
         o.name,
         p.email::text,
         c.provider_customer_id,
         app.subscription_access_state(o.id),
         p_interval
  from public.organizations o
  join public.profiles p on p.id = auth.uid()
  left join public.subscription_customers c
    on c.organization_id = o.id and c.provider = 'stripe'
  where o.id = p_organization_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Idempotent, service-only Stripe webhook persistence.
-- ---------------------------------------------------------------------------
create or replace function public.apply_stripe_subscription_event(
  p_event_id text,
  p_event_type text,
  p_payload jsonb,
  p_organization_id uuid,
  p_customer_id text,
  p_subscription_id text,
  p_provider_status text,
  p_interval public.billing_interval,
  p_trial_start timestamptz default null,
  p_trial_end timestamptz default null,
  p_period_start timestamptz default null,
  p_period_end timestamptz default null,
  p_cancel_at_period_end boolean default false,
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
  v_status public.billing_status;
  v_inserted integer;
begin
  if not app.is_service_context() then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if p_event_id is null or p_event_type is null or p_payload is null then
    raise exception 'INVALID_STRIPE_EVENT' using errcode = '22023';
  end if;

  insert into public.billing_events (
    provider, provider_event_id, event_type, organization_id, payload,
    signature_verified
  )
  values ('stripe', p_event_id, p_event_type, p_organization_id, p_payload, true)
  on conflict (provider, provider_event_id) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    -- A completed event is a harmless replay. An event with a recorded error
    -- is deliberately retried when Stripe delivers it again.
    if exists (
      select 1 from public.billing_events e
      where e.provider = 'stripe'
        and e.provider_event_id = p_event_id
        and e.processed_at is not null
    ) then
      return false;
    end if;
    update public.billing_events
    set payload = p_payload, signature_verified = true, processing_error = null
    where provider = 'stripe' and provider_event_id = p_event_id;
  end if;

  select id into v_plan from public.subscription_plans where key = 'ledger_suit';
  if v_plan is null or p_organization_id is null
     or not exists (select 1 from public.organizations o where o.id = p_organization_id) then
    update public.billing_events
    set processing_error = 'Missing or invalid organization metadata'
    where provider = 'stripe' and provider_event_id = p_event_id;
    return false;
  end if;

  begin
    v_status := case p_provider_status
      when 'trialing' then 'trialing'::public.billing_status
      when 'active' then 'active'::public.billing_status
      when 'past_due' then 'grace_period'::public.billing_status
      when 'canceled' then 'cancelled'::public.billing_status
      else 'suspended'::public.billing_status
    end;

    if p_customer_id is not null then
      insert into public.subscription_customers (
        organization_id, provider, provider_customer_id
      ) values (p_organization_id, 'stripe', p_customer_id)
      on conflict (organization_id, provider) do update
      set provider_customer_id = excluded.provider_customer_id;
    end if;

    update public.subscriptions s
    set plan_id = v_plan,
        price_id = null,
        status = v_status,
        provider = 'stripe',
        provider_subscription_id = coalesce(p_subscription_id, s.provider_subscription_id),
        provider_status = p_provider_status,
        billing_interval = coalesce(p_interval, s.billing_interval),
        trial_started_at = coalesce(p_trial_start, s.trial_started_at),
        trial_ends_at = coalesce(p_trial_end, s.trial_ends_at),
        current_period_start = coalesce(p_period_start, s.current_period_start),
        current_period_end = coalesce(p_period_end, s.current_period_end),
        grace_period_ends_at = case
          when p_provider_status = 'past_due' then now() + interval '3 days'
          else null
        end,
        cancel_at_period_end = coalesce(p_cancel_at_period_end, false),
        cancelled_at = case when p_provider_status = 'canceled' then now() else null end,
        checkout_completed_at = case
          when p_subscription_id is not null then coalesce(s.checkout_completed_at, now())
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
    where provider = 'stripe' and provider_event_id = p_event_id;
    return true;
  exception when others then
    update public.billing_events
    set processing_error = sqlerrm
    where provider = 'stripe' and provider_event_id = p_event_id;
    return false;
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Resend-backed notification email queue.
-- ---------------------------------------------------------------------------
alter table public.notifications
  -- Existing in-app notifications must not turn into a historical email blast
  -- when this migration ships. Only notifications created afterward queue.
  add column email_status text not null default 'sent',
  add column email_attempt_count integer not null default 0,
  add column email_last_attempt_at timestamptz,
  add column email_provider_id text,
  add column email_sent_at timestamptz,
  add column email_error text;

update public.notifications
set email_sent_at = created_at
where email_status = 'sent';

alter table public.notifications alter column email_status set default 'pending';

alter table public.notifications
  add constraint notifications_email_status_allowed
    check (email_status in ('pending', 'sending', 'sent', 'failed')),
  add constraint notifications_email_attempts_nonnegative
    check (email_attempt_count >= 0);

create index notifications_email_queue_idx
  on public.notifications (created_at)
  where email_status in ('pending', 'failed') and email_attempt_count < 5;

create or replace function public.claim_notification_emails(p_limit integer default 25)
returns table (
  notification_id uuid,
  recipient_email text,
  recipient_name text,
  organization_name text,
  subject text,
  body text,
  action_url text,
  notification_type text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app.is_service_context() then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;

  return query
  with claimed as (
    select n.id
    from public.notifications n
    where n.user_id is not null
      and n.email_status in ('pending', 'failed')
      and n.email_attempt_count < 5
      and (n.email_last_attempt_at is null
        or n.email_last_attempt_at < now() - interval '15 minutes')
    order by n.created_at
    for update skip locked
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
  ), updated as (
    update public.notifications n
    set email_status = 'sending',
        email_attempt_count = n.email_attempt_count + 1,
        email_last_attempt_at = now(),
        email_error = null
    from claimed c
    where n.id = c.id
    returning n.*
  )
  select u.id,
         p.email::text,
         coalesce(p.full_name, p.email::text),
         o.name,
         u.title,
         coalesce(u.body, ''),
         u.action_url,
         u.type
  from updated u
  join public.profiles p on p.id = u.user_id
  join public.organizations o on o.id = u.organization_id;
end;
$$;

create or replace function public.complete_notification_email(
  p_notification_id uuid,
  p_provider_id text default null,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app.is_service_context() then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  update public.notifications
  set email_status = case when p_error is null then 'sent' else 'failed' end,
      email_provider_id = case when p_error is null then p_provider_id else email_provider_id end,
      email_sent_at = case when p_error is null then now() else email_sent_at end,
      email_error = left(p_error, 2000)
  where id = p_notification_id and email_status = 'sending';
end;
$$;

-- ---------------------------------------------------------------------------
-- Supabase Cron: tenant-safe, idempotent financial background operations.
-- ---------------------------------------------------------------------------
create or replace function app.run_scheduled_operations()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org record;
  v_processed integer := 0;
  v_failed integer := 0;
begin
  perform set_config('app.bypass_authz', 'on', true);
  for v_org in
    select o.id
    from public.organizations o
    where o.status = 'active'
      and app.subscription_writes_allowed(o.id)
  loop
    begin
      perform * from public.run_recurring_schedule(v_org.id, null);
      perform public.notify_due_commitments(v_org.id);
      perform * from public.run_due_commitment_conversions(v_org.id, null);
      v_processed := v_processed + 1;
    exception when others then
      v_failed := v_failed + 1;
    end;
  end loop;
  return jsonb_build_object('organizations_processed', v_processed,
                            'organizations_failed', v_failed);
end;
$$;

do $$
declare v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname = 'ledger-suit-operations';
  if v_job_id is not null then perform cron.unschedule(v_job_id); end if;
  perform cron.schedule(
    'ledger-suit-operations',
    '*/15 * * * *',
    'select app.run_scheduled_operations();'
  );
end;
$$;

-- The delivery job becomes active as soon as deployment configuration stores
-- `ledger_suit_project_url` and `ledger_suit_service_role_key` in Supabase
-- Vault. Keeping values in Vault avoids ever committing a privileged key.
do $$
declare v_job_id bigint;
begin
  select jobid into v_job_id
  from cron.job where jobname = 'ledger-suit-notification-email';
  if v_job_id is not null then perform cron.unschedule(v_job_id); end if;
  perform cron.schedule(
    'ledger-suit-notification-email',
    '*/5 * * * *',
    $job$
      select net.http_post(
        url := secrets.project_url || '/functions/v1/scheduled-notifications',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || secrets.service_role_key
        ),
        body := '{}'::jsonb
      )
      from (
        select
          max(decrypted_secret) filter (where name = 'ledger_suit_project_url') as project_url,
          max(decrypted_secret) filter (where name = 'ledger_suit_service_role_key') as service_role_key
        from vault.decrypted_secrets
      ) secrets
      where secrets.project_url is not null and secrets.service_role_key is not null;
    $job$
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Explicit exposure: public objects are not auto-granted by modern Supabase.
-- ---------------------------------------------------------------------------
revoke all on function app.subscription_access_state(uuid) from public, anon, authenticated;
revoke all on function app.subscription_writes_allowed(uuid) from public, anon, authenticated;
revoke all on function app.capability_available(uuid, text) from public, anon, authenticated;
revoke all on function app.run_scheduled_operations() from public, anon, authenticated, service_role;

revoke all on function public.subscription_access_state(uuid) from public, anon;
grant execute on function public.subscription_access_state(uuid) to authenticated, service_role;
revoke all on function public.billing_checkout_context(uuid, public.billing_interval) from public, anon;
grant execute on function public.billing_checkout_context(uuid, public.billing_interval)
  to authenticated, service_role;
revoke all on function public.apply_stripe_subscription_event(
  text, text, jsonb, uuid, text, text, text, public.billing_interval,
  timestamptz, timestamptz, timestamptz, timestamptz, boolean, timestamptz, timestamptz
) from public, anon, authenticated;
grant execute on function public.apply_stripe_subscription_event(
  text, text, jsonb, uuid, text, text, text, public.billing_interval,
  timestamptz, timestamptz, timestamptz, timestamptz, boolean, timestamptz, timestamptz
) to service_role;
revoke all on function public.claim_notification_emails(integer)
  from public, anon, authenticated;
grant execute on function public.claim_notification_emails(integer) to service_role;
revoke all on function public.complete_notification_email(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.complete_notification_email(uuid, text, text) to service_role;

grant execute on function app.subscription_access_state(uuid) to service_role;
grant execute on function app.subscription_writes_allowed(uuid) to service_role;
grant execute on function app.capability_available(uuid, text) to authenticated, service_role;

revoke insert, update, delete on public.subscription_plans,
  public.subscription_plan_prices, public.subscription_entitlements,
  public.subscription_customers, public.subscriptions, public.billing_events
  from anon, authenticated;
