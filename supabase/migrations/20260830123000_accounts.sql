-- Ledger Suit — 07. Chart of accounts
--
-- Presented to users as "Accounts". Balances are NOT stored here: the ledger
-- (public.transaction_entries) is the single source of truth and balances are
-- derived by public.account_balances. The spec's `opening_balance` /
-- `current_balance` fields are intentionally absent — an opening balance is a
-- posted journal like any other, so it cannot drift from the ledger.

-- Maps a subtype to the account type it must belong to. Immutable so it can be
-- used inside a CHECK constraint.
create or replace function app.account_type_for_subtype(p_subtype public.account_subtype)
returns public.account_type
language sql
immutable
set search_path = ''
as $$
  select case p_subtype
    when 'cash' then 'asset' when 'bank' then 'asset'
    when 'mobile_wallet' then 'asset' when 'accounts_receivable' then 'asset'
    when 'inventory' then 'asset' when 'prepaid_expenses' then 'asset'
    when 'equipment' then 'asset' when 'vehicles' then 'asset'
    when 'property' then 'asset' when 'other_asset' then 'asset'

    when 'accounts_payable' then 'liability' when 'credit_card' then 'liability'
    when 'loan' then 'liability' when 'taxes_payable' then 'liability'
    when 'accrued_expenses' then 'liability' when 'other_liability' then 'liability'

    when 'owner_capital' then 'equity' when 'retained_earnings' then 'equity'
    when 'owner_drawings' then 'equity' when 'opening_balance_equity' then 'equity'
    when 'other_equity' then 'equity'

    when 'product_sales' then 'revenue' when 'service_revenue' then 'revenue'
    when 'commission' then 'revenue' when 'other_income' then 'revenue'

    else 'expense'
  end::public.account_type;
$$;

-- Default cash-flow classification, overridable per account.
create or replace function app.default_cash_flow_section(p_subtype public.account_subtype)
returns public.cash_flow_section
language sql
immutable
set search_path = ''
as $$
  select case
    when p_subtype in ('cash', 'bank', 'mobile_wallet') then 'none'
    when p_subtype in ('equipment', 'vehicles', 'property', 'inventory') then 'investing'
    when p_subtype in ('loan', 'credit_card', 'owner_capital', 'owner_drawings',
                       'retained_earnings', 'opening_balance_equity', 'other_equity')
      then 'financing'
    else 'operating'
  end::public.cash_flow_section;
$$;

create table if not exists public.accounts (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references public.organizations (id) on delete cascade,
  parent_account_id uuid,
  code              text,
  name              text not null,
  type              public.account_type not null,
  subtype           public.account_subtype not null,
  normal_balance    public.normal_balance not null
                      generated always as (
                        case when type in ('asset', 'expense')
                             then 'debit'::public.normal_balance
                             else 'credit'::public.normal_balance end
                      ) stored,
  currency          char(3) not null references public.currencies (code),
  cash_flow_section public.cash_flow_section not null default 'operating',
  is_liquid         boolean not null
                      generated always as (
                        subtype in ('cash', 'bank', 'mobile_wallet')
                      ) stored,
  description       text,
  -- System accounts are created by the default chart of accounts and are
  -- referenced by the posting engine (e.g. opening balance equity). They may be
  -- renamed but not archived or deleted.
  is_system         boolean not null default false,
  system_key        text,
  is_active         boolean not null default true,
  is_archived       boolean not null default false,
  archived_at       timestamptz,
  created_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint accounts_name_length check (char_length(name) between 1 and 160),
  constraint accounts_code_format check (
    code is null or code ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$'
  ),
  constraint accounts_subtype_matches_type check (
    type = app.account_type_for_subtype(subtype)
  ),
  constraint accounts_no_self_parent check (parent_account_id is distinct from id),
  constraint accounts_archived_consistency check (
    (is_archived = false and archived_at is null)
    or (is_archived = true and archived_at is not null)
  ),
  -- Tenant-safe self reference: a parent must belong to the same organization.
  constraint accounts_parent_same_org foreign key (parent_account_id, organization_id)
    references public.accounts (id, organization_id) on delete restrict,
  constraint accounts_id_org_unique unique (id, organization_id)
);

comment on table public.accounts is
  'Chart of accounts, one tree per organization. Balances are derived from '
  'transaction_entries and never stored on this table.';
comment on column public.accounts.system_key is
  'Stable identifier for accounts the posting engine must be able to find '
  '(opening_balance_equity, accounts_receivable, bank_fees, ...).';
comment on column public.accounts.is_liquid is
  'Drives the dashboard Cash Position widget.';

create unique index if not exists accounts_org_code_key
  on public.accounts (organization_id, lower(code)) where code is not null;
create unique index if not exists accounts_org_system_key
  on public.accounts (organization_id, system_key) where system_key is not null;
create index if not exists accounts_org_type_idx
  on public.accounts (organization_id, type, subtype);
create index if not exists accounts_org_active_idx
  on public.accounts (organization_id) where is_archived = false;
create index if not exists accounts_parent_idx
  on public.accounts (parent_account_id) where parent_account_id is not null;
create index if not exists accounts_org_liquid_idx
  on public.accounts (organization_id) where is_liquid and is_archived = false;

create trigger accounts_set_updated_at
  before update on public.accounts
  for each row execute function app.set_updated_at();

alter table public.accounts enable row level security;

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------
create or replace function app.guard_account_changes()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_entry_count bigint;
begin
  if tg_op = 'DELETE' then
    if old.is_system then
      raise exception 'SYSTEM_ACCOUNT_PROTECTED: % cannot be deleted', old.name
        using errcode = '42501';
    end if;

    select count(*) into v_entry_count
    from public.transaction_entries e
    where e.account_id = old.id;

    if v_entry_count > 0 then
      raise exception 'ACCOUNT_HAS_LEDGER_HISTORY: archive it instead of deleting'
        using errcode = '23503';
    end if;

    return old;
  end if;

  -- organization_id is the tenant key and is immutable by design.
  if new.organization_id is distinct from old.organization_id then
    raise exception 'TENANT_KEY_IMMUTABLE: organization_id cannot be changed'
      using errcode = '42501';
  end if;

  if old.is_system then
    if new.is_archived and not old.is_archived then
      raise exception 'SYSTEM_ACCOUNT_PROTECTED: % cannot be archived', old.name
        using errcode = '42501';
    end if;
    if new.type <> old.type or new.subtype <> old.subtype then
      raise exception 'SYSTEM_ACCOUNT_PROTECTED: type of % cannot be changed', old.name
        using errcode = '42501';
    end if;
    if new.system_key is distinct from old.system_key then
      raise exception 'SYSTEM_ACCOUNT_PROTECTED: system_key of % is fixed', old.name
        using errcode = '42501';
    end if;
  end if;

  -- Changing the type of an account that already carries ledger history would
  -- silently restate every past report.
  if new.type <> old.type then
    select count(*) into v_entry_count
    from public.transaction_entries e
    where e.account_id = old.id;

    if v_entry_count > 0 then
      raise exception 'ACCOUNT_HAS_LEDGER_HISTORY: type cannot be changed after posting'
        using errcode = '23514';
    end if;
  end if;

  if new.is_archived and not old.is_archived and new.archived_at is null then
    new.archived_at := now();
  elsif not new.is_archived then
    new.archived_at := null;
  end if;

  return new;
end;
$$;

-- transaction_entries does not exist yet; the trigger is attached in the
-- transaction_entries migration so the dependency order stays honest.

-- ---------------------------------------------------------------------------
-- Cycle protection for the account tree
-- ---------------------------------------------------------------------------
create or replace function app.guard_account_hierarchy()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent uuid := new.parent_account_id;
  v_depth  int  := 0;
begin
  while v_parent is not null loop
    v_depth := v_depth + 1;

    if v_parent = new.id then
      raise exception 'ACCOUNT_HIERARCHY_CYCLE: account cannot be its own ancestor'
        using errcode = '23514';
    end if;

    if v_depth > 8 then
      raise exception 'ACCOUNT_HIERARCHY_TOO_DEEP: maximum depth is 8'
        using errcode = '23514';
    end if;

    select a.parent_account_id into v_parent
    from public.accounts a
    where a.id = v_parent;
  end loop;

  return new;
end;
$$;

create trigger accounts_guard_hierarchy
  before insert or update of parent_account_id on public.accounts
  for each row when (new.parent_account_id is not null)
  execute function app.guard_account_hierarchy();
