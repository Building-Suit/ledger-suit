-- Ledger Suit — user-managed chart of accounts
--
-- Organizations now start with an empty chart. Existing ledger/account fixture
-- data is cleared once so every account visible after this migration is one a
-- user deliberately creates.

truncate table
  public.recurring_rules,
  public.commitments,
  public.transactions,
  public.categories,
  public.accounts
cascade;

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

  insert into public.organization_members (organization_id, user_id, role, status)
  values (v_org_id, v_user, 'owner', 'active');

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
  'Creates a tenant, its settings and owner membership with an empty, user-managed chart of accounts.';

-- Preserve the plain-language transaction flows when users build the chart
-- themselves. The first account for a workflow-specific subtype receives the
-- internal lookup key, and revenue/expense accounts receive a matching category.
create or replace function public.create_account(
  p_organization_id uuid,
  p_name text,
  p_type public.account_type,
  p_subtype public.account_subtype,
  p_currency char(3) default null,
  p_code text default null,
  p_parent_account_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_system_key text;
begin
  perform app.require_capability(p_organization_id, 'accounts.create');
  if p_name is null or char_length(trim(p_name)) = 0 then
    raise exception 'INVALID_INPUT: account name is required' using errcode = '22023';
  end if;
  if p_parent_account_id is not null then
    perform app.require_account(p_organization_id, p_parent_account_id,
      array[p_type]::public.account_type[], 'parent account');
  end if;

  if p_subtype::text in (
    'bank_fees', 'interest_expense', 'owner_capital', 'owner_drawings',
    'opening_balance_equity'
  ) and not exists (
    select 1 from public.accounts a
    where a.organization_id = p_organization_id
      and a.system_key = p_subtype::text
  ) then
    v_system_key := p_subtype::text;
  end if;

  insert into public.accounts (
    organization_id, code, name, type, subtype, currency,
    parent_account_id, system_key, created_by
  ) values (
    p_organization_id, nullif(trim(p_code), ''), trim(p_name), p_type,
    p_subtype, coalesce(p_currency, app.org_base_currency(p_organization_id)),
    p_parent_account_id, v_system_key, auth.uid()
  ) returning id into v_id;

  if p_type in ('revenue', 'expense') then
    insert into public.categories (
      organization_id, name, kind, default_account_id, created_by
    ) values (
      p_organization_id,
      trim(p_name),
      case when p_type = 'revenue'
        then 'income'::public.category_kind
        else 'expense'::public.category_kind
      end,
      v_id,
      auth.uid()
    )
    on conflict (organization_id, lower(name)) do update
      set default_account_id = excluded.default_account_id,
          kind = excluded.kind,
          is_active = true;
  end if;

  perform app.write_audit(p_organization_id, 'account.created', 'account', v_id,
    null, jsonb_build_object('name', trim(p_name), 'type', p_type, 'subtype', p_subtype));
  return v_id;
end;
$$;
