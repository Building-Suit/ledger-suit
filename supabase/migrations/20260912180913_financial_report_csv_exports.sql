-- Server-authoritative, UTF-8 CSV exports for the five launch reports.

update public.capabilities
set description = 'Export financial reports to CSV',
    description_ar = 'تصدير التقارير المالية إلى CSV'
where key in ('reports.export', 'exports.create');

create or replace function app.csv_cell(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(p_value, '') ~ '[,"\r\n]'
      then '"' || replace(coalesce(p_value, ''), '"', '""') || '"'
    else coalesce(p_value, '')
  end
$$;

create or replace function app.csv_line(variadic p_values text[])
returns text
language sql
immutable
set search_path = ''
as $$
  select string_agg(app.csv_cell(value), ',' order by ordinality)
  from unnest(p_values) with ordinality as cell(value, ordinality)
$$;

create or replace function app.csv_amount(
  p_organization_id uuid,
  p_amount_minor bigint
)
returns text
language sql
stable
set search_path = ''
as $$
  select round(
    p_amount_minor::numeric / power(10::numeric, currency.minor_unit),
    currency.minor_unit
  )::text
  from public.organizations organization
  join public.currencies currency on currency.code = organization.base_currency
  where organization.id = p_organization_id
$$;

create or replace function public.export_financial_report_csv(
  p_organization_id uuid,
  p_report text,
  p_from_date date default null,
  p_to_date date default null,
  p_as_of_date date default null,
  p_account_id uuid default null
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_header text;
  v_body text;
  v_currency text := app.org_base_currency(p_organization_id)::text;
begin
  perform app.require_capability(p_organization_id, 'reports.export');
  perform app.assert_plan_feature(p_organization_id, 'exports');

  case p_report
    when 'profit_loss' then
      if p_from_date is null or p_to_date is null then
        raise exception 'INVALID_EXPORT_ARGUMENT: profit_loss requires from and to dates'
          using errcode = '22023';
      end if;
      v_header := app.csv_line('section', 'code', 'account', 'amount', 'currency');
      select string_agg(app.csv_line(
        report.section, report.code, report.name,
        app.csv_amount(p_organization_id, report.amount_minor), v_currency
      ), E'\n' order by report.section, report.code nulls last, report.name)
      into v_body
      from public.report_profit_and_loss(p_organization_id, p_from_date, p_to_date) report;

    when 'balance_sheet' then
      v_header := app.csv_line('section', 'code', 'account', 'amount', 'currency');
      select string_agg(app.csv_line(
        report.section, report.code, report.name,
        app.csv_amount(p_organization_id, report.amount_minor), v_currency
      ), E'\n' order by report.section, report.code nulls last, report.name)
      into v_body
      from public.report_balance_sheet(p_organization_id, p_as_of_date) report;

    when 'trial_balance' then
      v_header := app.csv_line('code', 'account', 'type', 'debit', 'credit', 'currency');
      select string_agg(app.csv_line(
        report.code, report.name, report.type::text,
        app.csv_amount(p_organization_id, report.debit_minor),
        app.csv_amount(p_organization_id, report.credit_minor), v_currency
      ), E'\n' order by report.code nulls last, report.name)
      into v_body
      from public.report_trial_balance(p_organization_id, p_as_of_date) report;

    when 'cash_flow' then
      if p_from_date is null or p_to_date is null then
        raise exception 'INVALID_EXPORT_ARGUMENT: cash_flow requires from and to dates'
          using errcode = '22023';
      end if;
      v_header := app.csv_line('activity', 'net_movement', 'currency');
      select string_agg(app.csv_line(
        report.section::text,
        app.csv_amount(p_organization_id, report.amount_minor), v_currency
      ), E'\n' order by report.section)
      into v_body
      from public.report_cash_flow(p_organization_id, p_from_date, p_to_date) report;

    when 'general_ledger' then
      if p_account_id is null or p_from_date is null or p_to_date is null then
        raise exception 'INVALID_EXPORT_ARGUMENT: general_ledger requires an account and date range'
          using errcode = '22023';
      end if;
      v_header := app.csv_line(
        'date', 'reference', 'description', 'memo', 'debit', 'credit',
        'running_balance', 'currency'
      );
      select string_agg(app.csv_line(
        report.entry_date::text, report.reference, report.description, report.memo,
        app.csv_amount(p_organization_id, report.debit_minor),
        app.csv_amount(p_organization_id, report.credit_minor),
        app.csv_amount(p_organization_id, report.running_balance_minor), v_currency
      ), E'\n' order by report.entry_date, report.entry_id)
      into v_body
      from public.report_general_ledger(
        p_organization_id, p_account_id, p_from_date, p_to_date
      ) report;

    else
      raise exception 'INVALID_EXPORT_ARGUMENT: unsupported financial report'
        using errcode = '22023';
  end case;

  return v_header || case when v_body is null then '' else E'\n' || v_body end;
end;
$$;

comment on function public.export_financial_report_csv(uuid, text, date, date, date, uuid) is
  'Exports one of the five launch financial reports as stable UTF-8 CSV after '
  'checking report-export permission and the exports plan entitlement.';

revoke all on function public.export_financial_report_csv(uuid, text, date, date, date, uuid)
from public, anon;
grant execute on function public.export_financial_report_csv(uuid, text, date, date, date, uuid)
to authenticated, service_role;

revoke all on function app.csv_cell(text), app.csv_line(variadic text[]),
  app.csv_amount(uuid, bigint) from public, anon, authenticated;
