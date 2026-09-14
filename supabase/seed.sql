-- Development identities and empty organizations. No accounts, categories or
-- ledger activity are seeded: the chart of accounts is owned by the user.
--
-- Sign in with any account below using the password: ledgersuit

do $$
declare
  v_users jsonb := jsonb_build_array(
    jsonb_build_object('id', 'a0000000-0000-4000-8000-000000000001', 'email', 'owner@alpha.test',       'name', 'Amina Owner'),
    jsonb_build_object('id', 'a0000000-0000-4000-8000-000000000002', 'email', 'accountant@alpha.test',  'name', 'Karim Accountant'),
    jsonb_build_object('id', 'a0000000-0000-4000-8000-000000000003', 'email', 'viewer@alpha.test',      'name', 'Nour Viewer'),
    jsonb_build_object('id', 'b0000000-0000-4000-8000-000000000001', 'email', 'owner@beta.test',        'name', 'Beta Owner')
  );
  v_user jsonb;
begin
  for v_user in select * from jsonb_array_elements(v_users) loop
    insert into auth.users (
      id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new,
      email_change_token_current, email_change, phone_change,
      phone_change_token, reauthentication_token
    )
    values (
      (v_user ->> 'id')::uuid,
      '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated', v_user ->> 'email',
      extensions.crypt('ledgersuit', extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('full_name', v_user ->> 'name'), now(), now(),
      '', '', '', '', '', '', '', ''
    )
    on conflict (id) do nothing;
  end loop;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

do $$
declare v_org uuid;
begin
  v_org := public.create_organization(
    'Alpha Trading', 'EGP'::char(3), 'EG'::char(2), 'Africa/Cairo',
    'Alpha Trading LLC', 1::smallint
  );

  update public.subscriptions
  set status = 'active', provider = 'paymob',
      provider_subscription_id = 'sub_local_alpha', provider_status = 'active',
      billing_interval = 'monthly', checkout_completed_at = now(),
      current_period_start = now(), current_period_end = now() + interval '30 days'
  where organization_id = v_org;

  insert into public.organization_members (organization_id, user_id, role)
  values
    (v_org, 'a0000000-0000-4000-8000-000000000002', 'accountant'),
    (v_org, 'a0000000-0000-4000-8000-000000000003', 'viewer')
  on conflict do nothing;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

do $$
declare v_org uuid;
begin
  v_org := public.create_organization('Beta Supplies', 'EGP', 'EG', 'Africa/Cairo');

  update public.subscriptions
  set status = 'active', provider = 'paymob',
      provider_subscription_id = 'sub_local_beta', provider_status = 'active',
      billing_interval = 'monthly', checkout_completed_at = now(),
      current_period_start = now(), current_period_end = now() + interval '30 days'
  where organization_id = v_org;
end;
$$;

select set_config('request.jwt.claims', null, false);
