-- Ledger Suit — 23. Commitments
--
-- A commitment is a financial *intention*: rent due next month, an invoice a
-- customer owes. It is deliberately not part of the ledger — spec section 73
-- and 74 require that forecasting never contaminate posted reports. Nothing in
-- this file writes a ledger entry; settlement calls the existing posting RPCs,
-- which is the only way money reaches the books.

create type public.commitment_type as enum (
  'payable',
  'receivable',
  'scheduled_expense',
  'scheduled_income'
);

-- Lifecycle only. `due` and `overdue` are deliberately absent: they are a
-- function of today's date, and storing them would need a nightly job just to
-- keep rows honest. They are derived in public.commitment_states below.
create type public.commitment_status as enum (
  'draft',
  'upcoming',
  'partially_paid',
  'paid',
  'cancelled'
);

create table if not exists public.commitments (
  id                   uuid primary key default gen_random_uuid(),
  organization_id      uuid not null references public.organizations (id) on delete cascade,

  type                 public.commitment_type not null,
  status               public.commitment_status not null default 'upcoming',
  title                text not null,
  description          text,

  amount_minor         bigint not null,
  currency_code        char(3) not null references public.currencies (code),
  settled_amount_minor bigint not null default 0,

  due_date             date not null,
  -- Kept when a commitment is postponed so the original promise stays visible.
  original_due_date    date,

  linked_account_id    uuid,
  linked_category_id   uuid,
  counterparty_id      uuid,
  recurring_rule_id    uuid,

  -- When true, the scheduler may convert this into a posted transaction on the
  -- due date without a human confirming it (spec section 16).
  auto_convert         boolean not null default false,
  reminder_days_before smallint not null default 3
                         check (reminder_days_before between 0 and 90),

  notes                text,
  metadata             jsonb not null default '{}'::jsonb,

  created_by           uuid references public.profiles (id) on delete set null,
  cancelled_at         timestamptz,
  cancelled_reason     text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint commitments_title_length check (char_length(title) between 1 and 200),
  constraint commitments_amount_positive check (amount_minor > 0),
  constraint commitments_settled_non_negative check (settled_amount_minor >= 0),
  -- A commitment can never be settled for more than it promised.
  constraint commitments_not_oversettled check (settled_amount_minor <= amount_minor),
  constraint commitments_cancelled_fields check (
    (status = 'cancelled' and cancelled_at is not null)
    or (status <> 'cancelled')
  ),
  constraint commitments_paid_is_settled check (
    status <> 'paid' or settled_amount_minor = amount_minor
  ),

  constraint commitments_id_org_unique unique (id, organization_id),

  -- Tenant-safe references: every one is composite, so a commitment cannot
  -- point at another organization's account, category or counterparty.
  constraint commitments_account_same_org
    foreign key (linked_account_id, organization_id)
    references public.accounts (id, organization_id) on delete restrict,
  constraint commitments_category_same_org
    foreign key (linked_category_id, organization_id)
    references public.categories (id, organization_id) on delete restrict,
  constraint commitments_counterparty_same_org
    foreign key (counterparty_id, organization_id)
    references public.counterparties (id, organization_id) on delete restrict
);

comment on table public.commitments is
  'Future payables, receivables and scheduled events. Forecasting only — a '
  'commitment never appears in a posted report until it is settled, which '
  'creates a real transaction.';
comment on column public.commitments.settled_amount_minor is
  'Maintained by settle_commitment(); the authoritative detail is the rows in '
  'commitment_settlements.';

create index if not exists commitments_org_due_status_idx
  on public.commitments (organization_id, due_date, status);
create index if not exists commitments_org_open_idx
  on public.commitments (organization_id, due_date)
  where status in ('upcoming', 'partially_paid');
create index if not exists commitments_org_counterparty_idx
  on public.commitments (organization_id, counterparty_id)
  where counterparty_id is not null;
create index if not exists commitments_account_idx
  on public.commitments (linked_account_id) where linked_account_id is not null;
create index if not exists commitments_category_idx
  on public.commitments (linked_category_id) where linked_category_id is not null;
create index if not exists commitments_rule_idx
  on public.commitments (recurring_rule_id) where recurring_rule_id is not null;

create trigger commitments_set_updated_at
  before update on public.commitments
  for each row execute function app.set_updated_at();

alter table public.commitments enable row level security;

create or replace function app.guard_commitment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    -- A commitment that has moved money leaves an audit trail behind it.
    if exists (select 1 from public.commitment_settlements s
               where s.commitment_id = old.id) then
      raise exception
        'COMMITMENT_HAS_SETTLEMENTS: cancel it instead of deleting it'
        using errcode = '23503';
    end if;
    return old;
  end if;

  if new.organization_id is distinct from old.organization_id then
    raise exception 'TENANT_KEY_IMMUTABLE: organization_id cannot be changed'
      using errcode = '42501';
  end if;

  if old.status = 'cancelled' and new.status <> 'cancelled' then
    raise exception 'INVALID_COMMITMENT_STATE: a cancelled commitment cannot be reopened'
      using errcode = '23514';
  end if;

  -- Reducing the amount below what has already been settled would make the
  -- settlement history impossible to reconcile.
  if new.amount_minor < old.settled_amount_minor then
    raise exception
      'INVALID_COMMITMENT_AMOUNT: amount cannot drop below the % already settled',
      old.settled_amount_minor
      using errcode = '23514';
  end if;

  if new.status = 'cancelled' and new.cancelled_at is null then
    new.cancelled_at := now();
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Settlement history
-- ---------------------------------------------------------------------------
create table if not exists public.commitment_settlements (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  commitment_id   uuid not null,
  transaction_id  uuid not null,
  amount_minor    bigint not null,
  settled_on      date not null,
  created_by      uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),

  constraint commitment_settlements_amount_positive check (amount_minor > 0),
  -- One settlement row per posted transaction: replaying a settle call cannot
  -- double-count against the commitment.
  constraint commitment_settlements_transaction_unique unique (transaction_id),

  constraint commitment_settlements_commitment_same_org
    foreign key (commitment_id, organization_id)
    references public.commitments (id, organization_id) on delete cascade,
  constraint commitment_settlements_transaction_same_org
    foreign key (transaction_id, organization_id)
    references public.transactions (id, organization_id) on delete restrict
);

comment on table public.commitment_settlements is
  'Links each settlement to the transaction it posted. Append-only in practice: '
  'a mistaken settlement is corrected by reversing its transaction.';

create index if not exists commitment_settlements_commitment_idx
  on public.commitment_settlements (commitment_id, settled_on);
create index if not exists commitment_settlements_org_idx
  on public.commitment_settlements (organization_id, settled_on desc);

alter table public.commitment_settlements enable row level security;

create trigger commitments_guard
  before update or delete on public.commitments
  for each row execute function app.guard_commitment();

-- ---------------------------------------------------------------------------
-- Derived state
-- ---------------------------------------------------------------------------
-- `due` and `overdue` are computed against today in the organization's own
-- timezone, so a commitment is never wrongly overdue because the server sits in
-- a different one.
create or replace view public.commitment_states
with (security_invoker = true) as
select
  c.*,
  (c.amount_minor - c.settled_amount_minor) as outstanding_minor,
  o.timezone as organization_timezone,
  (now() at time zone o.timezone)::date as organization_today,
  (c.due_date - (now() at time zone o.timezone)::date) as days_until_due,
  case
    when c.status in ('paid', 'cancelled', 'draft') then c.status::text
    when c.due_date < (now() at time zone o.timezone)::date then 'overdue'
    when c.due_date = (now() at time zone o.timezone)::date then 'due'
    when c.status = 'partially_paid' then 'partially_paid'
    when c.due_date <= (now() at time zone o.timezone)::date + c.reminder_days_before
      then 'due_soon'
    else 'upcoming'
  end as display_status
from public.commitments c
join public.organizations o on o.id = c.organization_id;

comment on view public.commitment_states is
  'Commitments with due/overdue derived from the organization timezone. Nothing '
  'stores those states, so no scheduled job is needed to keep them true.';

grant select on public.commitment_states to authenticated;
