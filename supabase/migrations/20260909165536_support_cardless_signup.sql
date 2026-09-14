-- The earlier durable-signup trigger provisioned a paid-plan choice inside
-- the auth.users insert. Cardless trials have no plan choice, so that trigger
-- rejected new users and GoTrue surfaced only "Database error saving new
-- user". Keep auth signup narrowly responsible for the profile; resume the
-- saved organization metadata after OTP confirmation.

create or replace function app.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name, avatar_url)
  values (
    new.id,
    coalesce(new.email, new.id::text || '@placeholder.invalid'),
    nullif(btrim(coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      ''
    )), ''),
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'avatar_url', '')), '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function app.handle_new_auth_user() is
  'Creates the public profile only. Owner workspace provisioning resumes after email confirmation.';

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

  return public.complete_account_onboarding(
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
    nullif(btrim(coalesce(v_onboarding ->> 'tax_identifier', '')), '')
  );
end;
$$;

comment on function public.resume_saved_signup() is
  'Idempotently provisions the authenticated user and starts the cardless trial from saved signup metadata.';

revoke all on function public.resume_saved_signup() from public, anon;
grant execute on function public.resume_saved_signup() to authenticated, service_role;
