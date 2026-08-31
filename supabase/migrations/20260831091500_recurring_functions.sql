-- Ledger Suit — 26. Recurring scheduler
--
-- run_recurring_schedule() is safe to call as often as you like, from anywhere,
-- concurrently. Everything it does is guarded by the unique constraint on
-- (rule_id, occurrence_date).

-- ---------------------------------------------------------------------------
-- Create a rule
-- ---------------------------------------------------------------------------
create or replace function public.create_recurring_rule(
  p_organization_id  uuid,
  p_name             text,
  p_transaction_type public.transaction_type,
  p_template         jsonb,
  p_frequency        public.recurrence_frequency,
  p_start_date       date,
  p_interval_count   integer default 1,
  p_end_date         date    default null,
  p_max_occurrences  integer default null,
  p_mode             public.recurring_mode default 'requires_confirmation'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform app.require_capability(p_organization_id, 'recurring.manage');

  if p_transaction_type not in ('income', 'expense') then
    raise exception
      'UNSUPPORTED_RECURRENCE: only income and expense rules are supported so far'
      using errcode = '22023';
  end if;

  -- Fail now, on the rule, rather than every night on the occurrence.
  if p_transaction_type = 'expense' then
    perform app.require_account(
      p_organization_id, (p_template ->> 'source_account_id')::uuid,
      array['asset', 'liability']::public.account_type[], 'source account'
    );
  else
    perform app.require_account(
      p_organization_id, (p_template ->> 'destination_account_id')::uuid,
      array['asset']::public.account_type[], 'destination account'
    );
  end if;

  if coalesce((p_template ->> 'amount_minor')::bigint, 0) <= 0 then
    raise exception 'INVALID_AMOUNT: the template needs a positive amount_minor'
      using errcode = '22023';
  end if;

  if p_template ? 'category_id' and (p_template ->> 'category_id') is not null then
    perform app.category_account(p_organization_id, (p_template ->> 'category_id')::uuid);
  end if;

  insert into public.recurring_rules (
    organization_id, name, transaction_type, template, frequency, interval_count,
    start_date, end_date, max_occurrences, mode, next_run_on, created_by
  )
  values (
    p_organization_id, trim(p_name), p_transaction_type, p_template, p_frequency,
    coalesce(p_interval_count, 1), p_start_date, p_end_date, p_max_occurrences,
    coalesce(p_mode, 'requires_confirmation'), p_start_date, auth.uid()
  )
  returning id into v_id;

  perform app.write_audit(
    p_organization_id, 'recurring.created', 'recurring_rule', v_id,
    null, jsonb_build_object('name', p_name, 'frequency', p_frequency,
                             'mode', coalesce(p_mode, 'requires_confirmation'))
  );

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Claim one occurrence
-- ---------------------------------------------------------------------------
-- The idempotency point, isolated in its own function for two reasons: an
-- ON CONFLICT target cannot be table-qualified, so it must not sit in a scope
-- where a PL/pgSQL variable shares a name with the column; and keeping it here
-- makes the guarantee a single named unit rather than a detail buried in a loop.
--
-- Returns NULL when the occurrence already exists, which is how a concurrent
-- second run learns to skip instead of posting twice.
create or replace function app.claim_occurrence(
  p_organization_id uuid,
  p_rule_id         uuid,
  p_date            date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.recurring_occurrences (
    organization_id, rule_id, occurrence_date, status
  )
  values (p_organization_id, p_rule_id, p_date, 'pending')
  on conflict (rule_id, occurrence_date) do nothing
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Post one occurrence
-- ---------------------------------------------------------------------------
-- Separated out so both the scheduler and a manual confirmation take exactly
-- the same path into the ledger.
create or replace function app.post_recurring_occurrence(p_occurrence_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_occurrence public.recurring_occurrences%rowtype;
  v_rule       public.recurring_rules%rowtype;
  v_template   jsonb;
  v_txn_id     uuid;
  v_key        text;
begin
  select * into v_occurrence from public.recurring_occurrences o
  where o.id = p_occurrence_id for update;

  if not found then
    raise exception 'TENANT_ACCESS_DENIED: occurrence not found' using errcode = '42501';
  end if;

  if v_occurrence.status = 'posted' then
    return v_occurrence.transaction_id;   -- already done; replay is a no-op
  end if;

  select * into v_rule from public.recurring_rules r where r.id = v_occurrence.rule_id;
  v_template := v_rule.template;

  -- Belt and braces alongside the unique constraint: the same occurrence maps
  -- to the same idempotency key, so even a duplicated row could not post twice.
  v_key := 'recurring:' || v_rule.id::text || ':' || v_occurrence.occurrence_date::text;

  if v_rule.transaction_type = 'expense' then
    v_txn_id := public.record_expense(
      p_organization_id   => v_rule.organization_id,
      p_amount_minor      => (v_template ->> 'amount_minor')::bigint,
      p_source_account_id => (v_template ->> 'source_account_id')::uuid,
      p_category_id       => nullif(v_template ->> 'category_id', '')::uuid,
      p_transaction_date  => v_occurrence.occurrence_date,
      p_counterparty_id   => nullif(v_template ->> 'counterparty_id', '')::uuid,
      p_description       => coalesce(v_template ->> 'description', v_rule.name),
      p_reference         => nullif(v_template ->> 'reference', ''),
      p_idempotency_key   => v_key
    );
  else
    v_txn_id := public.record_income(
      p_organization_id        => v_rule.organization_id,
      p_amount_minor           => (v_template ->> 'amount_minor')::bigint,
      p_destination_account_id => (v_template ->> 'destination_account_id')::uuid,
      p_category_id            => nullif(v_template ->> 'category_id', '')::uuid,
      p_transaction_date       => v_occurrence.occurrence_date,
      p_counterparty_id        => nullif(v_template ->> 'counterparty_id', '')::uuid,
      p_description            => coalesce(v_template ->> 'description', v_rule.name),
      p_reference              => nullif(v_template ->> 'reference', ''),
      p_idempotency_key        => v_key
    );
  end if;

  update public.recurring_occurrences o
  set status = 'posted', transaction_id = v_txn_id, posted_at = now(), error_message = null
  where o.id = p_occurrence_id;

  update public.transactions t set source = 'recurring' where t.id = v_txn_id;

  return v_txn_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- The scheduler
-- ---------------------------------------------------------------------------
create or replace function public.run_recurring_schedule(
  p_organization_id uuid,
  p_through_date    date default null
)
returns table (
  rule_id         uuid,
  occurrence_date date,
  status          public.occurrence_status,
  transaction_id  uuid,
  message         text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_through   date;
  v_rule      public.recurring_rules%rowtype;
  v_index     integer;
  v_date      date;
  v_occ_id    uuid;
  v_txn_id    uuid;
  v_guard     integer;
begin
  perform app.require_capability(p_organization_id, 'recurring.manage');

  v_through := coalesce(p_through_date, app.org_today(p_organization_id));

  for v_rule in
    select * from public.recurring_rules r
    where r.organization_id = p_organization_id
      and r.status = 'active'
      and r.start_date <= v_through
    order by r.created_at
    for update
  loop
    v_index := v_rule.occurrences_created;
    v_guard := 0;

    loop
      -- A rule created far in the past would otherwise spin for thousands of
      -- iterations in one call; it catches up over successive runs instead.
      v_guard := v_guard + 1;
      exit when v_guard > 120;

      v_date := app.nth_occurrence(v_rule.start_date, v_rule.frequency,
                                   v_rule.interval_count, v_index);

      exit when v_date > v_through;
      exit when v_rule.end_date is not null and v_date > v_rule.end_date;
      exit when v_rule.max_occurrences is not null and v_index >= v_rule.max_occurrences;

      -- The idempotency point. A concurrent run loses this insert and moves on
      -- rather than posting a second transaction for the same period.
      v_occ_id := app.claim_occurrence(v_rule.organization_id, v_rule.id, v_date);

      if v_occ_id is null then
        v_index := v_index + 1;
        continue;
      end if;

      if v_rule.mode = 'auto_post' then
        begin
          v_txn_id := app.post_recurring_occurrence(v_occ_id);

          rule_id := v_rule.id; occurrence_date := v_date;
          status := 'posted'; transaction_id := v_txn_id; message := null;
          return next;
        exception when others then
          -- One bad occurrence must not abort the whole run, and the reason has
          -- to survive for whoever investigates.
          update public.recurring_occurrences o
          set status = 'failed', error_message = sqlerrm
          where o.id = v_occ_id;

          update public.recurring_rules r
          set failure_count = r.failure_count + 1,
              last_error = sqlerrm,
              status = case when r.failure_count + 1 >= 3
                            then 'failed'::public.recurring_status
                            else r.status end
          where r.id = v_rule.id;

          perform app.notify(
            v_rule.organization_id, v_rule.created_by, 'recurring.failed',
            'A recurring transaction could not be posted',
            v_rule.name || ' — ' || sqlerrm,
            'recurring_rule', v_rule.id, 'error'
          );

          rule_id := v_rule.id; occurrence_date := v_date;
          status := 'failed'; transaction_id := null; message := sqlerrm;
          return next;
        end;
      else
        perform app.notify(
          v_rule.organization_id, v_rule.created_by, 'recurring.awaiting_confirmation',
          'A recurring transaction is waiting for you',
          v_rule.name, 'recurring_rule', v_rule.id, 'info'
        );

        rule_id := v_rule.id; occurrence_date := v_date;
        status := 'pending'; transaction_id := null; message := null;
        return next;
      end if;

      v_index := v_index + 1;
    end loop;

    -- Advance the cursor only after the occurrence rows exist, so a crash
    -- mid-run replays the same period rather than skipping it.
    update public.recurring_rules r
    set occurrences_created = v_index,
        previous_run_on = v_through,
        next_run_on = app.nth_occurrence(r.start_date, r.frequency, r.interval_count, v_index),
        status = case
          when r.max_occurrences is not null and v_index >= r.max_occurrences
            then 'completed'::public.recurring_status
          when r.end_date is not null
               and app.nth_occurrence(r.start_date, r.frequency, r.interval_count, v_index) > r.end_date
            then 'completed'::public.recurring_status
          else r.status
        end
    where r.id = v_rule.id;
  end loop;

  return;
end;
$$;

comment on function public.run_recurring_schedule(uuid, date) is
  'Idempotent. Generates every occurrence due up to the given date, posting '
  'immediately for auto_post rules and queuing the rest for confirmation. '
  'Running it twice produces nothing the second time.';

-- ---------------------------------------------------------------------------
-- Confirm a queued occurrence
-- ---------------------------------------------------------------------------
create or replace function public.confirm_recurring_occurrence(p_occurrence_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
begin
  select o.organization_id into v_org
  from public.recurring_occurrences o where o.id = p_occurrence_id;

  if v_org is null then
    raise exception 'TENANT_ACCESS_DENIED: occurrence not found' using errcode = '42501';
  end if;

  perform app.require_capability(v_org, 'transactions.post');

  return app.post_recurring_occurrence(p_occurrence_id);
end;
$$;

create or replace function public.skip_recurring_occurrence(
  p_occurrence_id uuid,
  p_reason        text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_occurrence public.recurring_occurrences%rowtype;
begin
  select * into v_occurrence from public.recurring_occurrences o
  where o.id = p_occurrence_id for update;

  if not found then
    raise exception 'TENANT_ACCESS_DENIED: occurrence not found' using errcode = '42501';
  end if;

  perform app.require_capability(v_occurrence.organization_id, 'recurring.manage');

  if v_occurrence.status = 'posted' then
    raise exception
      'INVALID_TRANSACTION_STATE: this occurrence already posted; reverse the '
      'transaction instead'
      using errcode = '23514';
  end if;

  update public.recurring_occurrences o
  set status = 'skipped', error_message = p_reason
  where o.id = p_occurrence_id;

  return p_occurrence_id;
end;
$$;

create or replace function public.set_recurring_rule_status(
  p_rule_id uuid,
  p_status  public.recurring_status
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule public.recurring_rules%rowtype;
begin
  select * into v_rule from public.recurring_rules r where r.id = p_rule_id for update;

  if not found then
    raise exception 'TENANT_ACCESS_DENIED: rule not found' using errcode = '42501';
  end if;

  perform app.require_capability(v_rule.organization_id, 'recurring.manage');

  update public.recurring_rules r
  set status = p_status,
      -- Resuming after failures starts the retry budget again.
      failure_count = case when p_status = 'active' then 0 else r.failure_count end,
      last_error = case when p_status = 'active' then null else r.last_error end
  where r.id = p_rule_id;

  perform app.write_audit(
    v_rule.organization_id, 'recurring.status_changed', 'recurring_rule', p_rule_id,
    jsonb_build_object('status', v_rule.status), jsonb_build_object('status', p_status)
  );

  return p_rule_id;
end;
$$;
