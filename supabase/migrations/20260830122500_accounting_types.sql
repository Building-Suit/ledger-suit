-- Ledger Suit — 06. Accounting enums and shared types

create type public.account_type as enum (
  'asset',
  'liability',
  'equity',
  'revenue',
  'expense'
);

create type public.normal_balance as enum (
  'debit',
  'credit'
);

-- Subtypes drive UI grouping, cash-flow classification and the default chart of
-- accounts. Extending the list later is an additive ALTER TYPE ... ADD VALUE.
create type public.account_subtype as enum (
  -- assets
  'cash',
  'bank',
  'mobile_wallet',
  'accounts_receivable',
  'inventory',
  'prepaid_expenses',
  'equipment',
  'vehicles',
  'property',
  'other_asset',
  -- liabilities
  'accounts_payable',
  'credit_card',
  'loan',
  'taxes_payable',
  'accrued_expenses',
  'other_liability',
  -- equity
  'owner_capital',
  'retained_earnings',
  'owner_drawings',
  'opening_balance_equity',
  'other_equity',
  -- revenue
  'product_sales',
  'service_revenue',
  'commission',
  'other_income',
  -- expenses
  'cost_of_sales',
  'salaries',
  'rent',
  'utilities',
  'marketing',
  'transportation',
  'software',
  'professional_fees',
  'bank_fees',
  'interest_expense',
  'depreciation',
  'taxes',
  'other_expense'
);

create type public.entry_side as enum (
  'debit',
  'credit'
);

create type public.transaction_type as enum (
  'income',
  'expense',
  'transfer',
  'asset_purchase',
  'liability_created',
  'liability_payment',
  'owner_contribution',
  'owner_withdrawal',
  'adjustment',
  'opening_balance',
  'reversal'
);

create type public.transaction_status as enum (
  'draft',
  'scheduled',
  'pending',
  'pending_approval',
  'posted',
  'voided',
  'reversed',
  'failed'
);

comment on type public.transaction_status is
  'pending_approval exists so an approval policy can be switched on later '
  'without reshaping the posting engine.';

create type public.cash_flow_section as enum (
  'operating',
  'investing',
  'financing',
  'none'
);

create type public.category_kind as enum (
  'income',
  'expense',
  'asset',
  'liability',
  'other'
);

create type public.counterparty_type as enum (
  'customer',
  'vendor',
  'lender',
  'employee',
  'government',
  'other'
);

create type public.transaction_source as enum (
  'manual',
  'import',
  'recurring',
  'commitment',
  'reversal',
  'opening_balance',
  'api'
);

-- ---------------------------------------------------------------------------
-- Normal balance is a property of the account type, not a free-form field.
-- ---------------------------------------------------------------------------
create or replace function app.normal_balance_for(p_type public.account_type)
returns public.normal_balance
language sql
immutable
set search_path = ''
as $$
  select case
    when p_type in ('asset', 'expense') then 'debit'::public.normal_balance
    else 'credit'::public.normal_balance
  end;
$$;

comment on function app.normal_balance_for(public.account_type) is
  'Asset/Expense are debit-normal; Liability/Equity/Revenue are credit-normal.';

grant execute on function app.normal_balance_for(public.account_type)
  to authenticated, service_role;
