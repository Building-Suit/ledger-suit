-- Serialize any physical plan transition with every quota-increasing boundary.
-- Resource operations take one of these locks; acquiring all seven in a fixed
-- order prevents a service callback or future controlled transition from
-- racing a write evaluated against the previous plan.

create function app.plan_feature_transition_lock_key(p_organization_id uuid)
returns bigint
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.hashtextextended(
    p_organization_id::text || ':plan-feature-transition',
    73214761
  );
$$;

create function app.lock_plan_feature_transition(p_organization_id uuid)
returns bigint
language plpgsql
volatile
strict
set search_path = ''
as $$
declare
  v_lock_key bigint := app.plan_feature_transition_lock_key(p_organization_id);
begin
  perform pg_catalog.pg_advisory_xact_lock(v_lock_key);
  return v_lock_key;
end;
$$;

comment on function app.lock_plan_feature_transition(uuid) is
  'Serializes feature-gated writes with physical subscription plan transitions for one organization.';

create function app.lock_all_plan_quotas(p_organization_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_quota_key text;
begin
  if p_organization_id is null then
    raise exception 'PLAN_SUBSCRIPTION_NOT_FOUND' using errcode = '22023';
  end if;

  foreach v_quota_key in array array[
    'max_accounts',
    'max_counterparties',
    'max_custom_roles',
    'max_members',
    'max_monthly_transactions',
    'max_recurring_rules',
    'max_storage_bytes'
  ] loop
    perform app.lock_plan_quota(p_organization_id, v_quota_key);
  end loop;
end;
$$;

comment on function app.lock_all_plan_quotas(uuid) is
  'Takes every organization quota lock in canonical order before a physical subscription plan transition.';

create function app.lock_subscription_plan_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.plan_id is distinct from old.plan_id then
    perform app.lock_all_plan_quotas(new.organization_id);
    perform app.lock_plan_feature_transition(new.organization_id);
  end if;
  return new;
end;
$$;

create trigger subscriptions_lock_plan_change
  before update of plan_id on public.subscriptions
  for each row execute function app.lock_subscription_plan_change();

comment on trigger subscriptions_lock_plan_change on public.subscriptions is
  'Coordinates provider/service plan updates with quota and feature-gated write boundaries in canonical lock order.';

create or replace function app.assert_plan_feature(
  p_organization_id uuid,
  p_feature_key text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_entitlement record;
begin
  perform app.lock_plan_feature_transition(p_organization_id);

  select * into strict v_entitlement
  from app.resolve_plan_entitlement(p_organization_id, p_feature_key);

  if not v_entitlement.is_enabled
     or (v_entitlement.limit_value is not null and v_entitlement.limit_value = 0) then
    raise exception '%: %', app.plan_feature_error_code(p_feature_key), p_feature_key
      using errcode = 'P0001';
  end if;
end;
$$;

comment on function app.assert_plan_feature(uuid, text) is
  'Locks the organization plan-feature boundary, then authoritatively checks the current entitlement.';

-- These assertions now transitively take a transaction advisory lock.
alter function app.assert_write_currency(uuid, text) volatile;
alter function app.assert_recurring_template_currency(uuid, jsonb) volatile;
alter function app.validate_csv_import_row(uuid, jsonb, jsonb) volatile;
alter function public.export_financial_report_csv(uuid, text, date, date, date, uuid) volatile;

-- Import confirmation eventually enters the monthly transaction quota
-- boundary. Take that resource lock before the feature lock to preserve the
-- same quota-then-feature order used by plan transitions and row triggers.
create or replace function public.confirm_csv_import_batch(p_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.import_batches%rowtype;
  v_row public.import_rows%rowtype;
  v_data jsonb;
  v_category_account uuid;
  v_transaction_id uuid;
  v_existing uuid;
  v_error text;
  v_status text;
  v_summary jsonb;
begin
  select * into v_batch from public.import_batches b where b.id = p_batch_id for update;
  if not found then
    raise exception 'TENANT_ACCESS_DENIED: import batch not found' using errcode = '42501';
  end if;
  perform app.require_capability(v_batch.organization_id, 'imports.create');
  perform app.lock_plan_quota(v_batch.organization_id, 'max_monthly_transactions');
  perform app.assert_plan_feature(v_batch.organization_id, 'imports');
  if v_batch.status not in ('validated', 'partial', 'completed') then
    raise exception 'IMPORT_BATCH_NOT_VALIDATED:' using errcode = '23514';
  end if;
  if v_batch.status = 'completed' then
    perform app.refresh_import_batch_counts(p_batch_id);
  else
    update public.import_batches set status = 'processing' where id = p_batch_id;

    for v_row in select * from public.import_rows r
                 where r.batch_id = p_batch_id and r.status in ('valid', 'failed')
                 order by r.row_number for update loop
      begin
        perform pg_advisory_xact_lock(hashtextextended(
          v_batch.organization_id::text || ':' || v_row.deterministic_key, 0
        ));
        select t.id into v_existing from public.transactions t
        where t.organization_id = v_batch.organization_id
          and t.idempotency_key = 'csv-import:' || v_row.deterministic_key;
        if v_existing is not null then
          update public.import_rows set status = 'duplicate', transaction_id = v_existing,
            attempt_count = attempt_count + 1, error_code = 'IMPORT_ROW_DUPLICATE',
            error_message = 'An identical transaction already exists.' where id = v_row.id;
          continue;
        end if;

        v_data := v_row.normalized_data;
        v_category_account := app.assert_csv_import_posting_semantics(
          v_batch.organization_id, v_data
        );
        v_transaction_id := app.create_and_post(
          p_organization_id => v_batch.organization_id,
          p_type => (v_data ->> 'type')::public.transaction_type,
          p_transaction_date => (v_data ->> 'transaction_date')::date,
          p_lines => case v_data ->> 'type'
            when 'income' then jsonb_build_array(
              jsonb_build_object('account_id', v_data ->> 'account_id', 'side', 'debit',
                'amount_minor', v_data ->> 'amount_minor'),
              jsonb_build_object('account_id', v_category_account, 'side', 'credit',
                'amount_minor', v_data ->> 'amount_minor'))
            else jsonb_build_array(
              jsonb_build_object('account_id', v_category_account, 'side', 'debit',
                'amount_minor', v_data ->> 'amount_minor'),
              jsonb_build_object('account_id', v_data ->> 'account_id', 'side', 'credit',
                'amount_minor', v_data ->> 'amount_minor'))
          end,
          p_currency_code => (v_data ->> 'currency_code')::char(3),
          p_exchange_rate => (v_data ->> 'exchange_rate')::numeric,
          p_description => v_data ->> 'description',
          p_reference => v_data ->> 'reference',
          p_counterparty_id => nullif(v_data ->> 'counterparty_id', '')::uuid,
          p_category_id => (v_data ->> 'category_id')::uuid,
          p_source => 'import',
          p_idempotency_key => 'csv-import:' || v_row.deterministic_key,
          p_metadata => jsonb_build_object('import_batch_id', p_batch_id,
                                            'import_row_number', v_row.row_number)
        );
        update public.import_rows set status = 'posted', transaction_id = v_transaction_id,
          attempt_count = attempt_count + 1, error_code = null, error_message = null
        where id = v_row.id;
      exception when others then
        v_error := sqlerrm;
        update public.import_rows set status = 'failed', attempt_count = attempt_count + 1,
          error_code = split_part(v_error, ':', 1), error_message = v_error
        where id = v_row.id;
      end;
    end loop;

    perform app.refresh_import_batch_counts(p_batch_id);
    select case when b.valid_rows = 0 and b.failed_rows = 0 and b.invalid_rows = 0
      then 'completed' else 'partial' end
      into v_status from public.import_batches b where b.id = p_batch_id;
    update public.import_batches set status = v_status, confirmed_by = auth.uid(),
      confirmed_at = now() where id = p_batch_id;

    perform app.write_audit(
      v_batch.organization_id, 'import.confirmed', 'import', p_batch_id,
      null, jsonb_build_object('status', v_status),
      jsonb_build_object('filename', v_batch.filename)
    );
  end if;

  select jsonb_build_object(
    'batch_id', b.id, 'status', b.status, 'total_rows', b.total_rows,
    'valid_rows', b.valid_rows, 'invalid_rows', b.invalid_rows,
    'posted_rows', b.posted_rows, 'duplicate_rows', b.duplicate_rows,
    'failed_rows', b.failed_rows
  ) into v_summary from public.import_batches b where b.id = p_batch_id;
  return v_summary;
end;
$$;

revoke all on function app.plan_feature_transition_lock_key(uuid),
  app.lock_plan_feature_transition(uuid),
  app.lock_all_plan_quotas(uuid),
  app.lock_subscription_plan_change()
from public, anon, authenticated;
