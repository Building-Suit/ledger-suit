-- Signup keeps the pending workspace durable while delaying tenant creation
-- until the owner has confirmed their email.
begin;

create extension if not exists pgtap with schema extensions;
select plan(25);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, recovery_token,
  email_change_token_new, email_change_token_current, email_change,
  phone_change, phone_change_token, reauthentication_token
)
values (
  'd0000000-0000-4000-8000-000000000009',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'persist-before-otp@ledgersuit.test',
  extensions.crypt('pw', extensions.gen_salt('bf')),
  '{"provider":"email"}',
  '{
    "full_name":"Persistent Owner",
    "phone":"+201234567890",
    "job_title":"Founder",
    "pending_onboarding":{
      "organization_name":"Persistent Books",
      "legal_name":"Persistent Books LLC",
      "business_type":"limited_liability",
      "country_code":"EG",
      "timezone":"Africa/Cairo",
      "base_currency":"EGP",
      "fiscal_year_start_month":4,
      "tax_identifier":"TAX-PERSIST-09"
    }
  }',
  now(), now(), '', '', '', '', '', '', '', ''
);

select is(
  (select email_confirmed_at from auth.users where id = 'd0000000-0000-4000-8000-000000000009'),
  null::timestamptz,
  'email remains unconfirmed'
);
select is((select full_name from public.profiles where id = 'd0000000-0000-4000-8000-000000000009'), 'Persistent Owner', 'the basic profile is created without failing auth signup');
select is((select phone from public.profiles where id = 'd0000000-0000-4000-8000-000000000009'), null::text, 'owner details wait for email confirmation');
select is((select count(*) from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000009'), 0::bigint, 'no tenant is provisioned before OTP confirmation');

select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000009","role":"authenticated"}',
  true
);

select ok(public.resume_saved_signup() is not null, 'saved signup resumes after authentication');
select is((select phone from public.profiles where id = auth.uid()), '+201234567890', 'phone is restored from signup metadata');
select is((select job_title from public.profiles where id = auth.uid()), 'Founder', 'job title is restored from signup metadata');
select ok((select onboarding_completed_at is not null from public.profiles where id = auth.uid()), 'profile is marked onboarded');
select is((select count(*) from public.organizations where created_by = auth.uid()), 1::bigint, 'one organization is provisioned');
select is((select name from public.organizations where created_by = auth.uid()), 'Persistent Books', 'organization name is restored');
select is((select legal_name from public.organizations where created_by = auth.uid()), 'Persistent Books LLC', 'legal name is restored');
select is((select business_type::text from public.organizations where created_by = auth.uid()), 'limited_liability', 'business type is restored');
select is((select country_code::text from public.organizations where created_by = auth.uid()), 'EG', 'country is restored');
select is((select timezone from public.organizations where created_by = auth.uid()), 'Africa/Cairo', 'timezone is restored');
select is((select base_currency::text from public.organizations where created_by = auth.uid()), 'EGP', 'currency is restored');
select is((select fiscal_year_start_month from public.organizations where created_by = auth.uid()), 4::smallint, 'fiscal year start is restored');
select is((select tax_identifier from public.organizations where created_by = auth.uid()), 'TAX-PERSIST-09', 'tax identifier is restored');
select is((select count(*) from public.organization_members where user_id = auth.uid() and role = 'owner'), 1::bigint, 'owner membership is provisioned');
select is(
  (select count(*) from public.subscriptions s
   join public.organizations o on o.id = s.organization_id
   where o.created_by = auth.uid()
     and s.status = 'trialing'
     and s.trial_started_at is not null
     and s.trial_ends_at between now() + interval '13 days 23 hours' and now() + interval '14 days 1 minute'),
  1::bigint,
  'a 14-day trial starts after confirmation'
);
select is(
  (select s.billing_interval::text from public.subscriptions s
   join public.organizations o on o.id = s.organization_id
   where o.created_by = auth.uid()),
  null::text,
  'the trial starts without a paid billing interval'
);
select is(
  public.resume_saved_signup(),
  (select id from public.organizations where created_by = auth.uid()),
  'resuming signup is idempotent'
);

-- Accounts created by the briefly deployed checkout flow can still resume;
-- their obsolete billing interval is ignored rather than breaking signup.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, recovery_token,
  email_change_token_new, email_change_token_current, email_change,
  phone_change, phone_change_token, reauthentication_token
)
values (
  'd0000000-0000-4000-8000-000000000010',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'legacy-checkout@ledgersuit.test',
  extensions.crypt('pw', extensions.gen_salt('bf')),
  '{"provider":"email"}',
  '{
    "full_name":"Legacy Owner",
    "phone":"+201234567891",
    "job_title":"Director",
    "pending_onboarding":{
      "organization_name":"Legacy Books",
      "legal_name":"Legacy Books LLC",
      "business_type":"corporation",
      "country_code":"eg",
      "timezone":"Africa/Cairo",
      "base_currency":"egp",
      "fiscal_year_start_month":7,
      "tax_identifier":"",
      "billing_interval":"monthly"
    }
  }',
  now(), now(), '', '', '', '', '', '', '', ''
);

select is((select count(*) from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000010'), 0::bigint, 'legacy metadata also waits for confirmation');

select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000010","role":"authenticated"}',
  true
);

select ok(public.resume_saved_signup() is not null, 'legacy saved signup can resume');
select is(
  (select s.billing_interval::text from public.subscriptions s
   join public.organizations o on o.id = s.organization_id
   where o.created_by = auth.uid()),
  null::text,
  'legacy plan choice is ignored for the cardless trial'
);
select is(public.resume_saved_signup(), (select id from public.organizations where created_by = auth.uid()), 'legacy recovery is idempotent');

select * from finish();
rollback;
