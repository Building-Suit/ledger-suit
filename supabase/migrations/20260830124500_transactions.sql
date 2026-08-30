-- Ledger Suit — 10. Transactions
--
-- A transaction is the business-level financial event. Its accounting meaning
-- lives entirely in public.transaction_entries. Money is stored as integer
-- minor units (see public.currencies.minor_unit) — never floating point.

create table if not exists public.transactions (
  id                        uuid primary key default gen_random_uuid(),
  organization_id           uuid not null references public.organizations (id) on delete cascade,

  type                      public.transaction_type not null,
  status                    public.transaction_status not null default 'draft',
  source                    public.transaction_source not null default 'manual',

  -- When the event happened, in the organization's timezone.
  transaction_date          date not null,
  -- When it hit the books. Set at posting time; equal to transaction_date for
  -- ordinary flows but kept separate so back-dated postings stay auditable.
  posting_date              date,

  currency_code             char(3) not null references public.currencies (code),
  -- Rate from currency_code to the organization base currency at the time of
  -- the event. Exactly 1 when they are the same currency.
  exchange_rate             numeric(24,12) not null default 1,

  description               text,
  reference                 text,
  memo                      text,
  adjustment_reason         text,

  counterparty_id           uuid,
  category_id               uuid,

  -- Correction chain (section 25 of the spec).
  reverses_transaction_id     uuid,
  reversed_by_transaction_id  uuid,
  correction_of_transaction_id uuid,

  -- Duplicate detection (section 30). Flagged, never silently discarded.
  possible_duplicate        boolean not null default false,
  duplicate_of_transaction_id uuid,
  fingerprint               text,

  -- Idempotency for retried client posts, recurring runs and imports.
  idempotency_key           text,

  metadata                  jsonb not null default '{}'::jsonb,

  created_by                uuid references public.profiles (id) on delete set null,
  posted_by                 uuid references public.profiles (id) on delete set null,
  posted_at                 timestamptz,
  voided_by                 uuid references public.profiles (id) on delete set null,
  voided_at                 timestamptz,
  -- Soft delete is only ever reachable for drafts; see app.guard_transaction().
  deleted_at                timestamptz,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  constraint transactions_exchange_rate_positive check (exchange_rate > 0),
  constraint transactions_description_length check (
    description is null or char_length(description) <= 1000
  ),
  constraint transactions_reference_length check (
    reference is null or char_length(reference) <= 120
  ),
  constraint transactions_posted_fields check (
    (status = 'posted' and posted_at is not null and posting_date is not null)
    or (status <> 'posted')
  ),
  constraint transactions_reversed_fields check (
    (status = 'reversed' and reversed_by_transaction_id is not null)
    or (status <> 'reversed')
  ),
  constraint transactions_voided_fields check (
    (status = 'voided' and voided_at is not null) or (status <> 'voided')
  ),
  constraint transactions_adjustment_reason_required check (
    type <> 'adjustment'
    or status in ('draft', 'voided', 'failed')
    or (adjustment_reason is not null and char_length(trim(adjustment_reason)) > 0)
  ),
  constraint transactions_no_self_reversal check (
    reverses_transaction_id is distinct from id
    and reversed_by_transaction_id is distinct from id
    and correction_of_transaction_id is distinct from id
    and duplicate_of_transaction_id is distinct from id
  ),

  constraint transactions_id_org_unique unique (id, organization_id),

  -- Tenant-safe references. Every one of these is a composite key so a row can
  -- never point at another organization's data.
  constraint transactions_counterparty_same_org
    foreign key (counterparty_id, organization_id)
    references public.counterparties (id, organization_id) on delete restrict,
  constraint transactions_category_same_org
    foreign key (category_id, organization_id)
    references public.categories (id, organization_id) on delete restrict,
  constraint transactions_reverses_same_org
    foreign key (reverses_transaction_id, organization_id)
    references public.transactions (id, organization_id) on delete restrict,
  constraint transactions_reversed_by_same_org
    foreign key (reversed_by_transaction_id, organization_id)
    references public.transactions (id, organization_id) on delete restrict,
  constraint transactions_correction_of_same_org
    foreign key (correction_of_transaction_id, organization_id)
    references public.transactions (id, organization_id) on delete restrict,
  constraint transactions_duplicate_of_same_org
    foreign key (duplicate_of_transaction_id, organization_id)
    references public.transactions (id, organization_id) on delete restrict
);

comment on table public.transactions is
  'Business-level financial events. Posted rows are immutable in financial '
  'meaning; corrections go through reversal + correcting transaction.';
comment on column public.transactions.exchange_rate is
  'Transaction currency to organization base currency. Decimal, never float.';
comment on column public.transactions.fingerprint is
  'Stable hash of (date, amount, account, reference, counterparty) used for '
  'duplicate detection.';

create unique index if not exists transactions_org_idempotency_key
  on public.transactions (organization_id, idempotency_key)
  where idempotency_key is not null;

create unique index if not exists transactions_reverses_unique
  on public.transactions (reverses_transaction_id)
  where reverses_transaction_id is not null;

create index if not exists transactions_org_date_idx
  on public.transactions (organization_id, transaction_date desc, id desc);
create index if not exists transactions_org_status_idx
  on public.transactions (organization_id, status);
create index if not exists transactions_org_type_idx
  on public.transactions (organization_id, type);
create index if not exists transactions_org_counterparty_idx
  on public.transactions (organization_id, counterparty_id)
  where counterparty_id is not null;
create index if not exists transactions_org_category_idx
  on public.transactions (organization_id, category_id)
  where category_id is not null;
create index if not exists transactions_org_created_by_idx
  on public.transactions (organization_id, created_by);
create index if not exists transactions_org_fingerprint_idx
  on public.transactions (organization_id, fingerprint)
  where fingerprint is not null;
create index if not exists transactions_org_reference_idx
  on public.transactions (organization_id, lower(reference))
  where reference is not null;

-- Covering index for the reversal-chain lookups above (PostgreSQL does not
-- index foreign key columns automatically).
create index if not exists transactions_reversed_by_idx
  on public.transactions (reversed_by_transaction_id)
  where reversed_by_transaction_id is not null;
create index if not exists transactions_correction_of_idx
  on public.transactions (correction_of_transaction_id)
  where correction_of_transaction_id is not null;
create index if not exists transactions_duplicate_of_idx
  on public.transactions (duplicate_of_transaction_id)
  where duplicate_of_transaction_id is not null;

create trigger transactions_set_updated_at
  before update on public.transactions
  for each row execute function app.set_updated_at();

alter table public.transactions enable row level security;

-- ---------------------------------------------------------------------------
-- State machine and immutability
-- ---------------------------------------------------------------------------
create or replace function app.guard_transaction()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception
        'POSTED_RECORD_PROTECTED: only draft transactions can be deleted (status=%)',
        old.status
        using errcode = '42501';
    end if;
    return old;
  end if;

  if new.organization_id is distinct from old.organization_id then
    raise exception 'TENANT_KEY_IMMUTABLE: organization_id cannot be changed'
      using errcode = '42501';
  end if;

  -- Once posted, the financial meaning is frozen. The only mutations allowed
  -- are the bookkeeping columns the reversal flow needs, plus non-financial
  -- annotations (memo, metadata, duplicate flags).
  if old.status in ('posted', 'reversed', 'voided') then
    if new.type              is distinct from old.type
       or new.transaction_date is distinct from old.transaction_date
       or new.posting_date   is distinct from old.posting_date
       or new.currency_code  is distinct from old.currency_code
       or new.exchange_rate  is distinct from old.exchange_rate
       or new.category_id    is distinct from old.category_id
       or new.counterparty_id is distinct from old.counterparty_id
       or new.description    is distinct from old.description
       or new.reference      is distinct from old.reference
       or new.posted_at      is distinct from old.posted_at
       or new.posted_by      is distinct from old.posted_by
       or new.created_by     is distinct from old.created_by
       or new.reverses_transaction_id is distinct from old.reverses_transaction_id
       or new.deleted_at     is distinct from old.deleted_at then
      raise exception
        'POSTED_RECORD_PROTECTED: posted transactions cannot be edited in place; '
        'reverse and re-enter instead'
        using errcode = '42501';
    end if;

    -- posted -> reversed and posted -> voided are the only status moves left.
    if new.status <> old.status
       and not (old.status = 'posted' and new.status in ('reversed', 'voided')) then
      raise exception 'INVALID_TRANSACTION_STATE: % -> % is not allowed',
        old.status, new.status
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger transactions_guard
  before update or delete on public.transactions
  for each row execute function app.guard_transaction();
