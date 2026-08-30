-- Ledger Suit — 22. Query surface for the Transactions page and dashboard
--
-- The Transactions table needs one row per transaction carrying figures that
-- only exist in the ledger (the amount, which account the money left, which it
-- arrived in). Deriving that in the browser would mean shipping every ledger
-- line to the client, so it is derived here instead.
--
-- Everything in this file is read-only and runs as the caller, so row level
-- security still applies.

create extension if not exists pg_trgm with schema extensions;

-- Free-text search over the columns a user actually searches by.
create index if not exists transactions_description_trgm_idx
  on public.transactions using gin (description extensions.gin_trgm_ops);
create index if not exists transactions_reference_trgm_idx
  on public.transactions using gin (reference extensions.gin_trgm_ops);
create index if not exists counterparties_name_trgm_idx
  on public.counterparties using gin (name extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- One row per transaction, with its derived money columns
-- ---------------------------------------------------------------------------
create or replace view public.transaction_summaries
with (security_invoker = true) as
select
  t.id,
  t.organization_id,
  t.type,
  t.status,
  t.source,
  t.transaction_date,
  t.posting_date,
  t.currency_code,
  t.exchange_rate,
  t.description,
  t.reference,
  t.memo,
  t.adjustment_reason,
  t.counterparty_id,
  t.category_id,
  t.possible_duplicate,
  t.reverses_transaction_id,
  t.reversed_by_transaction_id,
  t.created_by,
  t.posted_by,
  t.posted_at,
  t.created_at,
  t.updated_at,

  -- A balanced journal debits exactly as much as it credits, so either side is
  -- "the amount". Debits are used by convention.
  coalesce(totals.debit_minor, 0)      as amount_minor,
  coalesce(totals.base_debit_minor, 0) as base_amount_minor,
  coalesce(totals.line_count, 0)       as line_count,

  -- For a two-line journal this is simply the credited and debited account.
  -- For a longer one (a loan payment splitting principal, interest and fees)
  -- the largest line on each side is the meaningful one to show in a table.
  credit_side.account_id   as from_account_id,
  credit_side.account_name as from_account_name,
  debit_side.account_id    as to_account_id,
  debit_side.account_name  as to_account_name,

  cat.name  as category_name,
  cp.name   as counterparty_name,
  author.full_name as created_by_name,
  author.email     as created_by_email,

  coalesce(tag_list.tags, array[]::text[])   as tags,
  coalesce(tag_list.tag_ids, array[]::uuid[]) as tag_ids,
  coalesce(files.attachment_count, 0)        as attachment_count
from public.transactions t
left join lateral (
  select
    coalesce(sum(e.amount_minor)      filter (where e.side = 'debit'), 0)::bigint as debit_minor,
    coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0)::bigint as base_debit_minor,
    count(*)::int as line_count
  from public.transaction_entries e
  where e.transaction_id = t.id
) totals on true
left join lateral (
  select a.id as account_id, a.name as account_name
  from public.transaction_entries e
  join public.accounts a on a.id = e.account_id
  where e.transaction_id = t.id and e.side = 'credit'
  order by e.base_amount_minor desc, e.entry_index
  limit 1
) credit_side on true
left join lateral (
  select a.id as account_id, a.name as account_name
  from public.transaction_entries e
  join public.accounts a on a.id = e.account_id
  where e.transaction_id = t.id and e.side = 'debit'
  order by e.base_amount_minor desc, e.entry_index
  limit 1
) debit_side on true
left join lateral (
  select
    array_agg(tg.name order by tg.name) as tags,
    array_agg(tg.id   order by tg.name) as tag_ids
  from public.transaction_tags tt
  join public.tags tg on tg.id = tt.tag_id
  where tt.transaction_id = t.id
) tag_list on true
left join lateral (
  select count(*)::int as attachment_count
  from public.attachments at2
  where at2.entity_type = 'transaction' and at2.entity_id = t.id
) files on true
left join public.categories cat    on cat.id = t.category_id
left join public.counterparties cp on cp.id = t.counterparty_id
left join public.profiles author    on author.id = t.created_by
where t.deleted_at is null;

comment on view public.transaction_summaries is
  'One row per transaction with its amount and counter-accounts derived from '
  'the ledger. security_invoker, so RLS still applies.';

grant select on public.transaction_summaries to authenticated;

-- ---------------------------------------------------------------------------
-- Server-side search, filtering, sorting and pagination
-- ---------------------------------------------------------------------------
-- Returns the page of rows plus the unpaginated total, so the client never
-- loads the dataset to count it.
create or replace function public.search_transactions(
  p_organization_id  uuid,
  p_search           text    default null,
  p_from_date        date    default null,
  p_to_date          date    default null,
  p_types            public.transaction_type[]   default null,
  p_statuses         public.transaction_status[] default null,
  p_category_ids     uuid[]  default null,
  p_account_ids      uuid[]  default null,
  p_counterparty_ids uuid[]  default null,
  p_created_by_ids   uuid[]  default null,
  p_tag_ids          uuid[]  default null,
  p_min_amount_minor bigint  default null,
  p_max_amount_minor bigint  default null,
  p_sort             text    default 'transaction_date',
  p_direction        text    default 'desc',
  p_limit            int     default 50,
  p_offset           int     default 0
)
returns table (
  id                 uuid,
  transaction_date   date,
  type               public.transaction_type,
  status             public.transaction_status,
  description        text,
  reference          text,
  currency_code      char(3),
  amount_minor       bigint,
  base_amount_minor  bigint,
  category_name      text,
  counterparty_name  text,
  from_account_name  text,
  to_account_name    text,
  created_by_name    text,
  tags               text[],
  attachment_count   int,
  possible_duplicate boolean,
  reversed_by_transaction_id uuid,
  total_count        bigint
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_limit  int := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_sort   text := lower(coalesce(p_sort, 'transaction_date'));
  v_desc   boolean := lower(coalesce(p_direction, 'desc')) <> 'asc';
begin
  perform app.require_capability(p_organization_id, 'transactions.read');

  -- Whitelist the sort column. It is interpolated into an ORDER BY, so it must
  -- never come straight from the client.
  if v_sort not in ('transaction_date', 'amount', 'created_at', 'status', 'type') then
    v_sort := 'transaction_date';
  end if;

  return query
  with filtered as (
    select s.*
    from public.transaction_summaries s
    where s.organization_id = p_organization_id
      and (p_from_date is null or s.transaction_date >= p_from_date)
      and (p_to_date   is null or s.transaction_date <= p_to_date)
      and (p_types      is null or s.type   = any (p_types))
      and (p_statuses   is null or s.status = any (p_statuses))
      and (p_category_ids     is null or s.category_id     = any (p_category_ids))
      and (p_counterparty_ids is null or s.counterparty_id = any (p_counterparty_ids))
      and (p_created_by_ids   is null or s.created_by      = any (p_created_by_ids))
      and (p_min_amount_minor is null or s.base_amount_minor >= p_min_amount_minor)
      and (p_max_amount_minor is null or s.base_amount_minor <= p_max_amount_minor)
      and (p_tag_ids is null or s.tag_ids && p_tag_ids)
      and (
        p_account_ids is null
        or exists (
          select 1 from public.transaction_entries e
          where e.transaction_id = s.id and e.account_id = any (p_account_ids)
        )
      )
      and (
        p_search is null
        or trim(p_search) = ''
        or s.description       ilike '%' || p_search || '%'
        or s.reference         ilike '%' || p_search || '%'
        or s.counterparty_name ilike '%' || p_search || '%'
        or s.category_name     ilike '%' || p_search || '%'
        or s.from_account_name ilike '%' || p_search || '%'
        or s.to_account_name   ilike '%' || p_search || '%'
      )
  )
  select
    f.id, f.transaction_date, f.type, f.status, f.description, f.reference,
    f.currency_code, f.amount_minor, f.base_amount_minor, f.category_name,
    f.counterparty_name, f.from_account_name, f.to_account_name,
    f.created_by_name, f.tags, f.attachment_count, f.possible_duplicate,
    f.reversed_by_transaction_id,
    count(*) over ()::bigint as total_count
  from filtered f
  order by
    case when v_desc then
      case v_sort
        when 'transaction_date' then to_char(f.transaction_date, 'YYYYMMDD')
        when 'amount'           then lpad(f.base_amount_minor::text, 20, '0')
        when 'created_at'       then to_char(f.created_at, 'YYYYMMDDHH24MISS')
        when 'status'           then f.status::text
        else f.type::text
      end
    end desc nulls last,
    case when not v_desc then
      case v_sort
        when 'transaction_date' then to_char(f.transaction_date, 'YYYYMMDD')
        when 'amount'           then lpad(f.base_amount_minor::text, 20, '0')
        when 'created_at'       then to_char(f.created_at, 'YYYYMMDDHH24MISS')
        when 'status'           then f.status::text
        else f.type::text
      end
    end asc nulls last,
    f.created_at desc, f.id desc
  limit v_limit offset v_offset;
end;
$$;

comment on function public.search_transactions is
  'Paginated transaction search. Returns total_count alongside each row so the '
  'client can render pagination without a second query or a full table load.';

-- ---------------------------------------------------------------------------
-- Revenue vs expenses, by month
-- ---------------------------------------------------------------------------
create or replace function public.report_monthly_series(
  p_organization_id uuid,
  p_months          int default 6,
  p_as_of_date      date default null
)
returns table (
  month         date,
  revenue_minor bigint,
  expense_minor bigint,
  net_minor     bigint
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_as_of  date := coalesce(p_as_of_date, app.org_today(p_organization_id));
  v_months int  := least(greatest(coalesce(p_months, 6), 1), 60);
  v_start  date;
begin
  perform app.require_capability(p_organization_id, 'reports.read');

  v_start := (date_trunc('month', v_as_of) - make_interval(months => v_months - 1))::date;

  return query
  with months as (
    select generate_series(v_start, date_trunc('month', v_as_of)::date, interval '1 month')::date as m
  ),
  movements as (
    select
      date_trunc('month', e.entry_date)::date as m,
      coalesce(sum(case when a.type = 'revenue'
                        then case when e.side = 'credit' then e.base_amount_minor
                                  else -e.base_amount_minor end
                   end), 0)::bigint as revenue,
      coalesce(sum(case when a.type = 'expense'
                        then case when e.side = 'debit' then e.base_amount_minor
                                  else -e.base_amount_minor end
                   end), 0)::bigint as expense
    from public.transaction_entries e
    join public.accounts a on a.id = e.account_id
    where e.organization_id = p_organization_id
      and e.posted_at is not null
      and e.entry_date >= v_start
      and e.entry_date <= v_as_of
      and a.type in ('revenue', 'expense')
    group by 1
  )
  select
    months.m,
    coalesce(movements.revenue, 0)::bigint,
    coalesce(movements.expense, 0)::bigint,
    (coalesce(movements.revenue, 0) - coalesce(movements.expense, 0))::bigint
  from months
  left join movements on movements.m = months.m
  order by months.m;
end;
$$;

comment on function public.report_monthly_series(uuid, int, date) is
  'Monthly revenue and expense totals for the dashboard chart. Months with no '
  'activity are returned as zeroes rather than omitted, so the chart keeps an '
  'even time axis.';

do $$
declare
  v_fn record;
begin
  for v_fn in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('search_transactions', 'report_monthly_series')
  loop
    execute format('revoke all on function %s from public, anon', v_fn.signature);
    execute format('grant execute on function %s to authenticated, service_role', v_fn.signature);
  end loop;
end;
$$;
