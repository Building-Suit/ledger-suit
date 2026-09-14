-- Persist the complete owner signup before email confirmation.
--
-- Supabase creates auth.users before it issues the confirmation OTP. The
-- signup form sends its already-validated owner, organization, and billing
-- choice as user metadata. This trigger copies those values into the product
-- tables in the same transaction as the auth user, so closing the browser at
-- the OTP screen cannot discard the organization.

create or replace function app.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_onboarding jsonb := new.raw_user_meta_data -> 'pending_onboarding';
  v_full_name text := btrim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  v_phone text := btrim(coalesce(new.raw_user_meta_data ->> 'phone', ''));
  v_job_title text := btrim(coalesce(new.raw_user_meta_data ->> 'job_title', ''));
  v_organization_name text;
  v_legal_name text;
  v_business_type text;
  v_country_code text;
  v_timezone text;
  v_base_currency text;
  v_fiscal_year_text text;
  v_fiscal_year smallint;
  v_tax_identifier text;
  v_billing_interval text;
  v_organization_id uuid;
  v_slug_base text;
  v_slug text;
begin
  insert into public.profiles (id, email, full_name, avatar_url, phone, job_title)
  values (
    new.id,
    coalesce(new.email, new.id::text || '@placeholder.invalid'),
    nullif(v_full_name, ''),
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'avatar_url', '')), ''),
    nullif(v_phone, ''),
    nullif(v_job_title, '')
  )
  on conflict (id) do nothing;

  -- Invitations and accounts created outside the paid owner signup do not
  -- carry this object and keep their existing provisioning behavior.
  if v_onboarding is null or jsonb_typeof(v_onboarding) <> 'object' then
    return new;
  end if;

  v_organization_name := btrim(coalesce(v_onboarding ->> 'organization_name', ''));
  v_legal_name := btrim(coalesce(v_onboarding ->> 'legal_name', ''));
  v_business_type := btrim(coalesce(v_onboarding ->> 'business_type', ''));
  v_country_code := upper(btrim(coalesce(v_onboarding ->> 'country_code', '')));
  v_timezone := btrim(coalesce(v_onboarding ->> 'timezone', ''));
  v_base_currency := upper(btrim(coalesce(v_onboarding ->> 'base_currency', '')));
  v_fiscal_year_text := btrim(coalesce(v_onboarding ->> 'fiscal_year_start_month', ''));
  v_tax_identifier := nullif(btrim(coalesce(v_onboarding ->> 'tax_identifier', '')), '');
  v_billing_interval := btrim(coalesce(v_onboarding ->> 'billing_interval', ''));

  if char_length(v_full_name) not between 2 and 160
     or char_length(v_phone) not between 7 and 30
     or char_length(v_job_title) not between 2 and 100 then
    raise exception 'INVALID_SIGNUP_OWNER: complete owner details are required'
      using errcode = '22023';
  end if;
  if char_length(v_organization_name) not between 1 and 160
     or char_length(v_legal_name) < 1 then
    raise exception 'INVALID_SIGNUP_ORGANIZATION: complete organization details are required'
      using errcode = '22023';
  end if;
  if v_business_type not in (
    'sole_proprietorship', 'partnership', 'limited_liability',
    'corporation', 'nonprofit', 'other'
  ) then
    raise exception 'INVALID_SIGNUP_ORGANIZATION: unsupported business type'
      using errcode = '22023';
  end if;
  if v_country_code !~ '^[A-Z]{2}$' or v_timezone = '' then
    raise exception 'INVALID_SIGNUP_ORGANIZATION: invalid country or timezone'
      using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.currencies c
    where c.code = v_base_currency and c.is_active
  ) then
    raise exception 'INVALID_SIGNUP_ORGANIZATION: unsupported currency'
      using errcode = '22023';
  end if;
  if v_fiscal_year_text !~ '^([1-9]|1[0-2])$' then
    raise exception 'INVALID_SIGNUP_ORGANIZATION: invalid fiscal year start month'
      using errcode = '22023';
  end if;
  v_fiscal_year := v_fiscal_year_text::smallint;
  if v_billing_interval not in ('monthly', 'yearly') then
    raise exception 'INVALID_SIGNUP_PLAN: unsupported billing interval'
      using errcode = '22023';
  end if;

  v_slug_base := left(app.slugify(v_organization_name), 58);
  if char_length(v_slug_base) < 3 then
    v_slug_base := 'org';
  end if;
  v_slug := v_slug_base;
  if exists (select 1 from public.organizations o where o.slug = v_slug) then
    v_slug := left(v_slug_base, 29) || '-' || replace(new.id::text, '-', '');
  end if;

  insert into public.organizations (
    name, slug, legal_name, business_type, country_code, timezone,
    base_currency, fiscal_year_start_month, tax_identifier, created_by
  )
  values (
    v_organization_name, v_slug, v_legal_name,
    v_business_type::public.organization_business_type,
    v_country_code, v_timezone, v_base_currency, v_fiscal_year,
    v_tax_identifier, new.id
  )
  returning id into v_organization_id;

  insert into public.organization_settings (
    organization_id, default_transaction_currency
  ) values (v_organization_id, v_base_currency);

  insert into public.organization_members (
    organization_id, user_id, role, status
  ) values (v_organization_id, new.id, 'owner', 'active');

  update public.profiles
  set default_organization_id = v_organization_id,
      timezone = v_timezone,
      onboarding_completed_at = now()
  where id = new.id;

  -- organizations_start_subscription creates this row synchronously.
  update public.subscriptions
  set billing_interval = v_billing_interval::public.billing_interval
  where organization_id = v_organization_id;

  insert into public.audit_logs (
    organization_id, actor_id, actor_email, action, entity_type, entity_id,
    after_state, metadata
  ) values (
    v_organization_id, new.id, new.email, 'organization.created',
    'organization', v_organization_id,
    jsonb_build_object('name', v_organization_name, 'base_currency', v_base_currency),
    jsonb_build_object('source', 'owner_signup')
  );

  return new;
end;
$$;

comment on function app.handle_new_auth_user() is
  'Creates the public profile and, for owner signups, durably provisions the organization and selected billing interval before OTP confirmation.';
