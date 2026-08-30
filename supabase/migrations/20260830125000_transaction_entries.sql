-- Ledger Suit — 11. Ledger entries (double-entry lines)
--
-- The single source of truth for every balance and every report.
--
-- One row = one side of a journal. `side` is an enum, so a line can never carry
-- both a debit and a credit. Amounts are positive integer minor units.

create table if not exists public.transaction_entries (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references public.organizations (id) on delete cascade,
  transaction_id    uuid not null,
  account_id        uuid not null,

  entry_index       smallint not null,
  side              public.entry_side not null,

  -- Amount in the transaction currency.
  amount_minor      bigint not null,
  currency_code     char(3) not null references public.currencies (code),

  -- Same amount converted to the organization base currency. Reports always
  -- aggregate this column so mixed-currency books still add up.
  base_amount_minor bigint not null,
  base_currency_code char(3) not null references public.currencies (code),
  exchange_rate     numeric(24,12) not null default 1,

  memo              text,

  -- Denormalised from the parent so ledger scans never need the join.
  entry_date        date not null,
  posted_at         timestamptz,

  -- Future analytical dimensions (branch, project, cost centre) without
  -- committing to a shape yet. See spec section 54.
  dimensions        jsonb not null default '{}'::jsonb,

  created_at        timestamptz not null default now(),

  constraint transaction_entries_amount_positive check (amount_minor > 0),
  constraint transaction_entries_base_amount_positive check (base_amount_minor > 0),
  constraint transaction_entries_rate_positive check (exchange_rate > 0),
  constraint transaction_entries_index_positive check (entry_index >= 0),
  constraint transaction_entries_memo_length check (
    memo is null or char_length(memo) <= 500
  ),
  constraint transaction_entries_unique_index unique (transaction_id, entry_index),
  constraint transaction_entries_id_org_unique unique (id, organization_id),

  constraint transaction_entries_transaction_same_org
    foreign key (transaction_id, organization_id)
    references public.transactions (id, organization_id) on delete cascade,
  constraint transaction_entries_account_same_org
    foreign key (account_id, organization_id)
    references public.accounts (id, organization_id) on delete restrict
);

comment on table public.transaction_entries is
  'Double-entry ledger. Source of truth for balances and reports. Rows attached '
  'to a posted transaction are immutable.';
comment on column public.transaction_entries.base_amount_minor is
  'amount_minor converted into the organization base currency at exchange_rate.';
comment on column public.transaction_entries.posted_at is
  'NULL while the parent transaction is a draft. Reports read posted rows only.';

create index if not exists transaction_entries_transaction_idx
  on public.transaction_entries (transaction_id);
create index if not exists transaction_entries_org_account_date_idx
  on public.transaction_entries (organization_id, account_id, entry_date)
  where posted_at is not null;
create index if not exists transaction_entries_org_date_idx
  on public.transaction_entries (organization_id, entry_date)
  where posted_at is not null;
create index if not exists transaction_entries_account_idx
  on public.transaction_entries (account_id);

alter table public.transaction_entries enable row level security;

-- ---------------------------------------------------------------------------
-- Derive denormalised columns from the parent transaction
-- ---------------------------------------------------------------------------
create or replace function app.fill_entry_from_transaction()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_txn public.transactions%rowtype;
  v_base_currency char(3);
  v_account public.accounts%rowtype;
begin
  select * into v_txn
  from public.transactions t
  where t.id = new.transaction_id
  for share;

  if not found then
    raise exception 'INVALID_TRANSACTION_STATE: parent transaction % not found',
      new.transaction_id
      using errcode = '23503';
  end if;

  if v_txn.organization_id <> new.organization_id then
    raise exception 'TENANT_ACCESS_DENIED: entry organization does not match transaction'
      using errcode = '42501';
  end if;

  -- Lines may only be attached while the journal is still open. The posting
  -- path stamps posted_at on the lines first and flips the transaction to
  -- posted last, precisely so that this stays an absolute rule.
  if v_txn.status in ('posted', 'reversed', 'voided') then
    raise exception
      'POSTED_RECORD_PROTECTED: cannot add ledger lines to a % transaction',
      v_txn.status
      using errcode = '42501';
  end if;

  select o.base_currency into v_base_currency
  from public.organizations o
  where o.id = new.organization_id;

  select * into v_account
  from public.accounts a
  where a.id = new.account_id;

  if v_account.is_archived then
    raise exception 'ACCOUNT_ARCHIVED: % cannot receive new postings', v_account.name
      using errcode = '23514';
  end if;

  new.entry_date          := v_txn.transaction_date;
  new.currency_code       := coalesce(new.currency_code, v_txn.currency_code);
  new.base_currency_code  := v_base_currency;
  new.exchange_rate       := coalesce(new.exchange_rate, v_txn.exchange_rate);
  new.base_amount_minor   := coalesce(
    new.base_amount_minor,
    app.convert_minor(new.amount_minor, new.currency_code, v_base_currency, new.exchange_rate)
  );
  new.posted_at           := case when v_txn.status = 'posted'
                                  then coalesce(v_txn.posted_at, now())
                                  else null end;

  return new;
end;
$$;

create trigger transaction_entries_fill
  before insert on public.transaction_entries
  for each row execute function app.fill_entry_from_transaction();

-- ---------------------------------------------------------------------------
-- Immutability of posted ledger lines
-- ---------------------------------------------------------------------------
create or replace function app.guard_transaction_entry()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status public.transaction_status;
begin
  select t.status into v_status
  from public.transactions t
  where t.id = old.transaction_id;

  -- The parent may already be gone during an ON DELETE CASCADE of a draft.
  --
  -- There is deliberately no escape hatch here: not a GUC, not a role check.
  -- The posting path stamps posted_at on the entries while the parent is still
  -- a draft and only then flips the transaction to posted, so it never needs
  -- to write to a frozen line.
  if v_status is not null and v_status in ('posted', 'reversed') then
    raise exception
      'POSTED_RECORD_PROTECTED: ledger entries of a posted transaction are immutable'
      using errcode = '42501';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create trigger transaction_entries_guard
  before update or delete on public.transaction_entries
  for each row execute function app.guard_transaction_entry();

-- ---------------------------------------------------------------------------
-- Balanced journal: SUM(debits) = SUM(credits)
-- ---------------------------------------------------------------------------
-- Deferred to commit time so a multi-statement posting can build its lines one
-- INSERT at a time and still be rejected as a whole if it does not balance.
create or replace function app.assert_transaction_balanced()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_txn_id uuid;
  v_status public.transaction_status;
  v_debit  bigint;
  v_credit bigint;
  v_base_debit  bigint;
  v_base_credit bigint;
  v_lines  int;
  v_currencies int;
begin
  -- NEW is unassigned on DELETE and OLD is unassigned on INSERT, so the row
  -- has to be picked by operation before any field is touched.
  if tg_table_name = 'transactions' then
    v_txn_id := new.id;
  elsif tg_op = 'DELETE' then
    v_txn_id := old.transaction_id;
  else
    v_txn_id := new.transaction_id;
  end if;

  select t.status into v_status
  from public.transactions t
  where t.id = v_txn_id;

  -- Deleted within the same transaction, or still a draft: nothing to enforce.
  if v_status is null or v_status not in ('posted', 'reversed') then
    return null;
  end if;

  select
    count(*),
    count(distinct e.currency_code),
    coalesce(sum(e.amount_minor)      filter (where e.side = 'debit'), 0),
    coalesce(sum(e.amount_minor)      filter (where e.side = 'credit'), 0),
    coalesce(sum(e.base_amount_minor) filter (where e.side = 'debit'), 0),
    coalesce(sum(e.base_amount_minor) filter (where e.side = 'credit'), 0)
  into v_lines, v_currencies, v_debit, v_credit, v_base_debit, v_base_credit
  from public.transaction_entries e
  where e.transaction_id = v_txn_id;

  if v_lines < 2 then
    raise exception
      'UNBALANCED_JOURNAL: transaction % has % ledger line(s); at least 2 are required',
      v_txn_id, v_lines
      using errcode = '23514';
  end if;

  -- Transaction-currency totals are only comparable when every line is in the
  -- same currency. A cross-currency journal balances in the base currency,
  -- which is the book the reports are drawn from.
  if v_currencies = 1 and v_debit <> v_credit then
    raise exception
      'UNBALANCED_JOURNAL: transaction % debits (%) <> credits (%)',
      v_txn_id, v_debit, v_credit
      using errcode = '23514';
  end if;

  if v_base_debit <> v_base_credit then
    raise exception
      'UNBALANCED_JOURNAL: transaction % base-currency debits (%) <> credits (%)',
      v_txn_id, v_base_debit, v_base_credit
      using errcode = '23514';
  end if;

  return null;
end;
$$;

comment on function app.assert_transaction_balanced() is
  'Deferred constraint trigger. A posted transaction must balance in both the '
  'transaction currency and the base currency, in every path that reaches the '
  'database — RPC, service role or psql.';

create constraint trigger transaction_entries_balanced
  after insert or update or delete on public.transaction_entries
  deferrable initially deferred
  for each row execute function app.assert_transaction_balanced();

create constraint trigger transactions_balanced
  after insert or update on public.transactions
  deferrable initially deferred
  for each row execute function app.assert_transaction_balanced();

-- Now that the ledger exists, the account guard (which counts ledger history)
-- can be attached.
create trigger accounts_guard
  before update or delete on public.accounts
  for each row execute function app.guard_account_changes();
