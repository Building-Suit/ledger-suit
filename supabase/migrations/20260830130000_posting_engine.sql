-- Ledger Suit — 13. Posting engine
--
-- Every write that touches the ledger goes through this file. Direct
-- INSERT/UPDATE/DELETE on transactions and transaction_entries is revoked from
-- client roles in the RLS migration, so these functions are the only door.
--
-- Each function is SECURITY DEFINER because it must write to tables the caller
-- cannot write to directly. Every one of them therefore:
--   * pins search_path to ''
--   * resolves the caller from auth.uid(), never from an argument
--   * calls app.require_capability() before touching anything
--   * validates that every referenced record belongs to the same organization
--   * runs as a single atomic statement — a failed line rolls back the journal

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
create or replace function app.org_base_currency(p_organization_id uuid)
returns char(3)
language sql
stable
security definer
set search_path = ''
as $$
  select o.base_currency from public.organizations o where o.id = p_organization_id;
$$;

-- "Today" as the organization sees it. Never the browser's clock.
create or replace function app.org_today(p_organization_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (now() at time zone coalesce(
    (select o.timezone from public.organizations o where o.id = p_organization_id),
    'UTC'
  ))::date;
$$;

-- Loads an account and asserts tenant ownership, usability and (optionally) the
-- account type the caller expects.
create or replace function app.require_account(
  p_organization_id uuid,
  p_account_id      uuid,
  p_expected_types  public.account_type[] default null,
  p_label           text default 'account'
)
returns public.accounts
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_account public.accounts%rowtype;
begin
  if p_account_id is null then
    raise exception 'INVALID_ACCOUNT: % is required', p_label
      using errcode = '22023';
  end if;

  select * into v_account
  from public.accounts a
  where a.id = p_account_id;

  -- Same message whether the account is missing or owned by another tenant, so
  -- the response cannot be used to probe for foreign ids.
  if not found or v_account.organization_id <> p_organization_id then
    raise exception 'TENANT_ACCESS_DENIED: % does not belong to this organization', p_label
      using errcode = '42501';
  end if;

  if v_account.is_archived then
    raise exception 'ACCOUNT_ARCHIVED: % (%) cannot receive postings', v_account.name, p_label
      using errcode = '23514';
  end if;

  if p_expected_types is not null and not (v_account.type = any (p_expected_types)) then
    raise exception 'INVALID_ACCOUNT: % must be one of %, got %',
      p_label, p_expected_types, v_account.type
      using errcode = '22023';
  end if;

  return v_account;
end;
$$;

-- Resolves the ledger account behind a user-facing category.
create or replace function app.category_account(
  p_organization_id uuid,
  p_category_id     uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_category public.categories%rowtype;
begin
  if p_category_id is null then
    return null;
  end if;

  select * into v_category
  from public.categories c
  where c.id = p_category_id;

  if not found or v_category.organization_id <> p_organization_id then
    raise exception 'TENANT_ACCESS_DENIED: category does not belong to this organization'
      using errcode = '42501';
  end if;

  return v_category.default_account_id;
end;
$$;

create or replace function app.system_account(
  p_organization_id uuid,
  p_system_key      text
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select a.id into v_id
  from public.accounts a
  where a.organization_id = p_organization_id
    and a.system_key = p_system_key;

  if v_id is null then
    raise exception 'MISSING_SYSTEM_ACCOUNT: this organization has no % account',
      p_system_key
      using errcode = '22023';
  end if;

  return v_id;
end;
$$;

-- Duplicate-detection fingerprint (spec section 30). Deterministic, so the same
-- event entered twice collides regardless of who entered it.
create or replace function app.transaction_fingerprint(
  p_organization_id uuid,
  p_date            date,
  p_amount_minor    bigint,
  p_account_id      uuid,
  p_reference       text,
  p_counterparty_id uuid,
  p_description     text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(
    extensions.digest(
      concat_ws('|',
        p_organization_id::text,
        p_date::text,
        p_amount_minor::text,
        coalesce(p_account_id::text, ''),
        lower(coalesce(trim(p_reference), '')),
        coalesce(p_counterparty_id::text, ''),
        lower(coalesce(trim(p_description), ''))
      ),
      'sha256'
    ),
    'hex'
  );
$$;

-- ---------------------------------------------------------------------------
-- Journal construction
-- ---------------------------------------------------------------------------
-- Normalises the caller-supplied lines into a jsonb array carrying computed
-- base-currency amounts, and proves the journal balances before a single row is
-- written. Shape of each input line:
--   { "account_id": uuid, "side": "debit"|"credit",
--     "amount_minor": bigint, "currency_code": char(3)?,
--     "exchange_rate": numeric?, "memo": text? }
create or replace function app.normalize_journal_lines(
  p_organization_id uuid,
  p_lines           jsonb,
  p_currency        char(3),
  p_exchange_rate   numeric
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_base_currency char(3) := app.org_base_currency(p_organization_id);
  v_line          jsonb;
  v_out           jsonb := '[]'::jsonb;
  v_index         int := 0;
  v_currency      char(3);
  v_rate          numeric;
  v_amount        bigint;
  v_base_amount   bigint;
  v_side          text;
  v_debit         bigint := 0;
  v_credit        bigint := 0;
  v_base_debit    bigint := 0;
  v_base_credit   bigint := 0;
  v_diff          bigint;
  v_target_index  int;
  v_target        jsonb;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'UNBALANCED_JOURNAL: lines must be a JSON array'
      using errcode = '22023';
  end if;

  if jsonb_array_length(p_lines) < 2 then
    raise exception 'UNBALANCED_JOURNAL: a journal needs at least 2 lines, got %',
      jsonb_array_length(p_lines)
      using errcode = '23514';
  end if;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_side := lower(coalesce(v_line ->> 'side', ''));
    if v_side not in ('debit', 'credit') then
      raise exception 'UNBALANCED_JOURNAL: line % has side "%", expected debit or credit',
        v_index, v_side
        using errcode = '22023';
    end if;

    v_amount := (v_line ->> 'amount_minor')::bigint;
    if v_amount is null or v_amount <= 0 then
      raise exception 'INVALID_AMOUNT: line % amount must be a positive integer '
                      'in minor units', v_index
        using errcode = '22023';
    end if;

    v_currency := coalesce(v_line ->> 'currency_code', p_currency);
    v_rate     := coalesce((v_line ->> 'exchange_rate')::numeric, p_exchange_rate);

    if v_currency = v_base_currency then
      v_rate := 1;
    elsif v_rate is null or v_rate <= 0 then
      raise exception 'INVALID_EXCHANGE_RATE: line % is in % but no rate to % was given',
        v_index, v_currency, v_base_currency
        using errcode = '22023';
    end if;

    -- Tenant ownership of the account is proven here, before any write.
    perform app.require_account(
      p_organization_id,
      (v_line ->> 'account_id')::uuid,
      null,
      format('line %s account', v_index)
    );

    v_base_amount := app.convert_minor(v_amount, v_currency, v_base_currency, v_rate);

    if v_side = 'debit' then
      v_debit := v_debit + v_amount;
      v_base_debit := v_base_debit + v_base_amount;
    else
      v_credit := v_credit + v_amount;
      v_base_credit := v_base_credit + v_base_amount;
    end if;

    v_out := v_out || jsonb_build_object(
      'entry_index',       v_index,
      'account_id',        v_line ->> 'account_id',
      'side',              v_side,
      'amount_minor',      v_amount,
      'currency_code',     v_currency,
      'exchange_rate',     v_rate,
      'base_amount_minor', v_base_amount,
      'memo',              v_line ->> 'memo'
    );

    v_index := v_index + 1;
  end loop;

  -- Same-currency journals must balance exactly. No tolerance, no rounding.
  if (select count(distinct value ->> 'currency_code')
      from jsonb_array_elements(v_out)) = 1
     and v_debit <> v_credit then
    raise exception 'UNBALANCED_JOURNAL: debits (%) <> credits (%)', v_debit, v_credit
      using errcode = '23514';
  end if;

  -- Cross-currency journals are converted line by line, so the base totals can
  -- differ by a few minor units of pure rounding residual. That residual is
  -- absorbed by the largest line on the short side rather than being written
  -- off to a plug account — anything larger than the residual is a real
  -- imbalance and is refused.
  v_diff := v_base_debit - v_base_credit;
  if v_diff <> 0 then
    if abs(v_diff) > greatest(jsonb_array_length(v_out), 2) then
      raise exception
        'UNBALANCED_JOURNAL: base-currency debits (%) <> credits (%) by %; '
        'this is not a rounding residual',
        v_base_debit, v_base_credit, v_diff
        using errcode = '23514';
    end if;

    select (value ->> 'entry_index')::int into v_target_index
    from jsonb_array_elements(v_out)
    where value ->> 'side' = case when v_diff > 0 then 'credit' else 'debit' end
    order by (value ->> 'base_amount_minor')::bigint desc
    limit 1;

    v_target := v_out -> v_target_index;
    v_out := jsonb_set(
      v_out,
      array[v_target_index::text, 'base_amount_minor'],
      to_jsonb((v_target ->> 'base_amount_minor')::bigint + abs(v_diff))
    );
  end if;

  return v_out;
end;
$$;

-- ---------------------------------------------------------------------------
-- Draft creation
-- ---------------------------------------------------------------------------
create or replace function public.create_draft_transaction(
  p_organization_id   uuid,
  p_type              public.transaction_type,
  p_transaction_date  date,
  p_lines             jsonb,
  p_currency_code     char(3) default null,
  p_exchange_rate     numeric default null,
  p_description       text    default null,
  p_reference         text    default null,
  p_counterparty_id   uuid    default null,
  p_category_id       uuid    default null,
  p_memo              text    default null,
  p_adjustment_reason text    default null,
  p_source            public.transaction_source default 'manual',
  p_idempotency_key   text    default null,
  p_metadata          jsonb   default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_currency char(3);
  v_rate     numeric;
  v_lines    jsonb;
  v_txn_id   uuid;
  v_line     jsonb;
  v_existing uuid;
begin
  perform app.require_capability(p_organization_id, 'transactions.create');

  if p_idempotency_key is not null then
    select t.id into v_existing
    from public.transactions t
    where t.organization_id = p_organization_id
      and t.idempotency_key = p_idempotency_key;
    if v_existing is not null then
      return v_existing;
    end if;
  end if;

  v_currency := coalesce(p_currency_code, app.org_base_currency(p_organization_id));
  v_rate     := case when v_currency = app.org_base_currency(p_organization_id)
                     then 1 else p_exchange_rate end;

  v_lines := app.normalize_journal_lines(p_organization_id, p_lines, v_currency, v_rate);

  insert into public.transactions (
    organization_id, type, status, source, transaction_date, currency_code,
    exchange_rate, description, reference, memo, adjustment_reason,
    counterparty_id, category_id, idempotency_key, metadata, created_by
  )
  values (
    p_organization_id, p_type, 'draft', p_source, p_transaction_date, v_currency,
    coalesce(v_rate, 1), p_description, p_reference, p_memo, p_adjustment_reason,
    p_counterparty_id, p_category_id, p_idempotency_key,
    coalesce(p_metadata, '{}'::jsonb), auth.uid()
  )
  returning id into v_txn_id;

  for v_line in select * from jsonb_array_elements(v_lines) loop
    insert into public.transaction_entries (
      organization_id, transaction_id, account_id, entry_index, side,
      amount_minor, currency_code, base_amount_minor, exchange_rate, memo
    )
    values (
      p_organization_id,
      v_txn_id,
      (v_line ->> 'account_id')::uuid,
      (v_line ->> 'entry_index')::smallint,
      (v_line ->> 'side')::public.entry_side,
      (v_line ->> 'amount_minor')::bigint,
      (v_line ->> 'currency_code')::char(3),
      (v_line ->> 'base_amount_minor')::bigint,
      (v_line ->> 'exchange_rate')::numeric,
      v_line ->> 'memo'
    );
  end loop;

  perform app.write_audit(
    p_organization_id, 'transaction.created', 'transaction', v_txn_id,
    null, jsonb_build_object('type', p_type, 'status', 'draft')
  );

  return v_txn_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Posting a draft
-- ---------------------------------------------------------------------------
create or replace function public.post_transaction(p_transaction_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_txn   public.transactions%rowtype;
  v_now   timestamptz := now();
begin
  -- Row lock first: two clients racing to post the same draft must serialise
  -- here, and the loser then fails the status check below.
  select * into v_txn
  from public.transactions t
  where t.id = p_transaction_id
  for update;

  if not found then
    raise exception 'TENANT_ACCESS_DENIED: transaction not found'
      using errcode = '42501';
  end if;

  perform app.require_capability(v_txn.organization_id, 'transactions.post');
  perform app.assert_books_open(v_txn.organization_id, v_txn.transaction_date);

  if v_txn.type = 'adjustment' then
    perform app.require_capability(v_txn.organization_id, 'transactions.adjust');
  end if;

  if v_txn.status not in ('draft', 'scheduled', 'pending', 'pending_approval') then
    raise exception 'INVALID_TRANSACTION_STATE: cannot post a % transaction',
      v_txn.status
      using errcode = '23514';
  end if;

  if v_txn.deleted_at is not null then
    raise exception 'INVALID_TRANSACTION_STATE: cannot post a deleted draft'
      using errcode = '23514';
  end if;

  -- Stamp the lines while the parent is still open, then close the parent.
  -- After the UPDATE below the entries are permanently frozen.
  update public.transaction_entries e
  set posted_at = v_now
  where e.transaction_id = p_transaction_id;

  update public.transactions t
  set status       = 'posted',
      posted_at    = v_now,
      posted_by    = auth.uid(),
      posting_date = coalesce(t.posting_date, app.org_today(t.organization_id))
  where t.id = p_transaction_id;

  perform app.write_audit(
    v_txn.organization_id, 'transaction.posted', 'transaction', p_transaction_id,
    jsonb_build_object('status', v_txn.status),
    jsonb_build_object('status', 'posted')
  );

  return p_transaction_id;
end;
$$;

comment on function public.post_transaction(uuid) is
  'Posts an existing draft. Balanced-journal enforcement happens in the '
  'deferred constraint trigger, so a bad journal aborts the whole statement.';

-- ---------------------------------------------------------------------------
-- Create + post in one atomic call (the path the quick-add UI uses)
-- ---------------------------------------------------------------------------
create or replace function app.create_and_post(
  p_organization_id   uuid,
  p_type              public.transaction_type,
  p_transaction_date  date,
  p_lines             jsonb,
  p_currency_code     char(3) default null,
  p_exchange_rate     numeric default null,
  p_description       text    default null,
  p_reference         text    default null,
  p_counterparty_id   uuid    default null,
  p_category_id       uuid    default null,
  p_memo              text    default null,
  p_adjustment_reason text    default null,
  p_source            public.transaction_source default 'manual',
  p_idempotency_key   text    default null,
  p_metadata          jsonb   default '{}'::jsonb,
  p_fingerprint       text    default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_txn_id   uuid;
  v_existing uuid;
begin
  perform app.require_capability(p_organization_id, 'transactions.post');
  perform app.assert_books_open(p_organization_id, p_transaction_date);

  if p_idempotency_key is not null then
    select t.id into v_existing
    from public.transactions t
    where t.organization_id = p_organization_id
      and t.idempotency_key = p_idempotency_key;
    if v_existing is not null then
      return v_existing;
    end if;
  end if;

  v_txn_id := public.create_draft_transaction(
    p_organization_id   => p_organization_id,
    p_type              => p_type,
    p_transaction_date  => p_transaction_date,
    p_lines             => p_lines,
    p_currency_code     => p_currency_code,
    p_exchange_rate     => p_exchange_rate,
    p_description       => p_description,
    p_reference         => p_reference,
    p_counterparty_id   => p_counterparty_id,
    p_category_id       => p_category_id,
    p_memo              => p_memo,
    p_adjustment_reason => p_adjustment_reason,
    p_source            => p_source,
    p_idempotency_key   => p_idempotency_key,
    p_metadata          => p_metadata
  );

  if p_fingerprint is not null then
    update public.transactions t
    set fingerprint = p_fingerprint,
        possible_duplicate = exists (
          select 1 from public.transactions d
          where d.organization_id = p_organization_id
            and d.fingerprint = p_fingerprint
            and d.id <> t.id
            and d.status = 'posted'
        ),
        duplicate_of_transaction_id = (
          select d.id from public.transactions d
          where d.organization_id = p_organization_id
            and d.fingerprint = p_fingerprint
            and d.id <> t.id
            and d.status = 'posted'
          order by d.created_at
          limit 1
        )
    where t.id = v_txn_id;
  end if;

  perform public.post_transaction(v_txn_id);

  return v_txn_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Manual journal adjustment
-- ---------------------------------------------------------------------------
create or replace function public.create_adjustment(
  p_organization_id  uuid,
  p_transaction_date date,
  p_lines            jsonb,
  p_description      text,
  p_reason           text,
  p_currency_code    char(3) default null,
  p_exchange_rate    numeric default null,
  p_idempotency_key  text    default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_requires_approval boolean;
  v_txn_id uuid;
begin
  perform app.require_capability(p_organization_id, 'transactions.adjust');

  if p_description is null or char_length(trim(p_description)) = 0 then
    raise exception 'INVALID_ADJUSTMENT: a description is required'
      using errcode = '22023';
  end if;

  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'INVALID_ADJUSTMENT: an adjustment reason is required'
      using errcode = '22023';
  end if;

  select s.require_adjustment_approval into v_requires_approval
  from public.organization_settings s
  where s.organization_id = p_organization_id;

  if coalesce(v_requires_approval, false) then
    -- Leave it for an approver rather than posting it.
    v_txn_id := public.create_draft_transaction(
      p_organization_id   => p_organization_id,
      p_type              => 'adjustment',
      p_transaction_date  => p_transaction_date,
      p_lines             => p_lines,
      p_currency_code     => p_currency_code,
      p_exchange_rate     => p_exchange_rate,
      p_description       => p_description,
      p_adjustment_reason => p_reason,
      p_idempotency_key   => p_idempotency_key
    );

    update public.transactions set status = 'pending_approval' where id = v_txn_id;

    perform app.write_audit(
      p_organization_id, 'transaction.created', 'transaction', v_txn_id,
      null, jsonb_build_object('type', 'adjustment', 'status', 'pending_approval')
    );

    return v_txn_id;
  end if;

  return app.create_and_post(
    p_organization_id   => p_organization_id,
    p_type              => 'adjustment',
    p_transaction_date  => p_transaction_date,
    p_lines             => p_lines,
    p_currency_code     => p_currency_code,
    p_exchange_rate     => p_exchange_rate,
    p_description       => p_description,
    p_adjustment_reason => p_reason,
    p_idempotency_key   => p_idempotency_key
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Reversal
-- ---------------------------------------------------------------------------
create or replace function public.reverse_transaction(
  p_transaction_id   uuid,
  p_reason           text,
  p_reversal_date    date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_txn        public.transactions%rowtype;
  v_reversal   uuid;
  v_date       date;
  v_now        timestamptz := now();
  v_entry      record;
  v_index      smallint := 0;
begin
  select * into v_txn
  from public.transactions t
  where t.id = p_transaction_id
  for update;

  if not found then
    raise exception 'TENANT_ACCESS_DENIED: transaction not found'
      using errcode = '42501';
  end if;

  perform app.require_capability(v_txn.organization_id, 'transactions.reverse');

  if v_txn.status <> 'posted' then
    raise exception 'INVALID_TRANSACTION_STATE: only posted transactions can be reversed (status=%)',
      v_txn.status
      using errcode = '23514';
  end if;

  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'INVALID_ADJUSTMENT: a reversal reason is required'
      using errcode = '22023';
  end if;

  v_date := coalesce(p_reversal_date, app.org_today(v_txn.organization_id));
  perform app.assert_books_open(v_txn.organization_id, v_date);

  insert into public.transactions (
    organization_id, type, status, source, transaction_date, currency_code,
    exchange_rate, description, reference, adjustment_reason, counterparty_id,
    category_id, reverses_transaction_id, metadata, created_by
  )
  values (
    v_txn.organization_id, 'reversal', 'draft', 'reversal', v_date,
    v_txn.currency_code, v_txn.exchange_rate,
    'Reversal of ' || coalesce(nullif(v_txn.description, ''), v_txn.id::text),
    v_txn.reference, p_reason, v_txn.counterparty_id, v_txn.category_id,
    v_txn.id, jsonb_build_object('reverses', v_txn.id), auth.uid()
  )
  returning id into v_reversal;

  -- Mirror every line with the opposite side and identical amounts, so the two
  -- journals sum to exactly zero in both the transaction and base currency.
  for v_entry in
    select * from public.transaction_entries e
    where e.transaction_id = v_txn.id
    order by e.entry_index
  loop
    insert into public.transaction_entries (
      organization_id, transaction_id, account_id, entry_index, side,
      amount_minor, currency_code, base_amount_minor, exchange_rate, memo, dimensions
    )
    values (
      v_entry.organization_id,
      v_reversal,
      v_entry.account_id,
      v_index,
      case v_entry.side when 'debit' then 'credit'::public.entry_side
                        else 'debit'::public.entry_side end,
      v_entry.amount_minor,
      v_entry.currency_code,
      v_entry.base_amount_minor,
      v_entry.exchange_rate,
      'Reversal: ' || coalesce(v_entry.memo, ''),
      v_entry.dimensions
    );
    v_index := v_index + 1;
  end loop;

  update public.transaction_entries e set posted_at = v_now
  where e.transaction_id = v_reversal;

  update public.transactions t
  set status = 'posted', posted_at = v_now, posted_by = auth.uid(),
      posting_date = app.org_today(t.organization_id)
  where t.id = v_reversal;

  update public.transactions t
  set status = 'reversed', reversed_by_transaction_id = v_reversal
  where t.id = v_txn.id;

  perform app.write_audit(
    v_txn.organization_id, 'transaction.reversed', 'transaction', v_txn.id,
    jsonb_build_object('status', 'posted'),
    jsonb_build_object('status', 'reversed', 'reversal_id', v_reversal, 'reason', p_reason)
  );

  return v_reversal;
end;
$$;

-- ---------------------------------------------------------------------------
-- Voiding an unposted transaction
-- ---------------------------------------------------------------------------
create or replace function public.void_transaction(
  p_transaction_id uuid,
  p_reason         text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_txn public.transactions%rowtype;
begin
  select * into v_txn
  from public.transactions t
  where t.id = p_transaction_id
  for update;

  if not found then
    raise exception 'TENANT_ACCESS_DENIED: transaction not found'
      using errcode = '42501';
  end if;

  perform app.require_capability(v_txn.organization_id, 'transactions.void');

  if v_txn.status = 'posted' then
    raise exception
      'INVALID_TRANSACTION_STATE: a posted transaction must be reversed, not voided'
      using errcode = '23514';
  end if;

  if v_txn.status in ('voided', 'reversed') then
    return p_transaction_id;
  end if;

  -- Voiding preserves the record and its lines; it never deletes history.
  update public.transactions t
  set status = 'voided', voided_at = now(), voided_by = auth.uid(),
      metadata = t.metadata || jsonb_build_object('void_reason', p_reason)
  where t.id = p_transaction_id;

  perform app.write_audit(
    v_txn.organization_id, 'transaction.voided', 'transaction', p_transaction_id,
    jsonb_build_object('status', v_txn.status),
    jsonb_build_object('status', 'voided', 'reason', p_reason)
  );

  return p_transaction_id;
end;
$$;
