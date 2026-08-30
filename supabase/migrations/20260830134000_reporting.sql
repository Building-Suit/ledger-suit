-- Ledger Suit — 21. Reporting views and RPCs
--
-- Every figure below is derived from posted ledger entries. Nothing is cached,
-- nothing is computed in the browser, and drafts, scheduled transactions and
-- commitments never reach an official report.
--
-- All views are declared security_invoker so RLS still applies: a view is not a
-- way around the tenant boundary.

-- ---------------------------------------------------------------------------
-- Per-account balances
-- ---------------------------------------------------------------------------
create or replace view public.account_balances
with (security_invoker = true) as
select
  a.organization_id,
  a.id                as account_id,
  a.code,
  a.name,
  a.type,
  a.subtype,
  a.normal_balance,
  a.currency,
  a.is_liquid,
  a.is_archived,
  a.parent_account_id,
  coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)::bigint  as debit_minor,
  coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0)::bigint as credit_minor,
  -- Signed so that a positive number always means "more of what this account
  -- normally holds", which is what a non-accountant expects to see.
  (case when a.normal_balance = 'debit'
        then coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)
           - coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0)
        else coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0)
           - coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)
   end)::bigint as balance_minor,
  count(e.id) as entry_count
from public.accounts a
left join public.transaction_entries e
  on e.account_id = a.id
 and e.posted_at is not null
group by a.organization_id, a.id;

comment on view public.account_balances is
  'Live balances derived from posted ledger entries, in base-currency minor '
  'units. There is no stored balance column anywhere to drift from this.';

-- ---------------------------------------------------------------------------
-- Flattened ledger, ready for the Transactions table and the Ledger report
-- ---------------------------------------------------------------------------
create or replace view public.ledger_entries
with (security_invoker = true) as
select
  e.id                as entry_id,
  e.organization_id,
  e.transaction_id,
  e.account_id,
  a.code              as account_code,
  a.name              as account_name,
  a.type              as account_type,
  e.side,
  e.amount_minor,
  e.currency_code,
  e.base_amount_minor,
  e.base_currency_code,
  e.exchange_rate,
  e.entry_date,
  e.posted_at,
  e.memo,
  t.type              as transaction_type,
  t.status            as transaction_status,
  t.reference,
  t.description,
  t.counterparty_id,
  t.category_id,
  t.created_by
from public.transaction_entries e
join public.transactions t on t.id = e.transaction_id
join public.accounts a     on a.id = e.account_id
where e.posted_at is not null;

comment on view public.ledger_entries is
  'Posted ledger lines joined to their transaction and account. Drafts are '
  'excluded by construction.';

grant select on public.account_balances, public.ledger_entries to authenticated;

-- ---------------------------------------------------------------------------
-- Trial balance
-- ---------------------------------------------------------------------------
create or replace function public.report_trial_balance(
  p_organization_id uuid,
  p_as_of_date      date default null
)
returns table (
  account_id      uuid,
  code            text,
  name            text,
  type            public.account_type,
  debit_minor     bigint,
  credit_minor    bigint
)
language plpgsql
stable
set search_path = ''
as $$
begin
  perform app.require_capability(p_organization_id, 'reports.read');

  return query
  select
    a.id, a.code, a.name, a.type,
    coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)::bigint,
    coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0)::bigint
  from public.accounts a
  left join public.transaction_entries e
    on e.account_id = a.id
   and e.posted_at is not null
   and (p_as_of_date is null or e.entry_date <= p_as_of_date)
  where a.organization_id = p_organization_id
  group by a.id, a.code, a.name, a.type
  having count(e.id) > 0
  order by a.code nulls last, a.name;
end;
$$;

-- ---------------------------------------------------------------------------
-- Profit & Loss
-- ---------------------------------------------------------------------------
create or replace function public.report_profit_and_loss(
  p_organization_id uuid,
  p_from_date       date,
  p_to_date         date
)
returns table (
  section        text,
  account_id     uuid,
  code           text,
  name           text,
  amount_minor   bigint
)
language plpgsql
stable
set search_path = ''
as $$
begin
  perform app.require_capability(p_organization_id, 'reports.read');

  if p_from_date > p_to_date then
    raise exception 'INVALID_DATE_RANGE: from date is after to date'
      using errcode = '22023';
  end if;

  return query
  with movements as (
    select
      a.id, a.code, a.name, a.type, a.subtype, a.normal_balance,
      coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)  as dr,
      coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0) as cr
    from public.accounts a
    join public.transaction_entries e
      on e.account_id = a.id
     and e.posted_at is not null
     and e.entry_date between p_from_date and p_to_date
    where a.organization_id = p_organization_id
      and a.type in ('revenue', 'expense')
    group by a.id, a.code, a.name, a.type, a.subtype, a.normal_balance
  )
  select
    case
      when m.type = 'revenue' then 'revenue'
      when m.subtype = 'cost_of_sales' then 'cost_of_sales'
      else 'operating_expenses'
    end,
    m.id, m.code, m.name,
    (case when m.normal_balance = 'credit' then m.cr - m.dr else m.dr - m.cr end)::bigint
  from movements m
  order by 1, m.code nulls last, m.name;
end;
$$;

comment on function public.report_profit_and_loss(uuid, date, date) is
  'Posted revenue and expense movements for a period. Net profit is '
  'revenue - cost_of_sales - operating_expenses.';

-- ---------------------------------------------------------------------------
-- Balance sheet
-- ---------------------------------------------------------------------------
create or replace function public.report_balance_sheet(
  p_organization_id uuid,
  p_as_of_date      date default null
)
returns table (
  section      text,
  account_id   uuid,
  code         text,
  name         text,
  amount_minor bigint
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_as_of date := coalesce(p_as_of_date, app.org_today(p_organization_id));
begin
  perform app.require_capability(p_organization_id, 'reports.read');

  return query
  with balances as (
    select
      a.id, a.code, a.name, a.type, a.normal_balance,
      (case when a.normal_balance = 'debit'
            then coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)
               - coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0)
            else coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0)
               - coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)
       end)::bigint as balance
    from public.accounts a
    join public.transaction_entries e
      on e.account_id = a.id
     and e.posted_at is not null
     and e.entry_date <= v_as_of
    where a.organization_id = p_organization_id
    group by a.id, a.code, a.name, a.type, a.normal_balance
  )
  select b.type::text, b.id, b.code, b.name, b.balance
  from balances b
  where b.type in ('asset', 'liability', 'equity')
    and b.balance <> 0

  union all

  -- Revenue less expenses for every period up to the reporting date. Without
  -- this line the statement cannot balance, because profit has not been closed
  -- into retained earnings yet.
  select
    'equity', null::uuid, null::text, 'Net profit for the period',
    coalesce(sum(case when b.type = 'revenue' then b.balance else -b.balance end), 0)::bigint
  from balances b
  where b.type in ('revenue', 'expense')
  having coalesce(sum(case when b.type = 'revenue' then b.balance else -b.balance end), 0) <> 0

  order by 1, 3 nulls last, 4;
end;
$$;

-- Assets = Liabilities + Equity, checked against the ledger itself.
create or replace function public.check_balance_sheet_integrity(
  p_organization_id uuid,
  p_as_of_date      date default null
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_as_of date := coalesce(p_as_of_date, app.org_today(p_organization_id));
  v_assets bigint := 0;
  v_liabilities bigint := 0;
  v_equity bigint := 0;
  v_net_income bigint := 0;
  v_difference bigint;
begin
  perform app.require_capability(p_organization_id, 'reports.read');

  select
    coalesce(sum(case when b.type = 'asset'     then b.amount else 0 end), 0),
    coalesce(sum(case when b.type = 'liability' then b.amount else 0 end), 0),
    coalesce(sum(case when b.type = 'equity'    then b.amount else 0 end), 0),
    coalesce(sum(case when b.type = 'revenue'   then b.amount
                      when b.type = 'expense'   then -b.amount
                      else 0 end), 0)
  into v_assets, v_liabilities, v_equity, v_net_income
  from (
    select
      a.type,
      case when a.normal_balance = 'debit'
           then coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)
              - coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0)
           else coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0)
              - coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)
      end as amount
    from public.accounts a
    join public.transaction_entries e
      on e.account_id = a.id
     and e.posted_at is not null
     and e.entry_date <= v_as_of
    where a.organization_id = p_organization_id
    group by a.id, a.type, a.normal_balance
  ) b;

  v_difference := v_assets - (v_liabilities + v_equity + v_net_income);

  return jsonb_build_object(
    'as_of',            v_as_of,
    'assets_minor',     v_assets,
    'liabilities_minor', v_liabilities,
    'equity_minor',     v_equity,
    'net_income_minor', v_net_income,
    'difference_minor', v_difference,
    'balanced',         v_difference = 0
  );
end;
$$;

comment on function public.check_balance_sheet_integrity(uuid, date) is
  'Diagnostic. A non-zero difference is an accounting integrity failure and '
  'must be surfaced, never hidden.';

-- ---------------------------------------------------------------------------
-- Cash flow
-- ---------------------------------------------------------------------------
-- Movement in liquid accounts, classified by the cash_flow_section of the
-- accounts on the other side of each journal. Manual overrides can be layered
-- on later without changing the shape of this result.
create or replace function public.report_cash_flow(
  p_organization_id uuid,
  p_from_date       date,
  p_to_date         date
)
returns table (
  section       public.cash_flow_section,
  amount_minor  bigint
)
language plpgsql
stable
set search_path = ''
as $$
begin
  perform app.require_capability(p_organization_id, 'reports.read');

  if p_from_date > p_to_date then
    raise exception 'INVALID_DATE_RANGE: from date is after to date'
      using errcode = '22023';
  end if;

  return query
  with cash_moves as (
    select
      e.transaction_id,
      sum(case when e.side = 'debit' then e.base_amount_minor
               else -e.base_amount_minor end) as cash_delta
    from public.transaction_entries e
    join public.accounts a on a.id = e.account_id
    where e.organization_id = p_organization_id
      and e.posted_at is not null
      and e.entry_date between p_from_date and p_to_date
      and a.is_liquid
    group by e.transaction_id
  ),
  counterpart as (
    select
      e.transaction_id,
      a.cash_flow_section,
      sum(e.base_amount_minor) as weight
    from public.transaction_entries e
    join public.accounts a on a.id = e.account_id
    where e.organization_id = p_organization_id
      and e.posted_at is not null
      and not a.is_liquid
    group by e.transaction_id, a.cash_flow_section
  ),
  dominant as (
    select distinct on (c.transaction_id)
      c.transaction_id, c.cash_flow_section
    from counterpart c
    order by c.transaction_id, c.weight desc, c.cash_flow_section
  )
  select
    coalesce(d.cash_flow_section, 'operating'::public.cash_flow_section),
    sum(m.cash_delta)::bigint
  from cash_moves m
  left join dominant d on d.transaction_id = m.transaction_id
  where m.cash_delta <> 0
  group by 1
  order by 1;
end;
$$;

-- ---------------------------------------------------------------------------
-- General ledger with running balance
-- ---------------------------------------------------------------------------
create or replace function public.report_general_ledger(
  p_organization_id uuid,
  p_account_id      uuid,
  p_from_date       date,
  p_to_date         date
)
returns table (
  entry_id        uuid,
  transaction_id  uuid,
  entry_date      date,
  reference       text,
  description     text,
  memo            text,
  debit_minor     bigint,
  credit_minor    bigint,
  running_balance_minor bigint
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_opening bigint;
  v_sign    int;
begin
  perform app.require_capability(p_organization_id, 'reports.read');
  perform app.require_account(p_organization_id, p_account_id, null, 'account');

  select case when a.normal_balance = 'debit' then 1 else -1 end
  into v_sign
  from public.accounts a where a.id = p_account_id;

  select coalesce(sum(
           case when e.side = 'debit' then e.base_amount_minor
                else -e.base_amount_minor end), 0) * v_sign
  into v_opening
  from public.transaction_entries e
  where e.account_id = p_account_id
    and e.posted_at is not null
    and e.entry_date < p_from_date;

  return query
  select
    e.id, e.transaction_id, e.entry_date, t.reference, t.description, e.memo,
    case when e.side = 'debit'  then e.base_amount_minor else 0 end,
    case when e.side = 'credit' then e.base_amount_minor else 0 end,
    (v_opening + sum(
      case when e.side = 'debit' then e.base_amount_minor
           else -e.base_amount_minor end * v_sign
    ) over (order by e.entry_date, e.created_at, e.id
            rows between unbounded preceding and current row))::bigint
  from public.transaction_entries e
  join public.transactions t on t.id = e.transaction_id
  where e.account_id = p_account_id
    and e.posted_at is not null
    and e.entry_date between p_from_date and p_to_date
  order by e.entry_date, e.created_at, e.id;
end;
$$;

comment on function public.report_general_ledger(uuid, uuid, date, date) is
  'Ledger for one account with an opening balance and a running balance, both '
  'expressed on the account''s normal side.';

-- ---------------------------------------------------------------------------
-- Dashboard
-- ---------------------------------------------------------------------------
create or replace function public.dashboard_summary(
  p_organization_id uuid,
  p_as_of_date      date default null
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_as_of        date := coalesce(p_as_of_date, app.org_today(p_organization_id));
  v_month_start  date := date_trunc('month', v_as_of)::date;
  v_prev_start   date := (date_trunc('month', v_as_of) - interval '1 month')::date;
  v_prev_end     date := (date_trunc('month', v_as_of) - interval '1 day')::date;
  v_assets       bigint;
  v_liabilities  bigint;
  v_cash         bigint;
  v_receivable   bigint;
  v_payable      bigint;
  v_revenue      bigint;
  v_expenses     bigint;
  v_prev_revenue bigint;
  v_prev_expenses bigint;
begin
  perform app.require_capability(p_organization_id, 'reports.read');

  with balances as (
    select
      a.type, a.subtype, a.is_liquid,
      case when a.normal_balance = 'debit'
           then coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)
              - coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0)
           else coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0)
              - coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)
      end as amount
    from public.accounts a
    left join public.transaction_entries e
      on e.account_id = a.id
     and e.posted_at is not null
     and e.entry_date <= v_as_of
    where a.organization_id = p_organization_id
    group by a.id, a.type, a.subtype, a.is_liquid
  )
  select
    coalesce(sum(amount) filter (where type = 'asset'), 0),
    coalesce(sum(amount) filter (where type = 'liability'), 0),
    coalesce(sum(amount) filter (where is_liquid), 0),
    coalesce(sum(amount) filter (where subtype = 'accounts_receivable'), 0),
    coalesce(sum(amount) filter (where subtype = 'accounts_payable'), 0)
  into v_assets, v_liabilities, v_cash, v_receivable, v_payable
  from balances;

  select
    coalesce(sum(case when a.type = 'revenue'
                      then case when e.side = 'credit' then e.base_amount_minor
                                else -e.base_amount_minor end end), 0),
    coalesce(sum(case when a.type = 'expense'
                      then case when e.side = 'debit' then e.base_amount_minor
                                else -e.base_amount_minor end end), 0)
  into v_revenue, v_expenses
  from public.transaction_entries e
  join public.accounts a on a.id = e.account_id
  where e.organization_id = p_organization_id
    and e.posted_at is not null
    and e.entry_date between v_month_start and v_as_of;

  select
    coalesce(sum(case when a.type = 'revenue'
                      then case when e.side = 'credit' then e.base_amount_minor
                                else -e.base_amount_minor end end), 0),
    coalesce(sum(case when a.type = 'expense'
                      then case when e.side = 'debit' then e.base_amount_minor
                                else -e.base_amount_minor end end), 0)
  into v_prev_revenue, v_prev_expenses
  from public.transaction_entries e
  join public.accounts a on a.id = e.account_id
  where e.organization_id = p_organization_id
    and e.posted_at is not null
    and e.entry_date between v_prev_start and v_prev_end;

  return jsonb_build_object(
    'as_of',                v_as_of,
    'base_currency',        app.org_base_currency(p_organization_id),
    'total_assets_minor',   v_assets,
    'total_liabilities_minor', v_liabilities,
    'net_worth_minor',      v_assets - v_liabilities,
    'cash_and_bank_minor',  v_cash,
    'accounts_receivable_minor', v_receivable,
    'accounts_payable_minor',    v_payable,
    'revenue_this_month_minor',  v_revenue,
    'expenses_this_month_minor', v_expenses,
    'net_profit_this_month_minor', v_revenue - v_expenses,
    'revenue_previous_month_minor',  v_prev_revenue,
    'expenses_previous_month_minor', v_prev_expenses,
    'net_profit_previous_month_minor', v_prev_revenue - v_prev_expenses
  );
end;
$$;

comment on function public.dashboard_summary(uuid, date) is
  'Every dashboard KPI in one round trip, computed server-side from posted '
  'ledger entries.';

do $$
declare
  v_fn record;
begin
  for v_fn in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'report_trial_balance', 'report_profit_and_loss', 'report_balance_sheet',
        'report_cash_flow', 'report_general_ledger', 'dashboard_summary',
        'check_balance_sheet_integrity'
      )
  loop
    execute format('revoke all on function %s from public, anon', v_fn.signature);
    execute format('grant execute on function %s to authenticated, service_role', v_fn.signature);
  end loop;
end;
$$;
