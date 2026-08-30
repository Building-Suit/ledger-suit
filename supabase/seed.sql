-- Development seed data. Fake figures only — no production data, no secrets.
--
-- Applied automatically by `supabase db reset`. Two organizations exist so that
-- tenant isolation is visible while developing, not just in the test suite.
--
-- Sign in with any of these accounts, password: ledgersuit
--   owner@alpha.test       owner in Alpha Trading
--   accountant@alpha.test  accountant in Alpha Trading
--   viewer@alpha.test      viewer in Alpha Trading
--   owner@beta.test        owner in Beta Supplies
--
-- Seeding runs as the database superuser but still impersonates each user
-- through request.jwt.claims, so it exercises the same RPCs the app does
-- instead of writing to the ledger behind their back.

do $$
declare
  v_users jsonb := jsonb_build_array(
    jsonb_build_object('id', 'a0000000-0000-4000-8000-000000000001', 'email', 'owner@alpha.test',      'name', 'Amina Owner'),
    jsonb_build_object('id', 'a0000000-0000-4000-8000-000000000002', 'email', 'accountant@alpha.test', 'name', 'Karim Accountant'),
    jsonb_build_object('id', 'a0000000-0000-4000-8000-000000000003', 'email', 'viewer@alpha.test',     'name', 'Nour Viewer'),
    jsonb_build_object('id', 'b0000000-0000-4000-8000-000000000001', 'email', 'owner@beta.test',       'name', 'Beta Owner')
  );
  v_user jsonb;
begin
  for v_user in select * from jsonb_array_elements(v_users) loop
    -- The token columns must be empty strings, not NULL. GoTrue scans them into
    -- a non-nullable Go string, so a NULL makes every sign-in fail with
    -- "Database error querying schema" — which reads like a broken schema
    -- rather than bad seed data.
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
      'authenticated', 'authenticated',
      v_user ->> 'email',
      extensions.crypt('ledgersuit', extensions.gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('full_name', v_user ->> 'name'),
      now(), now(),
      '', '', '', '', '', '', '', ''
    )
    on conflict (id) do nothing;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Alpha Trading
-- ---------------------------------------------------------------------------
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

do $$
declare
  v_org      uuid;
  v_bank     uuid;
  v_cash     uuid;
  v_wallet   uuid;
  v_loan     uuid;
  v_equip    uuid;
  v_month    int;
  v_day      date;
begin
  v_org := public.create_organization(
    'Alpha Trading', 'EGP'::char(3), 'EG'::char(2), 'Africa/Cairo',
    'Alpha Trading LLC', 1::smallint
  );

  select id into v_bank   from public.accounts where organization_id = v_org and system_key = 'bank';
  select id into v_cash   from public.accounts where organization_id = v_org and system_key = 'cash';
  select id into v_wallet from public.accounts where organization_id = v_org and code = '1130';
  select id into v_loan   from public.accounts where organization_id = v_org and code = '2300';
  select id into v_equip  from public.accounts where organization_id = v_org and code = '1500';

  -- The other two team members.
  insert into public.organization_members (organization_id, user_id, role)
  values
    (v_org, 'a0000000-0000-4000-8000-000000000002', 'accountant'),
    (v_org, 'a0000000-0000-4000-8000-000000000003', 'viewer')
  on conflict do nothing;

  insert into public.counterparties (organization_id, name, type, email)
  values
    (v_org, 'Cairo Property Holdings', 'vendor',   'leasing@cairoproperty.test'),
    (v_org, 'Nile Logistics',          'customer', 'ap@nilelogistics.test'),
    (v_org, 'Delta Bank',              'lender',   null)
  on conflict do nothing;

  insert into public.tags (organization_id, name, color)
  values (v_org, 'Nasr City Branch', '#2563EB'), (v_org, 'Ramadan Campaign', '#DB2777')
  on conflict do nothing;

  -- Opening position: 250,000 EGP in the bank, 12,000 in cash, 80,000 of kit.
  perform public.post_opening_balance(
    v_org,
    date '2026-01-01',
    jsonb_build_array(
      jsonb_build_object('account_id', v_bank,  'amount_minor', 25000000),
      jsonb_build_object('account_id', v_cash,  'amount_minor', 1200000),
      jsonb_build_object('account_id', v_equip, 'amount_minor', 8000000)
    ),
    'Migrated from the old spreadsheet'
  );

  -- A loan drawn down in January.
  perform public.record_liability_created(
    p_organization_id        => v_org,
    p_amount_minor           => 15000000,
    p_liability_account_id   => v_loan,
    p_destination_account_id => v_bank,
    p_transaction_date       => date '2026-01-15',
    p_description            => 'Working capital facility',
    p_counterparty_id        => (select id from public.counterparties
                                 where organization_id = v_org and name = 'Delta Bank')
  );

  -- Seven months of routine trading.
  for v_month in 1..7 loop
    v_day := make_date(2026, v_month, 1);

    perform public.record_income(
      p_organization_id        => v_org,
      p_amount_minor           => 9000000 + (v_month * 350000),
      p_destination_account_id => v_bank,
      p_category_id            => (select id from public.categories
                                   where organization_id = v_org and name = 'Sales'),
      p_transaction_date       => v_day + 6,
      p_description            => 'Monthly product sales',
      p_reference              => 'INV-2026-' || lpad(v_month::text, 3, '0'),
      p_counterparty_id        => (select id from public.counterparties
                                   where organization_id = v_org and name = 'Nile Logistics')
    );

    perform public.record_income(
      p_organization_id        => v_org,
      p_amount_minor           => 2500000,
      p_destination_account_id => v_bank,
      p_category_id            => (select id from public.categories
                                   where organization_id = v_org and name = 'Services'),
      p_transaction_date       => v_day + 18,
      p_description            => 'Maintenance retainer'
    );

    perform public.record_expense(
      p_organization_id   => v_org,
      p_amount_minor      => 1500000,
      p_source_account_id => v_bank,
      p_category_id       => (select id from public.categories
                              where organization_id = v_org and name = 'Rent'),
      p_transaction_date  => v_day + 1,
      p_description       => 'Office rent',
      p_counterparty_id   => (select id from public.counterparties
                              where organization_id = v_org and name = 'Cairo Property Holdings')
    );

    perform public.record_expense(
      p_organization_id   => v_org,
      p_amount_minor      => 4200000,
      p_source_account_id => v_bank,
      p_category_id       => (select id from public.categories
                              where organization_id = v_org and name = 'Salaries'),
      p_transaction_date  => v_day + 27,
      p_description       => 'Payroll'
    );

    perform public.record_expense(
      p_organization_id   => v_org,
      p_amount_minor      => 320000 + (v_month * 15000),
      p_source_account_id => v_bank,
      p_category_id       => (select id from public.categories
                              where organization_id = v_org and name = 'Utilities'),
      p_transaction_date  => v_day + 12,
      p_description       => 'Electricity and water'
    );

    perform public.record_expense(
      p_organization_id   => v_org,
      p_amount_minor      => 180000,
      p_source_account_id => v_cash,
      p_category_id       => (select id from public.categories
                              where organization_id = v_org and name = 'Transportation'),
      p_transaction_date  => v_day + 9,
      p_description       => 'Deliveries and taxis'
    );

    -- Top the petty cash float back up from the bank.
    perform public.record_transfer(
      p_organization_id  => v_org,
      p_amount_minor     => 200000,
      p_from_account_id  => v_bank,
      p_to_account_id    => v_cash,
      p_transaction_date => v_day + 20,
      p_fee_minor        => 1500,
      p_description      => 'Petty cash top-up'
    );

    -- Loan instalment: principal plus interest.
    perform public.record_liability_payment(
      p_organization_id      => v_org,
      p_liability_account_id => v_loan,
      p_payment_account_id   => v_bank,
      p_principal_minor      => 1250000,
      p_interest_minor       => 95000,
      p_transaction_date     => v_day + 25,
      p_description          => 'Facility instalment'
    );
  end loop;

  -- A mobile wallet funded once, so the Cash Position widget has three rows.
  perform public.record_transfer(
    p_organization_id  => v_org,
    p_amount_minor     => 500000,
    p_from_account_id  => v_bank,
    p_to_account_id    => v_wallet,
    p_transaction_date => date '2026-03-04',
    p_description      => 'Load Vodafone Cash'
  );

  perform public.record_owner_contribution(
    p_organization_id        => v_org,
    p_amount_minor           => 5000000,
    p_destination_account_id => v_bank,
    p_transaction_date       => date '2026-04-02',
    p_description            => 'Additional capital injection'
  );

  perform public.record_owner_withdrawal(
    p_organization_id   => v_org,
    p_amount_minor      => 2000000,
    p_source_account_id => v_bank,
    p_transaction_date  => date '2026-06-20',
    p_description       => 'Owner drawings'
  );

  -- One mistake and its correction, so the reversal chain is visible in dev.
  declare
    v_mistake uuid;
  begin
    v_mistake := public.record_expense(
      p_organization_id   => v_org,
      p_amount_minor      => 750000,
      p_source_account_id => v_bank,
      p_category_id       => (select id from public.categories
                              where organization_id = v_org and name = 'Marketing'),
      p_transaction_date  => date '2026-05-14',
      p_description       => 'Billboard campaign (wrong amount)'
    );

    perform public.reverse_transaction(v_mistake, 'Supplier invoiced a different amount');

    perform public.record_expense(
      p_organization_id   => v_org,
      p_amount_minor      => 675000,
      p_source_account_id => v_bank,
      p_category_id       => (select id from public.categories
                              where organization_id = v_org and name = 'Marketing'),
      p_transaction_date  => date '2026-05-14',
      p_description       => 'Billboard campaign'
    );
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Beta Supplies — a second tenant, to make isolation obvious while developing
-- ---------------------------------------------------------------------------
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

do $$
declare
  v_org  uuid;
  v_bank uuid;
begin
  v_org := public.create_organization('Beta Supplies', 'EGP', 'EG', 'Africa/Cairo');

  select id into v_bank from public.accounts where organization_id = v_org and system_key = 'bank';

  perform public.post_opening_balance(
    v_org, date '2026-01-01',
    jsonb_build_array(jsonb_build_object('account_id', v_bank, 'amount_minor', 4000000)),
    'Initial float'
  );

  perform public.record_income(
    p_organization_id        => v_org,
    p_amount_minor           => 1750000,
    p_destination_account_id => v_bank,
    p_category_id            => (select id from public.categories
                                 where organization_id = v_org and name = 'Sales'),
    p_transaction_date       => date '2026-08-04',
    p_description            => 'Beta private revenue — must never be visible to Alpha'
  );
end;
$$;

select set_config('request.jwt.claims', null, false);
