-- Owner signup is durable before the email OTP is confirmed.
begin;

create extension if not exists pgtap with schema extensions;
select plan(20);

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
      "tax_identifier":"TAX-PERSIST-09",
      "billing_interval":"yearly"
    }
  }',
  now(), now(), '', '', '', '', '', '', '', ''
);

select is(
  (select email_confirmed_at from auth.users where id = 'd0000000-0000-4000-8000-000000000009'),
  null::timestamptz,
  'email remains unconfirmed'
);
select is((select full_name from public.profiles where id = 'd0000000-0000-4000-8000-000000000009'), 'Persistent Owner', 'full name is saved before OTP');
select is((select phone from public.profiles where id = 'd0000000-0000-4000-8000-000000000009'), '+201234567890', 'phone is saved before OTP');
select is((select job_title from public.profiles where id = 'd0000000-0000-4000-8000-000000000009'), 'Founder', 'job title is saved before OTP');
select ok((select onboarding_completed_at is not null from public.profiles where id = 'd0000000-0000-4000-8000-000000000009'), 'registration details are marked complete before OTP');
select is((select count(*) from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000009'), 1::bigint, 'organization is saved before OTP');
select is((select name from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000009'), 'Persistent Books', 'organization name is saved');
select is((select legal_name from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000009'), 'Persistent Books LLC', 'legal name is saved');
select is((select business_type::text from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000009'), 'limited_liability', 'business type is saved');
select is((select country_code::text from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000009'), 'EG', 'country is saved');
select is((select timezone from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000009'), 'Africa/Cairo', 'timezone is saved');
select is((select base_currency::text from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000009'), 'EGP', 'currency is saved');
select is((select fiscal_year_start_month from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000009'), 4::smallint, 'fiscal year start is saved');
select is((select tax_identifier from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000009'), 'TAX-PERSIST-09', 'tax identifier is saved');
select is((select count(*) from public.organization_members where user_id = 'd0000000-0000-4000-8000-000000000009' and role = 'owner'), 1::bigint, 'owner membership is saved before OTP');
select is((select s.billing_interval::text from public.subscriptions s join public.organizations o on o.id = s.organization_id where o.created_by = 'd0000000-0000-4000-8000-000000000009'), 'yearly', 'selected plan interval is saved before OTP');

-- Simulate an account created while the application was already sending the
-- saved metadata but before the provisioning trigger reached the hosted DB.
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
  'authenticated', 'authenticated', 'resume-after-otp@ledgersuit.test',
  extensions.crypt('pw', extensions.gen_salt('bf')),
  '{"provider":"email"}', '{}',
  now(), now(), '', '', '', '', '', '', '', ''
);

update auth.users
set raw_user_meta_data = '{
    "full_name":"Recovered Owner",
    "phone":"+201234567891",
    "job_title":"Director",
    "pending_onboarding":{
      "organization_name":"Recovered Books",
      "legal_name":"Recovered Books LLC",
      "business_type":"corporation",
      "country_code":"eg",
      "timezone":"Africa/Cairo",
      "base_currency":"egp",
      "fiscal_year_start_month":7,
      "tax_identifier":"",
      "billing_interval":"monthly"
    }
  }'
where id = 'd0000000-0000-4000-8000-000000000010';

select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000010","role":"authenticated"}',
  true
);

select ok(public.resume_saved_signup() is not null, 'a pre-deployment signup is recovered from saved metadata');
select is((select count(*) from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000010'), 1::bigint, 'recovery creates exactly one organization');
select is((select s.billing_interval::text from public.subscriptions s join public.organizations o on o.id = s.organization_id where o.created_by = 'd0000000-0000-4000-8000-000000000010'), 'monthly', 'recovery preserves the selected plan interval');
select is(public.resume_saved_signup(), (select id from public.organizations where created_by = 'd0000000-0000-4000-8000-000000000010'), 'recovery is idempotent');

select * from finish();
rollback;
