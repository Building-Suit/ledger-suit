-- Owner onboarding provisions one complete, tenant-scoped workspace atomically.
begin;

create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at, confirmation_token, recovery_token,
                        email_change_token_new, email_change_token_current, email_change,
                        phone_change, phone_change_token, reauthentication_token)
values ('d0000000-0000-4000-8000-000000000001',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'onboarding@ledgersuit.test', extensions.crypt('pw', extensions.gen_salt('bf')),
        now(), '{"provider":"email"}', '{"full_name":"Onboarding Owner"}',
        now(), now(), '', '', '', '', '', '', '', '');

select set_config('request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

create temp table onboarding_ids (organization_id uuid);
grant all on onboarding_ids to authenticated;

insert into onboarding_ids
select public.complete_account_onboarding(
  'Onboarding Owner', '+201000000000', 'Founder',
  'Ready Books', 'Ready Books LLC', 'limited_liability',
  'EG'::char(2), 'Africa/Cairo', 'EGP'::char(3), 1::smallint, 'TAX-ONBOARD-01'
);

select is((select full_name from public.profiles where id = auth.uid()), 'Onboarding Owner', 'owner name is stored');
select is((select phone from public.profiles where id = auth.uid()), '+201000000000', 'owner phone is stored');
select is((select job_title from public.profiles where id = auth.uid()), 'Founder', 'owner job title is stored');
select ok((select onboarding_completed_at is not null from public.profiles where id = auth.uid()), 'profile is marked onboarded');
select is((select count(*) from public.organization_members where user_id = auth.uid() and role = 'owner'), 1::bigint, 'one owner membership is created');
select is((select business_type::text from public.organizations where id = (select organization_id from onboarding_ids)), 'limited_liability', 'business type is stored');
select is((select tax_identifier from public.organizations where id = (select organization_id from onboarding_ids)), 'TAX-ONBOARD-01', 'tax identifier is stored');
select ok((select count(*) > 10 from public.accounts where organization_id = (select organization_id from onboarding_ids)), 'starter chart of accounts is ready');
select is((select count(*) from public.subscriptions where organization_id = (select organization_id from onboarding_ids)), 1::bigint, 'one checkout-required subscription is provisioned');

select throws_ok(
  $$select public.complete_account_onboarding('Again', '+201000000000', 'Founder', 'Again', 'Again LLC', 'other', 'EG'::char(2), 'Africa/Cairo', 'EGP'::char(3), 1::smallint, null)$$,
  '23505', null,
  'onboarding cannot be replayed for an active member'
);

select * from finish();
rollback;
