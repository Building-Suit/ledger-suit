-- Ledger Suit — 15. Default chart of accounts, categories and organization setup
--
-- A new organization is usable immediately: it gets a complete chart of
-- accounts, the system accounts the posting engine depends on, and a starter
-- set of user-facing categories already wired to the right ledger accounts.

create or replace function app.seed_chart_of_accounts(p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_currency char(3) := app.org_base_currency(p_organization_id);
  v_row      record;
  v_parent   uuid;
begin
  -- code, name, subtype, parent code, system_key
  for v_row in
    select * from (values
      ('1000', 'Assets',                  'other_asset',            null,   null),
      ('1100', 'Cash and Bank',           'other_asset',            '1000', null),
      ('1110', 'Cash',                    'cash',                   '1100', 'cash'),
      ('1120', 'Bank Account',            'bank',                   '1100', 'bank'),
      ('1130', 'Mobile Wallet',           'mobile_wallet',          '1100', null),
      ('1200', 'Accounts Receivable',     'accounts_receivable',    '1000', 'accounts_receivable'),
      ('1300', 'Inventory',               'inventory',              '1000', null),
      ('1400', 'Prepaid Expenses',        'prepaid_expenses',       '1000', null),
      ('1500', 'Equipment',               'equipment',              '1000', null),
      ('1600', 'Vehicles',                'vehicles',               '1000', null),

      ('2000', 'Liabilities',             'other_liability',        null,   null),
      ('2100', 'Accounts Payable',        'accounts_payable',       '2000', 'accounts_payable'),
      ('2200', 'Credit Cards',            'credit_card',            '2000', null),
      ('2300', 'Loans',                   'loan',                   '2000', null),
      ('2400', 'Taxes Payable',           'taxes_payable',          '2000', null),
      ('2500', 'Accrued Expenses',        'accrued_expenses',       '2000', null),

      ('3000', 'Equity',                  'other_equity',           null,   null),
      ('3100', 'Owner Capital',           'owner_capital',          '3000', 'owner_capital'),
      ('3200', 'Retained Earnings',       'retained_earnings',      '3000', 'retained_earnings'),
      ('3300', 'Owner Drawings',          'owner_drawings',         '3000', 'owner_drawings'),
      ('3900', 'Opening Balance Equity',  'opening_balance_equity', '3000', 'opening_balance_equity'),

      ('4000', 'Revenue',                 'other_income',           null,   null),
      ('4100', 'Product Sales',           'product_sales',          '4000', 'product_sales'),
      ('4200', 'Service Revenue',         'service_revenue',        '4000', 'service_revenue'),
      ('4300', 'Commission',              'commission',             '4000', null),
      ('4900', 'Other Income',            'other_income',           '4000', 'other_income'),

      ('5000', 'Expenses',                'other_expense',          null,   null),
      ('5100', 'Cost of Sales',           'cost_of_sales',          '5000', 'cost_of_sales'),
      ('5200', 'Salaries',                'salaries',               '5000', 'salaries'),
      ('5300', 'Rent',                    'rent',                   '5000', 'rent'),
      ('5400', 'Utilities',               'utilities',              '5000', 'utilities'),
      ('5500', 'Marketing',               'marketing',              '5000', 'marketing'),
      ('5600', 'Transportation',          'transportation',         '5000', 'transportation'),
      ('5700', 'Software',                'software',               '5000', 'software'),
      ('5800', 'Professional Fees',       'professional_fees',      '5000', null),
      ('5850', 'Bank Fees',               'bank_fees',              '5000', 'bank_fees'),
      ('5860', 'Interest Expense',        'interest_expense',       '5000', 'interest_expense'),
      -- Absorbs the difference when a cross-currency movement does not convert
      -- to an equal base amount on both sides.
      ('5870', 'FX Gain / Loss',          'other_expense',          '5000', 'fx_gain_loss'),
      ('5900', 'Taxes',                   'taxes',                  '5000', null),
      ('5950', 'Other Expenses',          'other_expense',          '5000', 'other_expense')
    ) as t(code, name, subtype, parent_code, system_key)
  loop
    v_parent := null;
    if v_row.parent_code is not null then
      select a.id into v_parent
      from public.accounts a
      where a.organization_id = p_organization_id and a.code = v_row.parent_code;
    end if;

    insert into public.accounts (
      organization_id, parent_account_id, code, name, type, subtype, currency,
      cash_flow_section, is_system, system_key, created_by
    )
    values (
      p_organization_id,
      v_parent,
      v_row.code,
      v_row.name,
      app.account_type_for_subtype(v_row.subtype::public.account_subtype),
      v_row.subtype::public.account_subtype,
      v_currency,
      app.default_cash_flow_section(v_row.subtype::public.account_subtype),
      true,
      v_row.system_key,
      auth.uid()
    )
    on conflict do nothing;
  end loop;
end;
$$;

comment on function app.seed_chart_of_accounts(uuid) is
  'Creates the default chart of accounts, including every account the posting '
  'engine looks up by system_key.';

-- ---------------------------------------------------------------------------
-- Starter categories, each already pointing at a ledger account
-- ---------------------------------------------------------------------------
create or replace function app.seed_categories(p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_account uuid;
begin
  for v_row in
    select * from (values
      ('Sales',            'income',  'product_sales'),
      ('Services',         'income',  'service_revenue'),
      ('Other Income',     'income',  'other_income'),
      ('Rent',             'expense', 'rent'),
      ('Salaries',         'expense', 'salaries'),
      ('Utilities',        'expense', 'utilities'),
      ('Marketing',        'expense', 'marketing'),
      ('Transportation',   'expense', 'transportation'),
      ('Software',         'expense', 'software'),
      ('Bank Fees',        'expense', 'bank_fees'),
      ('Cost of Sales',    'expense', 'cost_of_sales'),
      ('Other Expenses',   'expense', 'other_expense')
    ) as t(name, kind, system_key)
  loop
    select a.id into v_account
    from public.accounts a
    where a.organization_id = p_organization_id and a.system_key = v_row.system_key;

    insert into public.categories (
      organization_id, name, kind, default_account_id, is_system, created_by
    )
    values (
      p_organization_id, v_row.name, v_row.kind::public.category_kind,
      v_account, true, auth.uid()
    )
    on conflict do nothing;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Organization creation
-- ---------------------------------------------------------------------------
create or replace function app.slugify(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select trim(both '-' from
    regexp_replace(lower(coalesce(p_text, '')), '[^a-z0-9]+', '-', 'g')
  );
$$;

create or replace function public.create_organization(
  p_name           text,
  p_base_currency  char(3) default 'EGP',
  p_country_code   char(2) default 'EG',
  p_timezone       text    default 'Africa/Cairo',
  p_legal_name     text    default null,
  p_fiscal_year_start_month smallint default 1
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_slug   text;
  v_base   text;
  v_suffix int := 0;
  v_user   uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'TENANT_ACCESS_DENIED: authentication required'
      using errcode = '42501';
  end if;

  if p_name is null or char_length(trim(p_name)) = 0 then
    raise exception 'INVALID_INPUT: organization name is required'
      using errcode = '22023';
  end if;

  if not exists (select 1 from public.currencies c
                 where c.code = p_base_currency and c.is_active) then
    raise exception 'INVALID_CURRENCY: % is not a supported currency', p_base_currency
      using errcode = '22023';
  end if;

  -- Slug must satisfy organizations_slug_format: 3+ chars, alphanumeric edges.
  v_base := app.slugify(p_name);
  if char_length(v_base) < 3 then
    v_base := v_base || '-org';
  end if;
  v_base := left(v_base, 58);
  v_slug := v_base;

  while exists (select 1 from public.organizations o where o.slug = v_slug) loop
    v_suffix := v_suffix + 1;
    v_slug := v_base || '-' || v_suffix::text;
  end loop;

  insert into public.organizations (
    name, slug, legal_name, country_code, timezone, base_currency,
    fiscal_year_start_month, created_by
  )
  values (
    trim(p_name), v_slug, p_legal_name, upper(p_country_code), p_timezone,
    p_base_currency, p_fiscal_year_start_month, v_user
  )
  returning id into v_org_id;

  insert into public.organization_settings (organization_id, default_transaction_currency)
  values (v_org_id, p_base_currency);

  -- The creator is the owner. This is the only place a membership is created
  -- without an invitation.
  insert into public.organization_members (organization_id, user_id, role, status)
  values (v_org_id, v_user, 'owner', 'active');

  perform app.seed_chart_of_accounts(v_org_id);
  perform app.seed_categories(v_org_id);

  update public.profiles p
  set default_organization_id = v_org_id
  where p.id = v_user and p.default_organization_id is null;

  perform app.write_audit(
    v_org_id, 'organization.created', 'organization', v_org_id,
    null, jsonb_build_object('name', trim(p_name), 'base_currency', p_base_currency)
  );

  return v_org_id;
end;
$$;

comment on function public.create_organization(text, char, char, text, text, smallint) is
  'Creates a tenant, its settings, its owner membership and its default chart '
  'of accounts in one transaction.';
