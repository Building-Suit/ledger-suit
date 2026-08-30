-- Ledger Suit — 14. Purpose-built transaction flows
--
-- These are the functions the product UI calls. Each one takes the vocabulary a
-- non-accountant uses ("I paid rent from CIB") and derives the double-entry
-- journal itself. The user never chooses a debit or a credit.
--
-- Every function delegates to app.create_and_post, so they all inherit the same
-- capability check, books-lock check, tenant validation, balance enforcement
-- and atomicity.

-- ---------------------------------------------------------------------------
-- Income:  Dr destination asset / Cr revenue
-- ---------------------------------------------------------------------------
create or replace function public.record_income(
  p_organization_id      uuid,
  p_amount_minor         bigint,
  p_destination_account_id uuid,
  p_category_id          uuid    default null,
  p_revenue_account_id   uuid    default null,
  p_transaction_date     date    default null,
  p_counterparty_id      uuid    default null,
  p_description          text    default null,
  p_reference            text    default null,
  p_currency_code        char(3) default null,
  p_exchange_rate        numeric default null,
  p_idempotency_key      text    default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_destination public.accounts%rowtype;
  v_revenue_id  uuid;
  v_currency    char(3);
  v_date        date;
begin
  perform app.require_capability(p_organization_id, 'transactions.create');

  v_date := coalesce(p_transaction_date, app.org_today(p_organization_id));
  v_destination := app.require_account(
    p_organization_id, p_destination_account_id,
    array['asset']::public.account_type[], 'destination account'
  );

  v_revenue_id := coalesce(
    p_revenue_account_id,
    app.category_account(p_organization_id, p_category_id)
  );
  perform app.require_account(
    p_organization_id, v_revenue_id,
    array['revenue']::public.account_type[], 'revenue account'
  );

  v_currency := coalesce(p_currency_code, v_destination.currency);

  return app.create_and_post(
    p_organization_id  => p_organization_id,
    p_type             => 'income',
    p_transaction_date => v_date,
    p_lines            => jsonb_build_array(
      jsonb_build_object('account_id', p_destination_account_id, 'side', 'debit',
                         'amount_minor', p_amount_minor),
      jsonb_build_object('account_id', v_revenue_id, 'side', 'credit',
                         'amount_minor', p_amount_minor)
    ),
    p_currency_code    => v_currency,
    p_exchange_rate    => p_exchange_rate,
    p_description      => p_description,
    p_reference        => p_reference,
    p_counterparty_id  => p_counterparty_id,
    p_category_id      => p_category_id,
    p_idempotency_key  => p_idempotency_key,
    p_fingerprint      => app.transaction_fingerprint(
      p_organization_id, v_date, p_amount_minor, p_destination_account_id,
      p_reference, p_counterparty_id, p_description
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Expense:  Dr expense / Cr source asset (or credit-card liability)
-- ---------------------------------------------------------------------------
create or replace function public.record_expense(
  p_organization_id     uuid,
  p_amount_minor        bigint,
  p_source_account_id   uuid,
  p_category_id         uuid    default null,
  p_expense_account_id  uuid    default null,
  p_transaction_date    date    default null,
  p_counterparty_id     uuid    default null,
  p_description         text    default null,
  p_reference           text    default null,
  p_currency_code       char(3) default null,
  p_exchange_rate       numeric default null,
  p_idempotency_key     text    default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source     public.accounts%rowtype;
  v_expense_id uuid;
  v_currency   char(3);
  v_date       date;
begin
  perform app.require_capability(p_organization_id, 'transactions.create');

  v_date := coalesce(p_transaction_date, app.org_today(p_organization_id));

  -- Paying by credit card is a liability increase, not an asset decrease, so
  -- both account types are legitimate funding sources.
  v_source := app.require_account(
    p_organization_id, p_source_account_id,
    array['asset', 'liability']::public.account_type[], 'source account'
  );

  v_expense_id := coalesce(
    p_expense_account_id,
    app.category_account(p_organization_id, p_category_id)
  );
  perform app.require_account(
    p_organization_id, v_expense_id,
    array['expense']::public.account_type[], 'expense account'
  );

  v_currency := coalesce(p_currency_code, v_source.currency);

  return app.create_and_post(
    p_organization_id  => p_organization_id,
    p_type             => 'expense',
    p_transaction_date => v_date,
    p_lines            => jsonb_build_array(
      jsonb_build_object('account_id', v_expense_id, 'side', 'debit',
                         'amount_minor', p_amount_minor),
      jsonb_build_object('account_id', p_source_account_id, 'side', 'credit',
                         'amount_minor', p_amount_minor)
    ),
    p_currency_code    => v_currency,
    p_exchange_rate    => p_exchange_rate,
    p_description      => p_description,
    p_reference        => p_reference,
    p_counterparty_id  => p_counterparty_id,
    p_category_id      => p_category_id,
    p_idempotency_key  => p_idempotency_key,
    p_fingerprint      => app.transaction_fingerprint(
      p_organization_id, v_date, p_amount_minor, p_source_account_id,
      p_reference, p_counterparty_id, p_description
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Transfer:  Dr destination asset / Cr source asset  (+ optional fee)
-- ---------------------------------------------------------------------------
create or replace function public.record_transfer(
  p_organization_id         uuid,
  p_amount_minor            bigint,
  p_from_account_id         uuid,
  p_to_account_id           uuid,
  p_transaction_date        date    default null,
  p_destination_amount_minor bigint default null,
  p_fee_minor               bigint  default 0,
  p_fee_account_id          uuid    default null,
  p_description             text    default null,
  p_reference               text    default null,
  p_exchange_rate           numeric default null,
  p_destination_exchange_rate numeric default null,
  p_idempotency_key         text    default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from    public.accounts%rowtype;
  v_to      public.accounts%rowtype;
  v_fee_id  uuid;
  v_lines   jsonb;
  v_date    date;
  v_dest_amount bigint;
begin
  perform app.require_capability(p_organization_id, 'transactions.create');

  if p_from_account_id = p_to_account_id then
    raise exception 'INVALID_TRANSFER: source and destination must differ'
      using errcode = '22023';
  end if;

  v_date := coalesce(p_transaction_date, app.org_today(p_organization_id));
  v_from := app.require_account(p_organization_id, p_from_account_id,
              array['asset', 'liability']::public.account_type[], 'source account');
  v_to   := app.require_account(p_organization_id, p_to_account_id,
              array['asset', 'liability']::public.account_type[], 'destination account');

  if v_from.currency <> v_to.currency and p_destination_amount_minor is null then
    raise exception
      'INVALID_TRANSFER: a cross-currency transfer (% to %) needs an explicit '
      'destination amount', v_from.currency, v_to.currency
      using errcode = '22023';
  end if;

  v_dest_amount := coalesce(p_destination_amount_minor, p_amount_minor);

  -- A transfer moves value between two accounts the business already owns. It
  -- must not create revenue or expense — only an explicit fee does that.
  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_id', p_to_account_id, 'side', 'debit',
      'amount_minor', v_dest_amount,
      'currency_code', v_to.currency,
      'exchange_rate', coalesce(p_destination_exchange_rate, p_exchange_rate)
    ),
    jsonb_build_object(
      'account_id', p_from_account_id, 'side', 'credit',
      'amount_minor', p_amount_minor,
      'currency_code', v_from.currency,
      'exchange_rate', p_exchange_rate
    )
  );

  if coalesce(p_fee_minor, 0) > 0 then
    v_fee_id := coalesce(p_fee_account_id, app.system_account(p_organization_id, 'bank_fees'));
    perform app.require_account(p_organization_id, v_fee_id,
      array['expense']::public.account_type[], 'fee account');

    v_lines := v_lines
      || jsonb_build_object('account_id', v_fee_id, 'side', 'debit',
                            'amount_minor', p_fee_minor,
                            'currency_code', v_from.currency,
                            'exchange_rate', p_exchange_rate)
      || jsonb_build_object('account_id', p_from_account_id, 'side', 'credit',
                            'amount_minor', p_fee_minor,
                            'currency_code', v_from.currency,
                            'exchange_rate', p_exchange_rate);
  end if;

  return app.create_and_post(
    p_organization_id  => p_organization_id,
    p_type             => 'transfer',
    p_transaction_date => v_date,
    p_lines            => v_lines,
    p_currency_code    => v_from.currency,
    p_exchange_rate    => p_exchange_rate,
    p_description      => p_description,
    p_reference        => p_reference,
    p_idempotency_key  => p_idempotency_key
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Asset purchase:  Dr asset / Cr payment account
-- ---------------------------------------------------------------------------
create or replace function public.record_asset_purchase(
  p_organization_id    uuid,
  p_amount_minor       bigint,
  p_asset_account_id   uuid,
  p_payment_account_id uuid,
  p_transaction_date   date    default null,
  p_counterparty_id    uuid    default null,
  p_description        text    default null,
  p_reference          text    default null,
  p_useful_life_months integer default null,
  p_exchange_rate      numeric default null,
  p_idempotency_key    text    default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment public.accounts%rowtype;
  v_date    date;
begin
  perform app.require_capability(p_organization_id, 'transactions.create');

  v_date := coalesce(p_transaction_date, app.org_today(p_organization_id));
  perform app.require_account(p_organization_id, p_asset_account_id,
    array['asset']::public.account_type[], 'asset account');
  v_payment := app.require_account(p_organization_id, p_payment_account_id,
    array['asset', 'liability']::public.account_type[], 'payment account');

  return app.create_and_post(
    p_organization_id  => p_organization_id,
    p_type             => 'asset_purchase',
    p_transaction_date => v_date,
    p_lines            => jsonb_build_array(
      jsonb_build_object('account_id', p_asset_account_id, 'side', 'debit',
                         'amount_minor', p_amount_minor),
      jsonb_build_object('account_id', p_payment_account_id, 'side', 'credit',
                         'amount_minor', p_amount_minor)
    ),
    p_currency_code    => v_payment.currency,
    p_exchange_rate    => p_exchange_rate,
    p_description      => p_description,
    p_reference        => p_reference,
    p_counterparty_id  => p_counterparty_id,
    p_idempotency_key  => p_idempotency_key,
    -- Depreciation is out of scope for now; capturing useful life here keeps
    -- the data available for when it lands, without a schema change.
    p_metadata         => jsonb_strip_nulls(
                            jsonb_build_object('useful_life_months', p_useful_life_months)
                          )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Liability created (loan received):  Dr asset / Cr liability
-- ---------------------------------------------------------------------------
create or replace function public.record_liability_created(
  p_organization_id      uuid,
  p_amount_minor         bigint,
  p_liability_account_id uuid,
  p_destination_account_id uuid,
  p_transaction_date     date    default null,
  p_counterparty_id      uuid    default null,
  p_due_date             date    default null,
  p_description          text    default null,
  p_reference            text    default null,
  p_exchange_rate        numeric default null,
  p_idempotency_key      text    default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_destination public.accounts%rowtype;
  v_date        date;
begin
  perform app.require_capability(p_organization_id, 'transactions.create');

  v_date := coalesce(p_transaction_date, app.org_today(p_organization_id));
  perform app.require_account(p_organization_id, p_liability_account_id,
    array['liability']::public.account_type[], 'liability account');
  v_destination := app.require_account(p_organization_id, p_destination_account_id,
    array['asset']::public.account_type[], 'destination account');

  return app.create_and_post(
    p_organization_id  => p_organization_id,
    p_type             => 'liability_created',
    p_transaction_date => v_date,
    p_lines            => jsonb_build_array(
      jsonb_build_object('account_id', p_destination_account_id, 'side', 'debit',
                         'amount_minor', p_amount_minor),
      jsonb_build_object('account_id', p_liability_account_id, 'side', 'credit',
                         'amount_minor', p_amount_minor)
    ),
    p_currency_code    => v_destination.currency,
    p_exchange_rate    => p_exchange_rate,
    p_description      => p_description,
    p_reference        => p_reference,
    p_counterparty_id  => p_counterparty_id,
    p_idempotency_key  => p_idempotency_key,
    p_metadata         => jsonb_strip_nulls(jsonb_build_object('due_date', p_due_date))
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Liability payment:  Dr liability (principal) + Dr interest + Dr fees / Cr asset
-- ---------------------------------------------------------------------------
create or replace function public.record_liability_payment(
  p_organization_id      uuid,
  p_liability_account_id uuid,
  p_payment_account_id   uuid,
  p_principal_minor      bigint,
  p_interest_minor       bigint  default 0,
  p_fees_minor           bigint  default 0,
  p_transaction_date     date    default null,
  p_interest_account_id  uuid    default null,
  p_fee_account_id       uuid    default null,
  p_counterparty_id      uuid    default null,
  p_description          text    default null,
  p_reference            text    default null,
  p_exchange_rate        numeric default null,
  p_idempotency_key      text    default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment  public.accounts%rowtype;
  v_lines    jsonb := '[]'::jsonb;
  v_total    bigint;
  v_interest uuid;
  v_fees     uuid;
  v_date     date;
begin
  perform app.require_capability(p_organization_id, 'transactions.create');

  v_date := coalesce(p_transaction_date, app.org_today(p_organization_id));

  if coalesce(p_principal_minor, 0) < 0
     or coalesce(p_interest_minor, 0) < 0
     or coalesce(p_fees_minor, 0) < 0 then
    raise exception 'INVALID_AMOUNT: principal, interest and fees cannot be negative'
      using errcode = '22023';
  end if;

  v_total := coalesce(p_principal_minor, 0) + coalesce(p_interest_minor, 0)
             + coalesce(p_fees_minor, 0);
  if v_total <= 0 then
    raise exception 'INVALID_AMOUNT: a payment must be greater than zero'
      using errcode = '22023';
  end if;

  perform app.require_account(p_organization_id, p_liability_account_id,
    array['liability']::public.account_type[], 'liability account');
  v_payment := app.require_account(p_organization_id, p_payment_account_id,
    array['asset']::public.account_type[], 'payment account');

  if coalesce(p_principal_minor, 0) > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', p_liability_account_id, 'side', 'debit',
      'amount_minor', p_principal_minor, 'memo', 'Principal');
  end if;

  if coalesce(p_interest_minor, 0) > 0 then
    v_interest := coalesce(p_interest_account_id,
                           app.system_account(p_organization_id, 'interest_expense'));
    perform app.require_account(p_organization_id, v_interest,
      array['expense']::public.account_type[], 'interest account');
    v_lines := v_lines || jsonb_build_object(
      'account_id', v_interest, 'side', 'debit',
      'amount_minor', p_interest_minor, 'memo', 'Interest');
  end if;

  if coalesce(p_fees_minor, 0) > 0 then
    v_fees := coalesce(p_fee_account_id, app.system_account(p_organization_id, 'bank_fees'));
    perform app.require_account(p_organization_id, v_fees,
      array['expense']::public.account_type[], 'fee account');
    v_lines := v_lines || jsonb_build_object(
      'account_id', v_fees, 'side', 'debit',
      'amount_minor', p_fees_minor, 'memo', 'Fees');
  end if;

  v_lines := v_lines || jsonb_build_object(
    'account_id', p_payment_account_id, 'side', 'credit', 'amount_minor', v_total);

  return app.create_and_post(
    p_organization_id  => p_organization_id,
    p_type             => 'liability_payment',
    p_transaction_date => v_date,
    p_lines            => v_lines,
    p_currency_code    => v_payment.currency,
    p_exchange_rate    => p_exchange_rate,
    p_description      => p_description,
    p_reference        => p_reference,
    p_counterparty_id  => p_counterparty_id,
    p_idempotency_key  => p_idempotency_key
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Owner contribution:  Dr asset / Cr equity
-- ---------------------------------------------------------------------------
create or replace function public.record_owner_contribution(
  p_organization_id        uuid,
  p_amount_minor           bigint,
  p_destination_account_id uuid,
  p_equity_account_id      uuid    default null,
  p_transaction_date       date    default null,
  p_description            text    default null,
  p_reference              text    default null,
  p_exchange_rate          numeric default null,
  p_idempotency_key        text    default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_destination public.accounts%rowtype;
  v_equity      uuid;
  v_date        date;
begin
  perform app.require_capability(p_organization_id, 'transactions.create');

  v_date := coalesce(p_transaction_date, app.org_today(p_organization_id));
  v_destination := app.require_account(p_organization_id, p_destination_account_id,
    array['asset']::public.account_type[], 'destination account');
  v_equity := coalesce(p_equity_account_id,
                       app.system_account(p_organization_id, 'owner_capital'));
  perform app.require_account(p_organization_id, v_equity,
    array['equity']::public.account_type[], 'equity account');

  return app.create_and_post(
    p_organization_id  => p_organization_id,
    p_type             => 'owner_contribution',
    p_transaction_date => v_date,
    p_lines            => jsonb_build_array(
      jsonb_build_object('account_id', p_destination_account_id, 'side', 'debit',
                         'amount_minor', p_amount_minor),
      jsonb_build_object('account_id', v_equity, 'side', 'credit',
                         'amount_minor', p_amount_minor)
    ),
    p_currency_code    => v_destination.currency,
    p_exchange_rate    => p_exchange_rate,
    p_description      => p_description,
    p_reference        => p_reference,
    p_idempotency_key  => p_idempotency_key
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Owner withdrawal:  Dr owner drawings / Cr asset
-- ---------------------------------------------------------------------------
create or replace function public.record_owner_withdrawal(
  p_organization_id     uuid,
  p_amount_minor        bigint,
  p_source_account_id   uuid,
  p_drawings_account_id uuid    default null,
  p_transaction_date    date    default null,
  p_description         text    default null,
  p_reference           text    default null,
  p_exchange_rate       numeric default null,
  p_idempotency_key     text    default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source   public.accounts%rowtype;
  v_drawings uuid;
  v_date     date;
begin
  perform app.require_capability(p_organization_id, 'transactions.create');

  v_date := coalesce(p_transaction_date, app.org_today(p_organization_id));
  v_source := app.require_account(p_organization_id, p_source_account_id,
    array['asset']::public.account_type[], 'source account');
  v_drawings := coalesce(p_drawings_account_id,
                         app.system_account(p_organization_id, 'owner_drawings'));
  perform app.require_account(p_organization_id, v_drawings,
    array['equity']::public.account_type[], 'drawings account');

  return app.create_and_post(
    p_organization_id  => p_organization_id,
    p_type             => 'owner_withdrawal',
    p_transaction_date => v_date,
    p_lines            => jsonb_build_array(
      jsonb_build_object('account_id', v_drawings, 'side', 'debit',
                         'amount_minor', p_amount_minor),
      jsonb_build_object('account_id', p_source_account_id, 'side', 'credit',
                         'amount_minor', p_amount_minor)
    ),
    p_currency_code    => v_source.currency,
    p_exchange_rate    => p_exchange_rate,
    p_description      => p_description,
    p_reference        => p_reference,
    p_idempotency_key  => p_idempotency_key
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Opening balances
-- ---------------------------------------------------------------------------
-- Takes the balances the business is carrying into the system and posts them as
-- one balanced journal against Opening Balance Equity. It never writes a
-- balance field — there isn't one.
--
-- p_balances shape:
--   [ { "account_id": uuid, "amount_minor": bigint }, ... ]
-- A positive amount means "this account holds this much on its normal side".
create or replace function public.post_opening_balance(
  p_organization_id uuid,
  p_as_of_date      date,
  p_balances        jsonb,
  p_notes           text default null,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item        jsonb;
  v_account     public.accounts%rowtype;
  v_lines       jsonb := '[]'::jsonb;
  v_debit_total bigint := 0;   -- base currency
  v_credit_total bigint := 0;  -- base currency
  v_diff        bigint;
  v_equity      uuid;
  v_amount      bigint;
  v_base_amount bigint;
  v_rate        numeric;
  v_base        char(3) := app.org_base_currency(p_organization_id);
begin
  perform app.require_capability(p_organization_id, 'transactions.adjust');
  perform app.assert_books_open(p_organization_id, p_as_of_date);

  if p_balances is null or jsonb_typeof(p_balances) <> 'array'
     or jsonb_array_length(p_balances) = 0 then
    raise exception 'INVALID_OPENING_BALANCE: at least one account balance is required'
      using errcode = '22023';
  end if;

  for v_item in select * from jsonb_array_elements(p_balances) loop
    v_account := app.require_account(
      p_organization_id, (v_item ->> 'account_id')::uuid, null, 'opening balance account'
    );

    v_amount := (v_item ->> 'amount_minor')::bigint;
    if coalesce(v_amount, 0) = 0 then
      continue;
    end if;

    v_rate := case when v_account.currency = v_base
                   then 1
                   else (v_item ->> 'exchange_rate')::numeric end;

    if v_account.currency <> v_base and coalesce(v_rate, 0) <= 0 then
      raise exception
        'INVALID_EXCHANGE_RATE: account % is in % and needs an exchange_rate to %',
        v_account.name, v_account.currency, v_base
        using errcode = '22023';
    end if;

    -- The balancing figure has to be computed in the base currency, otherwise a
    -- book holding both EGP and USD accounts would balance against a total that
    -- adds up two different units.
    v_base_amount := app.convert_minor(abs(v_amount), v_account.currency, v_base, v_rate);

    -- Post on the account's normal side; a negative figure flips it.
    if (v_account.normal_balance = 'debit') = (v_amount > 0) then
      v_lines := v_lines || jsonb_build_object(
        'account_id', v_account.id, 'side', 'debit',
        'amount_minor', abs(v_amount),
        'currency_code', v_account.currency,
        'exchange_rate', v_rate, 'memo', 'Opening balance');
      v_debit_total := v_debit_total + v_base_amount;
    else
      v_lines := v_lines || jsonb_build_object(
        'account_id', v_account.id, 'side', 'credit',
        'amount_minor', abs(v_amount),
        'currency_code', v_account.currency,
        'exchange_rate', v_rate, 'memo', 'Opening balance');
      v_credit_total := v_credit_total + v_base_amount;
    end if;
  end loop;

  if jsonb_array_length(v_lines) = 0 then
    raise exception 'INVALID_OPENING_BALANCE: every supplied balance was zero'
      using errcode = '22023';
  end if;

  -- The balancing figure goes to Opening Balance Equity, which is exactly what
  -- that account exists for.
  v_equity := app.system_account(p_organization_id, 'opening_balance_equity');
  v_diff := v_debit_total - v_credit_total;

  if v_diff <> 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', v_equity,
      'side', case when v_diff > 0 then 'credit' else 'debit' end,
      'amount_minor', abs(v_diff),
      'currency_code', v_base,
      'memo', 'Opening balance equity');
  end if;

  return app.create_and_post(
    p_organization_id  => p_organization_id,
    p_type             => 'opening_balance',
    p_transaction_date => p_as_of_date,
    p_lines            => v_lines,
    p_currency_code    => v_base,
    p_description      => 'Opening balances as of ' || p_as_of_date::text,
    p_memo             => p_notes,
    p_source           => 'opening_balance',
    p_idempotency_key  => p_idempotency_key,
    p_adjustment_reason => 'Opening balance entry'
  );
end;
$$;

comment on function public.post_opening_balance(uuid, date, jsonb, text, text) is
  'Posts opening balances as a balanced journal against Opening Balance Equity. '
  'Deliberately does not write any cached balance field.';
