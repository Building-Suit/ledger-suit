-- Business is the only launch plan that may create or mutate records outside
-- the workspace base currency.  Keep this at table boundaries so privileged
-- clients and every posting path inherit the same rule.

create or replace function app.assert_write_currency(
  p_organization_id uuid,
  p_currency_code text
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_base_currency char(3);
  v_currency char(3) := upper(trim(p_currency_code))::char(3);
begin
  select o.base_currency into strict v_base_currency
  from public.organizations o
  where o.id = p_organization_id;

  if v_currency is null or char_length(trim(v_currency)) <> 3
     or not exists (select 1 from public.currencies c where c.code = v_currency and c.is_active) then
    raise exception 'INVALID_CURRENCY: %', coalesce(p_currency_code, '')
      using errcode = '22023';
  end if;

  if v_currency <> v_base_currency then
    perform app.assert_plan_feature(p_organization_id, 'multi_currency');
  end if;
end;
$$;

comment on function app.assert_write_currency(uuid, text) is
  'Private authoritative assertion for writes denominated outside an organization base currency.';

create or replace function app.enforce_row_write_currency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := to_jsonb(new);
  v_old_row jsonb;
  v_currency text := v_row ->> tg_argv[0];
  v_account_currency char(3);
begin
  if tg_op = 'UPDATE' then
    v_old_row := to_jsonb(old);

    -- Downgrades freeze new FX activity, but must not trap customers in live
    -- resources. Permit only tightly-scoped closing transitions.
    if tg_table_name = 'accounts'
       and v_old_row ->> 'currency' = v_row ->> 'currency'
       and not (v_old_row ->> 'is_archived')::boolean
       and (v_row ->> 'is_archived')::boolean
       and (v_row - array['is_archived', 'archived_at', 'updated_at',
                          'normal_balance', 'is_liquid'])
           = (v_old_row - array['is_archived', 'archived_at', 'updated_at',
                                'normal_balance', 'is_liquid']) then
      return new;
    elsif tg_table_name = 'transactions'
       and v_old_row ->> 'currency_code' = v_row ->> 'currency_code'
       and v_old_row ->> 'status' not in ('voided', 'reversed')
       and v_row ->> 'status' = 'voided'
       and (v_row - array['status', 'voided_at', 'voided_by', 'metadata', 'updated_at'])
           = (v_old_row - array['status', 'voided_at', 'voided_by', 'metadata', 'updated_at']) then
      return new;
    elsif tg_table_name = 'commitments'
       and v_old_row ->> 'currency_code' = v_row ->> 'currency_code'
       and v_old_row ->> 'status' <> 'cancelled'
       and v_row ->> 'status' = 'cancelled'
       and (v_row - array['status', 'cancelled_at', 'cancelled_reason', 'updated_at'])
           = (v_old_row - array['status', 'cancelled_at', 'cancelled_reason', 'updated_at']) then
      return new;
    end if;
  end if;

  perform app.assert_write_currency((v_row ->> 'organization_id')::uuid, v_currency);

  if tg_table_name = 'transaction_entries' then
    select a.currency into v_account_currency
    from public.accounts a
    where a.id = (v_row ->> 'account_id')::uuid
      and a.organization_id = (v_row ->> 'organization_id')::uuid;
    if found then
      perform app.assert_write_currency(
        (v_row ->> 'organization_id')::uuid,
        v_account_currency
      );
    end if;
  elsif tg_table_name = 'commitments' then
    foreach v_currency in array array[
      v_row ->> 'linked_account_id', v_row ->> 'auto_payment_account_id'
    ] loop
      if nullif(v_currency, '') is not null then
        select a.currency into v_account_currency
        from public.accounts a
        where a.id = v_currency::uuid
          and a.organization_id = (v_row ->> 'organization_id')::uuid;
        if found then
          perform app.assert_write_currency(
            (v_row ->> 'organization_id')::uuid,
            v_account_currency
          );
        end if;
      end if;
    end loop;
  end if;

  return new;
end;
$$;

create trigger accounts_multi_currency_guard
  before insert or update on public.accounts
  for each row execute function app.enforce_row_write_currency('currency');

create trigger transactions_multi_currency_guard
  before insert or update on public.transactions
  for each row execute function app.enforce_row_write_currency('currency_code');

create trigger transaction_entries_multi_currency_guard
  before insert or update on public.transaction_entries
  for each row execute function app.enforce_row_write_currency('currency_code');

create trigger commitments_multi_currency_guard
  before insert or update on public.commitments
  for each row execute function app.enforce_row_write_currency('currency_code');

-- Recurring templates do not have a currency column. Their effective currency
-- comes from the accounts replayed by the scheduler, plus an optional explicit
-- currency_code used by API clients.
create or replace function app.assert_recurring_template_currency(
  p_organization_id uuid,
  p_template jsonb
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_key text;
  v_account_currency char(3);
begin
  if nullif(p_template ->> 'currency_code', '') is not null then
    perform app.assert_write_currency(p_organization_id, p_template ->> 'currency_code');
  end if;

  foreach v_key in array array[
    'source_account_id', 'destination_account_id', 'liability_account_id',
    'payment_account_id', 'revenue_account_id', 'expense_account_id'
  ] loop
    if nullif(p_template ->> v_key, '') is not null then
      select a.currency into v_account_currency
      from public.accounts a
      where a.id = (p_template ->> v_key)::uuid
        and a.organization_id = p_organization_id;

      if found then
        perform app.assert_write_currency(p_organization_id, v_account_currency);
      end if;
    end if;
  end loop;
end;
$$;

create or replace function app.enforce_recurring_template_currency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and old.template = new.template
     and old.status in ('active', 'paused', 'failed')
     and new.status in ('paused', 'completed')
     and new.status <> old.status
     and (to_jsonb(new) - array['status', 'failure_count', 'last_error', 'updated_at'])
         = (to_jsonb(old) - array['status', 'failure_count', 'last_error', 'updated_at']) then
    return new;
  end if;

  perform app.assert_recurring_template_currency(new.organization_id, new.template);
  return new;
end;
$$;

create trigger recurring_rules_multi_currency_guard
  before insert or update on public.recurring_rules
  for each row execute function app.enforce_recurring_template_currency();

-- The base currency defines whether every other currency is foreign. Prevent
-- clients from moving that trust boundary through a direct organization update.
create or replace function app.guard_organization_base_currency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.base_currency is distinct from old.base_currency
     and coalesce(current_setting('app.allow_base_currency_change', true), 'off') <> 'on' then
    raise exception 'BASE_CURRENCY_CHANGE_REQUIRES_CONTROLLED_PATH:'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger organizations_base_currency_guard
  before update on public.organizations
  for each row execute function app.guard_organization_base_currency();

create or replace function public.change_organization_base_currency(
  p_organization_id uuid,
  p_base_currency char(3)
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old_currency char(3);
  v_new_currency char(3) := upper(trim(p_base_currency))::char(3);
begin
  perform app.require_capability(p_organization_id, 'organization.update');

  select o.base_currency into strict v_old_currency
  from public.organizations o
  where o.id = p_organization_id
  for update;

  if not exists (
    select 1 from public.currencies c
    where c.code = v_new_currency and c.is_active
  ) then
    raise exception 'INVALID_CURRENCY: %', coalesce(p_base_currency::text, '')
      using errcode = '22023';
  end if;

  if v_new_currency = v_old_currency then
    return p_organization_id;
  end if;

  if exists (select 1 from public.accounts a where a.organization_id = p_organization_id)
     or exists (select 1 from public.transactions t where t.organization_id = p_organization_id)
     or exists (select 1 from public.transaction_entries e where e.organization_id = p_organization_id)
     or exists (select 1 from public.commitments c where c.organization_id = p_organization_id)
     or exists (select 1 from public.recurring_rules r where r.organization_id = p_organization_id) then
    raise exception 'BASE_CURRENCY_LOCKED: accounting state already exists'
      using errcode = '23514';
  end if;

  perform set_config('app.allow_base_currency_change', 'on', true);
  update public.organizations o
  set base_currency = v_new_currency
  where o.id = p_organization_id;
  perform set_config('app.allow_base_currency_change', 'off', true);

  update public.organization_settings s
  set default_transaction_currency = v_new_currency
  where s.organization_id = p_organization_id
    and s.default_transaction_currency = v_old_currency;

  perform app.write_audit(
    p_organization_id, 'organization.base_currency_changed', 'organization', p_organization_id,
    jsonb_build_object('base_currency', v_old_currency),
    jsonb_build_object('base_currency', v_new_currency)
  );
  return p_organization_id;
end;
$$;

revoke update on public.organizations from authenticated;
grant update (
  name, slug, legal_name, country_code, timezone, fiscal_year_start_month,
  tax_identifier, logo_url, status, archived_at
) on public.organizations to authenticated;

revoke all on function public.change_organization_base_currency(uuid, char(3))
  from public, anon;
grant execute on function public.change_organization_base_currency(uuid, char(3))
  to authenticated, service_role;
