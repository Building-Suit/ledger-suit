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
  v_currency text := v_row ->> tg_argv[0];
  v_account_currency char(3);
begin
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
  perform app.assert_recurring_template_currency(new.organization_id, new.template);
  return new;
end;
$$;

create trigger recurring_rules_multi_currency_guard
  before insert or update on public.recurring_rules
  for each row execute function app.enforce_recurring_template_currency();
