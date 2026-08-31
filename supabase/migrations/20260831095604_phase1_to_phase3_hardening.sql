-- Ledger Suit — Phase 1–3 security and lifecycle hardening
-- Forward-only correction for client-writable workflow state.

-- ---------------------------------------------------------------------------
-- Commitments: settlement state is RPC-owned.
-- ---------------------------------------------------------------------------
revoke update on public.commitments from authenticated;
drop policy if exists "commitments are edited with commitments.update"
  on public.commitments;

alter table public.commitments
  add column if not exists auto_payment_account_id uuid;

alter table public.commitments
  add constraint commitments_auto_payment_account_same_org
  foreign key (auto_payment_account_id, organization_id)
  references public.accounts (id, organization_id) on delete restrict;

create index if not exists commitments_auto_due_idx
  on public.commitments (organization_id, due_date)
  where auto_convert = true
    and status in ('upcoming', 'partially_paid');

create or replace function public.update_commitment(
  p_commitment_id          uuid,
  p_title                  text,
  p_description            text default null,
  p_amount_minor           bigint default null,
  p_linked_category_id     uuid default null,
  p_linked_account_id      uuid default null,
  p_counterparty_id        uuid default null,
  p_notes                  text default null,
  p_auto_convert           boolean default false,
  p_auto_payment_account_id uuid default null,
  p_reminder_days_before   smallint default 3
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.commitments%rowtype;
  v_amount bigint;
begin
  select * into v_row
  from public.commitments c
  where c.id = p_commitment_id
  for update;

  if not found then
    raise exception 'TENANT_ACCESS_DENIED: commitment not found' using errcode = '42501';
  end if;

  perform app.require_capability(v_row.organization_id, 'commitments.update');

  if v_row.status in ('paid', 'cancelled') then
    raise exception 'INVALID_COMMITMENT_STATE: a closed commitment cannot be edited'
      using errcode = '23514';
  end if;

  if p_title is null or char_length(trim(p_title)) = 0 then
    raise exception 'INVALID_INPUT: a title is required' using errcode = '22023';
  end if;

  v_amount := coalesce(p_amount_minor, v_row.amount_minor);
  if v_amount <= 0 or v_amount < v_row.settled_amount_minor then
    raise exception 'INVALID_AMOUNT: amount must be positive and not below settlements'
      using errcode = '22023';
  end if;

  if p_linked_account_id is not null then
    perform app.require_account(v_row.organization_id, p_linked_account_id, null, 'linked account');
  end if;
  if p_linked_category_id is not null then
    perform app.category_account(v_row.organization_id, p_linked_category_id);
  end if;
  if p_auto_convert and p_auto_payment_account_id is null then
    raise exception 'INVALID_ACCOUNT: automatic conversion requires a payment account'
      using errcode = '22023';
  end if;
  if p_auto_payment_account_id is not null then
    perform app.require_account(
      v_row.organization_id, p_auto_payment_account_id,
      array['asset', 'liability']::public.account_type[], 'automatic payment account'
    );
  end if;

  update public.commitments c
  set title = trim(p_title),
      description = p_description,
      amount_minor = v_amount,
      linked_category_id = p_linked_category_id,
      linked_account_id = p_linked_account_id,
      counterparty_id = p_counterparty_id,
      notes = p_notes,
      auto_convert = coalesce(p_auto_convert, false),
      auto_payment_account_id = case when p_auto_convert then p_auto_payment_account_id end,
      reminder_days_before = coalesce(p_reminder_days_before, 3::smallint)
  where c.id = p_commitment_id;

  perform app.write_audit(
    v_row.organization_id, 'commitment.updated', 'commitment', p_commitment_id,
    to_jsonb(v_row),
    jsonb_build_object('title', trim(p_title), 'amount_minor', v_amount,
                       'auto_convert', coalesce(p_auto_convert, false))
  );
  return p_commitment_id;
end;
$$;

create or replace function public.run_due_commitment_conversions(
  p_organization_id uuid,
  p_through_date date default null
)
returns table (commitment_id uuid, transaction_id uuid, status text, message text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.commitments%rowtype;
  v_through date;
begin
  perform app.require_capability(p_organization_id, 'commitments.settle');
  v_through := coalesce(p_through_date, app.org_today(p_organization_id));

  for v_row in
    select * from public.commitments c
    where c.organization_id = p_organization_id
      and c.auto_convert = true
      and c.auto_payment_account_id is not null
      and c.status in ('upcoming', 'partially_paid')
      and c.due_date <= v_through
    order by c.due_date, c.created_at
    for update skip locked
  loop
    commitment_id := v_row.id;
    begin
      transaction_id := public.settle_commitment(
        p_commitment_id => v_row.id,
        p_payment_account_id => v_row.auto_payment_account_id,
        p_settled_on => v_row.due_date,
        p_idempotency_key => 'commitment:auto:' || v_row.id::text || ':' || v_row.due_date::text
      );
      status := 'posted'; message := null;
    exception when others then
      transaction_id := null; status := 'failed'; message := sqlerrm;
      perform app.notify(
        v_row.organization_id, v_row.created_by, 'commitment.auto_convert_failed',
        'A commitment could not be converted', v_row.title || ' — ' || sqlerrm,
        'commitment', v_row.id, 'error'
      );
    end;
    return next;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Recurring rules: templates and scheduler cursors are RPC-owned.
-- ---------------------------------------------------------------------------
revoke update on public.recurring_rules from authenticated;
drop policy if exists "recurring rules are edited with recurring.manage"
  on public.recurring_rules;

create or replace function app.guard_recurring_rule_tenant()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.organization_id is distinct from old.organization_id then
    raise exception 'TENANT_KEY_IMMUTABLE: organization_id cannot be changed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger recurring_rules_guard_tenant
  before update on public.recurring_rules
  for each row execute function app.guard_recurring_rule_tenant();

alter table public.recurring_occurrences
  add column if not exists attempt_count integer not null default 0,
  add column if not exists last_attempt_at timestamptz;

alter table public.recurring_occurrences
  add constraint recurring_occurrences_attempt_count_nonnegative
  check (attempt_count >= 0);

-- Extend the recurring engine to loan/liability instalments. Income and expense
-- remain the simple paths; the template for a liability payment contains the
-- same validated fields as record_liability_payment().
create or replace function public.create_recurring_rule(
  p_organization_id  uuid,
  p_name             text,
  p_transaction_type public.transaction_type,
  p_template         jsonb,
  p_frequency        public.recurrence_frequency,
  p_start_date       date,
  p_interval_count   integer default 1,
  p_end_date         date default null,
  p_max_occurrences  integer default null,
  p_mode             public.recurring_mode default 'requires_confirmation'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  perform app.require_capability(p_organization_id, 'recurring.manage');
  if p_name is null or char_length(trim(p_name)) = 0 then
    raise exception 'INVALID_INPUT: a rule name is required' using errcode = '22023';
  end if;
  if p_transaction_type not in ('income', 'expense', 'liability_payment') then
    raise exception 'UNSUPPORTED_RECURRENCE: this transaction flow is not supported'
      using errcode = '22023';
  end if;

  if p_transaction_type = 'expense' then
    perform app.require_account(p_organization_id,
      (p_template ->> 'source_account_id')::uuid,
      array['asset', 'liability']::public.account_type[], 'source account');
    if coalesce((p_template ->> 'amount_minor')::bigint, 0) <= 0 then
      raise exception 'INVALID_AMOUNT: the template needs a positive amount'
        using errcode = '22023';
    end if;
  elsif p_transaction_type = 'income' then
    perform app.require_account(p_organization_id,
      (p_template ->> 'destination_account_id')::uuid,
      array['asset']::public.account_type[], 'destination account');
    if coalesce((p_template ->> 'amount_minor')::bigint, 0) <= 0 then
      raise exception 'INVALID_AMOUNT: the template needs a positive amount'
        using errcode = '22023';
    end if;
  else
    perform app.require_account(p_organization_id,
      (p_template ->> 'liability_account_id')::uuid,
      array['liability']::public.account_type[], 'liability account');
    perform app.require_account(p_organization_id,
      (p_template ->> 'payment_account_id')::uuid,
      array['asset']::public.account_type[], 'payment account');
    if coalesce((p_template ->> 'principal_minor')::bigint, 0)
       + coalesce((p_template ->> 'interest_minor')::bigint, 0)
       + coalesce((p_template ->> 'fees_minor')::bigint, 0) <= 0 then
      raise exception 'INVALID_AMOUNT: a liability payment needs a positive component'
        using errcode = '22023';
    end if;
  end if;

  if p_template ? 'category_id' and nullif(p_template ->> 'category_id', '') is not null then
    perform app.category_account(p_organization_id, (p_template ->> 'category_id')::uuid);
  end if;

  insert into public.recurring_rules (
    organization_id, name, transaction_type, template, frequency, interval_count,
    start_date, end_date, max_occurrences, mode, next_run_on, created_by
  ) values (
    p_organization_id, trim(p_name), p_transaction_type, p_template, p_frequency,
    coalesce(p_interval_count, 1), p_start_date, p_end_date, p_max_occurrences,
    coalesce(p_mode, 'requires_confirmation'), p_start_date, auth.uid()
  ) returning id into v_id;

  perform app.write_audit(p_organization_id, 'recurring.created', 'recurring_rule', v_id,
    null, jsonb_build_object('name', trim(p_name), 'frequency', p_frequency,
                             'mode', coalesce(p_mode, 'requires_confirmation')));
  return v_id;
end;
$$;

create or replace function app.post_recurring_occurrence(p_occurrence_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_occurrence public.recurring_occurrences%rowtype;
  v_rule public.recurring_rules%rowtype;
  v_template jsonb;
  v_txn_id uuid;
  v_key text;
begin
  select * into v_occurrence from public.recurring_occurrences o
  where o.id = p_occurrence_id for update;
  if not found then raise exception 'TENANT_ACCESS_DENIED: occurrence not found' using errcode = '42501'; end if;
  if v_occurrence.status = 'posted' then return v_occurrence.transaction_id; end if;

  select * into v_rule from public.recurring_rules r where r.id = v_occurrence.rule_id;
  v_template := v_rule.template;
  v_key := 'recurring:' || v_rule.id::text || ':' || v_occurrence.occurrence_date::text;

  case v_rule.transaction_type
    when 'expense' then
      v_txn_id := public.record_expense(
        p_organization_id => v_rule.organization_id,
        p_amount_minor => (v_template ->> 'amount_minor')::bigint,
        p_source_account_id => (v_template ->> 'source_account_id')::uuid,
        p_category_id => nullif(v_template ->> 'category_id', '')::uuid,
        p_transaction_date => v_occurrence.occurrence_date,
        p_counterparty_id => nullif(v_template ->> 'counterparty_id', '')::uuid,
        p_description => coalesce(v_template ->> 'description', v_rule.name),
        p_reference => nullif(v_template ->> 'reference', ''), p_idempotency_key => v_key);
    when 'income' then
      v_txn_id := public.record_income(
        p_organization_id => v_rule.organization_id,
        p_amount_minor => (v_template ->> 'amount_minor')::bigint,
        p_destination_account_id => (v_template ->> 'destination_account_id')::uuid,
        p_category_id => nullif(v_template ->> 'category_id', '')::uuid,
        p_transaction_date => v_occurrence.occurrence_date,
        p_counterparty_id => nullif(v_template ->> 'counterparty_id', '')::uuid,
        p_description => coalesce(v_template ->> 'description', v_rule.name),
        p_reference => nullif(v_template ->> 'reference', ''), p_idempotency_key => v_key);
    when 'liability_payment' then
      v_txn_id := public.record_liability_payment(
        p_organization_id => v_rule.organization_id,
        p_liability_account_id => (v_template ->> 'liability_account_id')::uuid,
        p_payment_account_id => (v_template ->> 'payment_account_id')::uuid,
        p_principal_minor => coalesce((v_template ->> 'principal_minor')::bigint, 0),
        p_interest_minor => coalesce((v_template ->> 'interest_minor')::bigint, 0),
        p_fees_minor => coalesce((v_template ->> 'fees_minor')::bigint, 0),
        p_transaction_date => v_occurrence.occurrence_date,
        p_counterparty_id => nullif(v_template ->> 'counterparty_id', '')::uuid,
        p_description => coalesce(v_template ->> 'description', v_rule.name),
        p_reference => nullif(v_template ->> 'reference', ''), p_idempotency_key => v_key);
    else
      raise exception 'UNSUPPORTED_RECURRENCE: transaction type is not supported' using errcode = '22023';
  end case;

  update public.recurring_occurrences o
  set status = 'posted', transaction_id = v_txn_id, posted_at = now(),
      error_message = null, attempt_count = o.attempt_count + 1,
      last_attempt_at = now()
  where o.id = p_occurrence_id;
  update public.transactions t set source = 'recurring' where t.id = v_txn_id;
  return v_txn_id;
end;
$$;

create or replace function public.retry_recurring_occurrence(p_occurrence_id uuid)
returns table (transaction_id uuid, status public.occurrence_status, message text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_occ public.recurring_occurrences%rowtype;
begin
  select * into v_occ
  from public.recurring_occurrences o
  where o.id = p_occurrence_id
  for update;

  if not found then
    raise exception 'TENANT_ACCESS_DENIED: occurrence not found' using errcode = '42501';
  end if;
  perform app.require_capability(v_occ.organization_id, 'recurring.manage');

  if v_occ.status <> 'failed' then
    raise exception 'INVALID_TRANSACTION_STATE: only failed occurrences can be retried'
      using errcode = '23514';
  end if;

  begin
    transaction_id := app.post_recurring_occurrence(p_occurrence_id);
    status := 'posted'; message := null;
    update public.recurring_rules r
    set failure_count = greatest(r.failure_count - 1, 0),
        last_error = null,
        status = case when r.status = 'failed' then 'active'::public.recurring_status else r.status end
    where r.id = v_occ.rule_id;
  exception when others then
    transaction_id := null; status := 'failed'; message := sqlerrm;
    update public.recurring_occurrences o
    set status = 'failed', error_message = sqlerrm,
        attempt_count = o.attempt_count + 1, last_attempt_at = now()
    where o.id = p_occurrence_id;
  end;
  return next;
end;
$$;

-- ---------------------------------------------------------------------------
-- Invitations: token creation and acceptance are atomic controlled actions.
-- ---------------------------------------------------------------------------
revoke insert, update on public.organization_invitations from authenticated;
drop policy if exists "invitations are created with members.invite"
  on public.organization_invitations;
drop policy if exists "invitations are updated with members.update"
  on public.organization_invitations;

create or replace function public.create_organization_invitation(
  p_organization_id uuid,
  p_email text,
  p_role public.organization_role default 'viewer'
)
returns table (invitation_id uuid, invitation_token text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
begin
  perform app.require_capability(p_organization_id, 'members.invite');
  if p_role = 'owner' then
    raise exception 'INVALID_ROLE: owners cannot be invited directly' using errcode = '22023';
  end if;
  if p_email is null or p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'INVALID_INPUT: a valid email is required' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.organization_members m
    join public.profiles p on p.id = m.user_id
    where m.organization_id = p_organization_id and p.email = p_email
  ) then
    raise exception 'DUPLICATE_MEMBERSHIP: this user is already a member' using errcode = '23505';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.organization_invitations (
    organization_id, email, role, token_hash, invited_by
  ) values (
    p_organization_id, lower(trim(p_email)), p_role,
    encode(extensions.digest(v_token, 'sha256'), 'hex'), auth.uid()
  )
  returning id into invitation_id;
  invitation_token := v_token;

  perform app.write_audit(
    p_organization_id, 'member.invited', 'organization_invitation', invitation_id,
    null, jsonb_build_object('email', lower(trim(p_email)), 'role', p_role)
  );
  return next;
end;
$$;

create or replace function public.accept_organization_invitation(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv public.organization_invitations%rowtype;
  v_email extensions.citext;
begin
  if auth.uid() is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  select p.email into v_email from public.profiles p where p.id = auth.uid();
  select * into v_inv
  from public.organization_invitations i
  where i.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
  for update;

  if not found or v_inv.status <> 'pending' or v_inv.expires_at <= now()
     or v_inv.email <> v_email then
    raise exception 'INVALID_INVITATION: invitation is invalid or expired'
      using errcode = '42501';
  end if;

  insert into public.organization_members (
    organization_id, user_id, role, invited_by
  ) values (v_inv.organization_id, auth.uid(), v_inv.role, v_inv.invited_by)
  on conflict (organization_id, user_id) do nothing;

  update public.organization_invitations i
  set status = 'accepted', accepted_by = auth.uid(), accepted_at = now()
  where i.id = v_inv.id;

  perform app.write_audit(
    v_inv.organization_id, 'member.invitation_accepted', 'organization_invitation', v_inv.id,
    null, jsonb_build_object('user_id', auth.uid(), 'role', v_inv.role)
  );
  return v_inv.organization_id;
end;
$$;

-- Explicit Data API function permissions.
do $$
declare v_fn record;
begin
  for v_fn in
    select p.oid::regprocedure as signature
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'update_commitment', 'run_due_commitment_conversions',
        'retry_recurring_occurrence', 'create_organization_invitation',
        'accept_organization_invitation'
      )
  loop
    execute format('revoke all on function %s from public, anon', v_fn.signature);
    execute format('grant execute on function %s to authenticated, service_role', v_fn.signature);
  end loop;
end;
$$;
