-- Ledger Suit — acquisition and owner onboarding
--
-- Account creation now collects the owner and organization data required to
-- enter Stripe Checkout in one journey. The function is atomic: a partially
-- configured tenant cannot be created if any validation or seed step fails.

create type public.organization_business_type as enum (
  'sole_proprietorship',
  'partnership',
  'limited_liability',
  'corporation',
  'nonprofit',
  'other'
);

alter table public.profiles
  add column phone text,
  add column job_title text,
  add column onboarding_completed_at timestamptz;

alter table public.profiles
  add constraint profiles_phone_length check (
    phone is null or char_length(phone) between 7 and 30
  ),
  add constraint profiles_job_title_length check (
    job_title is null or char_length(job_title) between 2 and 100
  );

alter table public.organizations
  add column business_type public.organization_business_type not null default 'other';

create or replace function public.complete_account_onboarding(
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
  p_tax_identifier text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_organization_id uuid;
begin
  if v_user is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_full_name, ''))) < 2 then
    raise exception 'INVALID_INPUT: full name is required' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_phone, ''))) < 7 then
    raise exception 'INVALID_INPUT: phone is required' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_job_title, ''))) < 2 then
    raise exception 'INVALID_INPUT: job title is required' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.organization_members m
    where m.user_id = v_user and m.status = 'active'
  ) then
    raise exception 'ONBOARDING_ALREADY_COMPLETED' using errcode = '23505';
  end if;

  update public.profiles
  set full_name = trim(p_full_name),
      phone = trim(p_phone),
      job_title = trim(p_job_title),
      timezone = p_timezone
  where id = v_user;

  v_organization_id := public.create_organization(
    p_name => p_organization_name,
    p_base_currency => p_base_currency,
    p_country_code => p_country_code,
    p_timezone => p_timezone,
    p_legal_name => nullif(trim(coalesce(p_legal_name, '')), ''),
    p_fiscal_year_start_month => p_fiscal_year_start_month
  );

  update public.organizations
  set business_type = p_business_type,
      tax_identifier = nullif(trim(coalesce(p_tax_identifier, '')), '')
  where id = v_organization_id and created_by = v_user;

  update public.profiles
  set onboarding_completed_at = now()
  where id = v_user;

  perform app.write_audit(
    v_organization_id,
    'onboarding.completed',
    'organization',
    v_organization_id,
    null,
    jsonb_build_object('business_type', p_business_type, 'country_code', p_country_code)
  );

  return v_organization_id;
end;
$$;

comment on function public.complete_account_onboarding(
  text, text, text, text, text, public.organization_business_type,
  char, text, char, smallint, text
) is 'Completes the owner profile and provisions a ready-to-use organization atomically.';

revoke all on function public.complete_account_onboarding(
  text, text, text, text, text, public.organization_business_type,
  char, text, char, smallint, text
) from public, anon;
grant execute on function public.complete_account_onboarding(
  text, text, text, text, text, public.organization_business_type,
  char, text, char, smallint, text
) to authenticated, service_role;
