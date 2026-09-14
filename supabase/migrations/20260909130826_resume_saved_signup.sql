-- Recover signups created before durable auth-trigger provisioning was
-- deployed. The authenticated user can only resume their own saved metadata.

create or replace function public.complete_account_onboarding_with_plan(
  p_full_name text,
  p_phone text,
  p_job_title text,
  p_organization_name text,
  p_legal_name text,
  p_business_type public.organization_business_type,
  p_country_code char(2),
  p_timezone text,
  p_base_currency char(3),
  p_fiscal_year_start_month smallint,
  p_tax_identifier text,
  p_billing_interval public.billing_interval
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;

  v_organization_id := public.complete_account_onboarding(
    p_full_name,
    p_phone,
    p_job_title,
    p_organization_name,
    p_legal_name,
    p_business_type,
    p_country_code,
    p_timezone,
    p_base_currency,
    p_fiscal_year_start_month,
    p_tax_identifier
  );

  update public.subscriptions
  set billing_interval = p_billing_interval
  where organization_id = v_organization_id;

  return v_organization_id;
end;
$$;

create or replace function public.resume_saved_signup()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_metadata jsonb;
  v_onboarding jsonb;
  v_existing_organization_id uuid;
begin
  if v_user_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;

  select m.organization_id
  into v_existing_organization_id
  from public.organization_members m
  where m.user_id = v_user_id and m.status = 'active'
  order by m.created_at
  limit 1;

  if v_existing_organization_id is not null then
    return v_existing_organization_id;
  end if;

  select u.raw_user_meta_data
  into v_metadata
  from auth.users u
  where u.id = v_user_id;

  v_onboarding := v_metadata -> 'pending_onboarding';
  if v_onboarding is null or jsonb_typeof(v_onboarding) <> 'object' then
    return null;
  end if;

  return public.complete_account_onboarding_with_plan(
    btrim(coalesce(v_metadata ->> 'full_name', '')),
    btrim(coalesce(v_metadata ->> 'phone', '')),
    btrim(coalesce(v_metadata ->> 'job_title', '')),
    btrim(coalesce(v_onboarding ->> 'organization_name', '')),
    btrim(coalesce(v_onboarding ->> 'legal_name', '')),
    (v_onboarding ->> 'business_type')::public.organization_business_type,
    upper(btrim(coalesce(v_onboarding ->> 'country_code', '')))::char(2),
    btrim(coalesce(v_onboarding ->> 'timezone', '')),
    upper(btrim(coalesce(v_onboarding ->> 'base_currency', '')))::char(3),
    (v_onboarding ->> 'fiscal_year_start_month')::smallint,
    nullif(btrim(coalesce(v_onboarding ->> 'tax_identifier', '')), ''),
    (v_onboarding ->> 'billing_interval')::public.billing_interval
  );
end;
$$;

comment on function public.resume_saved_signup() is
  'Idempotently provisions the authenticated user from owner-signup metadata saved before OTP verification.';

revoke all on function public.complete_account_onboarding_with_plan(
  text, text, text, text, text, public.organization_business_type,
  char, text, char, smallint, text, public.billing_interval
) from public, anon;
grant execute on function public.complete_account_onboarding_with_plan(
  text, text, text, text, text, public.organization_business_type,
  char, text, char, smallint, text, public.billing_interval
) to authenticated, service_role;

revoke all on function public.resume_saved_signup() from public, anon;
grant execute on function public.resume_saved_signup() to authenticated, service_role;
