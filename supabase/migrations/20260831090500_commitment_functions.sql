-- Ledger Suit — 24. Commitment lifecycle
--
-- Settling a commitment does not invent its own bookkeeping: it calls the same
-- record_income / record_expense RPCs the manual flows use, so a settled
-- commitment produces exactly the journal a hand-entered one would.

comment on column public.commitments.linked_account_id is
  'The revenue or expense account this commitment maps to. NOT the account it '
  'will be paid from — that is chosen at settlement time, because a payable can '
  'be settled from cash one month and the bank the next.';

-- ---------------------------------------------------------------------------
-- Create
-- ---------------------------------------------------------------------------
create or replace function public.create_commitment(
  p_organization_id      uuid,
  p_type                 public.commitment_type,
  p_title                text,
  p_amount_minor         bigint,
  p_due_date             date,
  p_currency_code        char(3) default null,
  p_linked_category_id   uuid    default null,
  p_linked_account_id    uuid    default null,
  p_counterparty_id      uuid    default null,
  p_description          text    default null,
  p_notes                text    default null,
  p_auto_convert         boolean default false,
  p_reminder_days_before smallint default 3
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform app.require_capability(p_organization_id, 'commitments.create');

  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'INVALID_AMOUNT: a commitment must be for more than zero'
      using errcode = '22023';
  end if;

  if p_title is null or char_length(trim(p_title)) = 0 then
    raise exception 'INVALID_INPUT: a title is required'
      using errcode = '22023';
  end if;

  -- Validate tenant ownership before writing, so the error names the field
  -- rather than surfacing a foreign key violation.
  if p_linked_account_id is not null then
    perform app.require_account(p_organization_id, p_linked_account_id, null, 'linked account');
  end if;

  if p_linked_category_id is not null then
    perform app.category_account(p_organization_id, p_linked_category_id);
  end if;

  insert into public.commitments (
    organization_id, type, title, description, amount_minor, currency_code,
    due_date, original_due_date, linked_category_id, linked_account_id,
    counterparty_id, notes, auto_convert, reminder_days_before, created_by
  )
  values (
    p_organization_id, p_type, trim(p_title), p_description, p_amount_minor,
    coalesce(p_currency_code, app.org_base_currency(p_organization_id)),
    p_due_date, p_due_date, p_linked_category_id, p_linked_account_id,
    p_counterparty_id, p_notes, coalesce(p_auto_convert, false),
    coalesce(p_reminder_days_before, 3::smallint), auth.uid()
  )
  returning id into v_id;

  perform app.write_audit(
    p_organization_id, 'commitment.created', 'commitment', v_id,
    null, jsonb_build_object('type', p_type, 'amount_minor', p_amount_minor,
                             'due_date', p_due_date)
  );

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Settle (fully or partially)
-- ---------------------------------------------------------------------------
create or replace function public.settle_commitment(
  p_commitment_id      uuid,
  p_payment_account_id uuid,
  p_amount_minor       bigint default null,
  p_settled_on         date    default null,
  p_description        text    default null,
  p_reference          text    default null,
  p_idempotency_key    text    default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_commitment  public.commitments%rowtype;
  v_outstanding bigint;
  v_amount      bigint;
  v_date        date;
  v_txn_id      uuid;
  v_account     uuid;
  v_key         text;
  v_new_settled bigint;
begin
  -- Row lock first: two people settling the same commitment at once must
  -- serialise, or both could pass the outstanding-amount check.
  select * into v_commitment
  from public.commitments c
  where c.id = p_commitment_id
  for update;

  if not found then
    raise exception 'TENANT_ACCESS_DENIED: commitment not found'
      using errcode = '42501';
  end if;

  perform app.require_capability(v_commitment.organization_id, 'commitments.settle');

  if v_commitment.status = 'cancelled' then
    raise exception 'INVALID_COMMITMENT_STATE: this commitment was cancelled'
      using errcode = '23514';
  end if;

  if v_commitment.status = 'paid' then
    raise exception 'INVALID_COMMITMENT_STATE: this commitment is already settled'
      using errcode = '23514';
  end if;

  v_outstanding := v_commitment.amount_minor - v_commitment.settled_amount_minor;
  v_amount := coalesce(p_amount_minor, v_outstanding);
  v_date := coalesce(p_settled_on, app.org_today(v_commitment.organization_id));

  if v_amount <= 0 then
    raise exception 'INVALID_AMOUNT: settlement must be greater than zero'
      using errcode = '22023';
  end if;

  if v_amount > v_outstanding then
    raise exception
      'INVALID_AMOUNT: settlement of % exceeds the % still outstanding',
      v_amount, v_outstanding
      using errcode = '22023';
  end if;

  -- Deterministic default so a retried call reuses the same posting instead of
  -- creating a second one. Includes the amount and date, so a genuine second
  -- part-payment of the same size on a different day still posts.
  v_key := coalesce(
    p_idempotency_key,
    'commitment:' || p_commitment_id::text || ':' || v_date::text || ':' || v_amount::text
  );

  v_account := v_commitment.linked_account_id;

  if v_commitment.type in ('payable', 'scheduled_expense') then
    v_txn_id := public.record_expense(
      p_organization_id    => v_commitment.organization_id,
      p_amount_minor       => v_amount,
      p_source_account_id  => p_payment_account_id,
      p_category_id        => v_commitment.linked_category_id,
      p_expense_account_id => v_account,
      p_transaction_date   => v_date,
      p_counterparty_id    => v_commitment.counterparty_id,
      p_description        => coalesce(p_description, v_commitment.title),
      p_reference          => p_reference,
      p_idempotency_key    => v_key
    );
  else
    v_txn_id := public.record_income(
      p_organization_id        => v_commitment.organization_id,
      p_amount_minor           => v_amount,
      p_destination_account_id => p_payment_account_id,
      p_category_id            => v_commitment.linked_category_id,
      p_revenue_account_id     => v_account,
      p_transaction_date       => v_date,
      p_counterparty_id        => v_commitment.counterparty_id,
      p_description            => coalesce(p_description, v_commitment.title),
      p_reference              => p_reference,
      p_idempotency_key        => v_key
    );
  end if;

  -- If the posting was a replay, the transaction already has a settlement row
  -- and this does nothing — the commitment is not double-credited.
  insert into public.commitment_settlements (
    organization_id, commitment_id, transaction_id, amount_minor, settled_on, created_by
  )
  values (
    v_commitment.organization_id, p_commitment_id, v_txn_id, v_amount, v_date, auth.uid()
  )
  on conflict (transaction_id) do nothing;

  -- Recomputed from the settlement rows rather than incremented, so the total
  -- can never drift from its own history.
  select coalesce(sum(s.amount_minor), 0) into v_new_settled
  from public.commitment_settlements s
  where s.commitment_id = p_commitment_id;

  update public.commitments c
  set settled_amount_minor = v_new_settled,
      status = case
        when v_new_settled >= c.amount_minor then 'paid'::public.commitment_status
        when v_new_settled > 0 then 'partially_paid'::public.commitment_status
        else c.status
      end
  where c.id = p_commitment_id;

  perform app.write_audit(
    v_commitment.organization_id, 'commitment.settled', 'commitment', p_commitment_id,
    jsonb_build_object('settled_amount_minor', v_commitment.settled_amount_minor),
    jsonb_build_object('settled_amount_minor', v_new_settled, 'transaction_id', v_txn_id)
  );

  return v_txn_id;
end;
$$;

comment on function public.settle_commitment(uuid, uuid, bigint, date, text, text, text) is
  'Posts a real transaction for the settled amount and links it. Partial '
  'settlement is supported; the running total is recomputed from '
  'commitment_settlements so it cannot drift.';

-- ---------------------------------------------------------------------------
-- Cancel and postpone
-- ---------------------------------------------------------------------------
create or replace function public.cancel_commitment(
  p_commitment_id uuid,
  p_reason        text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_commitment public.commitments%rowtype;
begin
  select * into v_commitment from public.commitments c
  where c.id = p_commitment_id for update;

  if not found then
    raise exception 'TENANT_ACCESS_DENIED: commitment not found'
      using errcode = '42501';
  end if;

  perform app.require_capability(v_commitment.organization_id, 'commitments.update');

  if v_commitment.status = 'paid' then
    raise exception
      'INVALID_COMMITMENT_STATE: a settled commitment cannot be cancelled; '
      'reverse its transaction instead'
      using errcode = '23514';
  end if;

  update public.commitments c
  set status = 'cancelled', cancelled_at = now(), cancelled_reason = p_reason
  where c.id = p_commitment_id;

  perform app.write_audit(
    v_commitment.organization_id, 'commitment.cancelled', 'commitment', p_commitment_id,
    jsonb_build_object('status', v_commitment.status),
    jsonb_build_object('status', 'cancelled', 'reason', p_reason)
  );

  return p_commitment_id;
end;
$$;

create or replace function public.postpone_commitment(
  p_commitment_id uuid,
  p_new_due_date  date,
  p_reason        text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_commitment public.commitments%rowtype;
begin
  select * into v_commitment from public.commitments c
  where c.id = p_commitment_id for update;

  if not found then
    raise exception 'TENANT_ACCESS_DENIED: commitment not found'
      using errcode = '42501';
  end if;

  perform app.require_capability(v_commitment.organization_id, 'commitments.update');

  if v_commitment.status in ('paid', 'cancelled') then
    raise exception 'INVALID_COMMITMENT_STATE: this commitment is closed'
      using errcode = '23514';
  end if;

  if p_new_due_date <= v_commitment.due_date then
    raise exception 'INVALID_DATE_RANGE: the new due date must be later than the current one'
      using errcode = '22023';
  end if;

  update public.commitments c
  set due_date = p_new_due_date,
      -- Keep the first promise so the delay stays visible in the audit trail.
      original_due_date = coalesce(c.original_due_date, c.due_date),
      metadata = c.metadata || jsonb_build_object(
        'postponed_from', c.due_date, 'postpone_reason', p_reason
      )
  where c.id = p_commitment_id;

  perform app.write_audit(
    v_commitment.organization_id, 'commitment.postponed', 'commitment', p_commitment_id,
    jsonb_build_object('due_date', v_commitment.due_date),
    jsonb_build_object('due_date', p_new_due_date, 'reason', p_reason)
  );

  return p_commitment_id;
end;
$$;
