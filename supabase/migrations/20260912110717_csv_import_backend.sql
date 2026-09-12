-- CSV transaction imports are staged as tenant-owned data, validated row by
-- row, then confirmed through the ordinary posting engine. Raw client rows are
-- never allowed to write the ledger directly.

create table public.import_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  filename text not null,
  status text not null default 'staged'
    check (status in ('staged', 'validated', 'processing', 'completed', 'partial')),
  mapping jsonb,
  total_rows integer not null default 0 check (total_rows >= 0),
  valid_rows integer not null default 0 check (valid_rows >= 0),
  invalid_rows integer not null default 0 check (invalid_rows >= 0),
  posted_rows integer not null default 0 check (posted_rows >= 0),
  duplicate_rows integer not null default 0 check (duplicate_rows >= 0),
  failed_rows integer not null default 0 check (failed_rows >= 0),
  created_by uuid references public.profiles(id) on delete set null,
  confirmed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  validated_at timestamptz,
  confirmed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint import_batches_filename_length check (char_length(filename) between 1 and 255),
  constraint import_batches_id_org_unique unique (id, organization_id)
);

create table public.import_rows (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  batch_id uuid not null,
  row_number integer not null check (row_number > 0),
  raw_data jsonb not null check (jsonb_typeof(raw_data) = 'object'),
  normalized_data jsonb,
  status text not null default 'staged'
    check (status in ('staged', 'valid', 'invalid', 'posted', 'duplicate', 'failed')),
  deterministic_key text,
  error_code text,
  error_message text,
  transaction_id uuid,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint import_rows_batch_row_unique unique (batch_id, row_number),
  constraint import_rows_batch_same_org foreign key (batch_id, organization_id)
    references public.import_batches(id, organization_id) on delete cascade,
  constraint import_rows_transaction_same_org foreign key (transaction_id, organization_id)
    references public.transactions(id, organization_id) on delete restrict
);

create index import_batches_org_created_idx
  on public.import_batches(organization_id, created_at desc);
create index import_rows_batch_status_idx
  on public.import_rows(batch_id, status, row_number);
create index import_rows_org_key_idx
  on public.import_rows(organization_id, deterministic_key)
  where deterministic_key is not null;

create trigger import_batches_set_updated_at
  before update on public.import_batches
  for each row execute function app.set_updated_at();
create trigger import_rows_set_updated_at
  before update on public.import_rows
  for each row execute function app.set_updated_at();

alter table public.import_batches enable row level security;
alter table public.import_rows enable row level security;

create policy "import batches are readable by capable tenant members"
  on public.import_batches for select to authenticated
  using (
    app.is_org_member(organization_id)
    and app.has_capability(organization_id, 'imports.create')
  );
create policy "import rows are readable by capable tenant members"
  on public.import_rows for select to authenticated
  using (
    app.is_org_member(organization_id)
    and app.has_capability(organization_id, 'imports.create')
  );

revoke all on public.import_batches, public.import_rows from anon, authenticated;
grant select on public.import_batches, public.import_rows to authenticated;

create or replace function app.validate_csv_import_mapping(p_mapping jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
begin
  if p_mapping is null or jsonb_typeof(p_mapping) <> 'object' then
    raise exception 'IMPORT_MAPPING_INVALID: mapping must be an object'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_each(p_mapping) field
    where jsonb_typeof(field.value) <> 'string'
       or nullif(trim(field.value #>> '{}'), '') is null
  ) then
    raise exception 'IMPORT_MAPPING_INVALID: every mapped column must be a non-empty string'
      using errcode = '22023';
  end if;

  foreach v_key in array array['type', 'date', 'amount', 'account', 'category'] loop
    if jsonb_typeof(p_mapping -> v_key) <> 'string'
       or nullif(trim(p_mapping ->> v_key), '') is null then
      raise exception 'IMPORT_MAPPING_INVALID: % is required', v_key
        using errcode = '22023';
    end if;
  end loop;

  if exists (
    select 1 from jsonb_object_keys(p_mapping) key
    where key <> all (array[
      'type', 'date', 'amount', 'account', 'category', 'description',
      'reference', 'counterparty', 'currency', 'exchange_rate'
    ])
  ) then
    raise exception 'IMPORT_MAPPING_INVALID: unsupported target field'
      using errcode = '22023';
  end if;

  if exists (
    select value
    from jsonb_each_text(p_mapping)
    group by value having count(*) > 1
  ) then
    raise exception 'IMPORT_MAPPING_INVALID: one source column cannot map to multiple fields'
      using errcode = '22023';
  end if;
end;
$$;

create or replace function app.validate_csv_import_row(
  p_organization_id uuid,
  p_raw_data jsonb,
  p_mapping jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_type text := lower(trim(coalesce(p_raw_data ->> (p_mapping ->> 'type'), '')));
  v_date_text text := trim(coalesce(p_raw_data ->> (p_mapping ->> 'date'), ''));
  v_amount_text text := trim(coalesce(p_raw_data ->> (p_mapping ->> 'amount'), ''));
  v_account_text text := trim(coalesce(p_raw_data ->> (p_mapping ->> 'account'), ''));
  v_category_text text := trim(coalesce(p_raw_data ->> (p_mapping ->> 'category'), ''));
  v_counterparty_text text;
  v_currency_text text;
  v_rate_text text;
  v_date date;
  v_amount numeric;
  v_scaled numeric;
  v_amount_minor bigint;
  v_minor_unit smallint;
  v_account public.accounts%rowtype;
  v_category public.categories%rowtype;
  v_counterparty public.counterparties%rowtype;
  v_match_count integer;
  v_currency char(3);
  v_base char(3) := app.org_base_currency(p_organization_id);
  v_rate numeric;
  v_description text;
  v_reference text;
begin
  if v_type not in ('income', 'expense') then
    raise exception 'IMPORT_ROW_TYPE_INVALID: expected income or expense'
      using errcode = '22023';
  end if;

  if v_date_text !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'IMPORT_ROW_DATE_INVALID: expected YYYY-MM-DD'
      using errcode = '22023';
  end if;
  begin
    v_date := v_date_text::date;
  exception when others then
    raise exception 'IMPORT_ROW_DATE_INVALID: expected a real calendar date'
      using errcode = '22023';
  end;

  if v_account_text = '' then
    raise exception 'IMPORT_ROW_ACCOUNT_INVALID: account is required'
      using errcode = '22023';
  end if;
  select count(*) into v_match_count
  from public.accounts a
  where a.organization_id = p_organization_id
    and not a.is_archived
    and (a.id::text = v_account_text or lower(a.code) = lower(v_account_text)
         or lower(a.name) = lower(v_account_text));
  if v_match_count <> 1 then
    raise exception 'IMPORT_ROW_ACCOUNT_INVALID: account is missing or ambiguous'
      using errcode = '22023';
  end if;
  select * into strict v_account
  from public.accounts a
  where a.organization_id = p_organization_id
    and not a.is_archived
    and (a.id::text = v_account_text or lower(a.code) = lower(v_account_text)
         or lower(a.name) = lower(v_account_text))
  limit 1;
  if (v_type = 'income' and v_account.type <> 'asset')
     or (v_type = 'expense' and v_account.type not in ('asset', 'liability')) then
    raise exception 'IMPORT_ROW_ACCOUNT_INVALID: account type is not valid for %', v_type
      using errcode = '22023';
  end if;

  select count(*) into v_match_count
  from public.categories c
  where c.organization_id = p_organization_id and c.is_active
    and c.kind::text = v_type
    and (c.id::text = v_category_text or lower(c.name) = lower(v_category_text));
  if v_match_count <> 1 then
    raise exception 'IMPORT_ROW_CATEGORY_INVALID: category is missing or ambiguous'
      using errcode = '22023';
  end if;
  select * into strict v_category
  from public.categories c
  where c.organization_id = p_organization_id and c.is_active
    and c.kind::text = v_type
    and (c.id::text = v_category_text or lower(c.name) = lower(v_category_text))
  limit 1;

  v_currency_text := case when p_mapping ? 'currency'
    then nullif(upper(trim(p_raw_data ->> (p_mapping ->> 'currency'))), '') end;
  if v_currency_text is not null and v_currency_text !~ '^[A-Z]{3}$' then
    raise exception 'INVALID_CURRENCY: %', v_currency_text using errcode = '22023';
  end if;
  v_currency := coalesce(v_currency_text::char(3), v_account.currency);
  perform app.assert_write_currency(p_organization_id, v_currency);

  select c.minor_unit into v_minor_unit
  from public.currencies c where c.code = v_currency and c.is_active;
  if not found then
    raise exception 'INVALID_CURRENCY: %', v_currency using errcode = '22023';
  end if;
  if v_amount_text !~ '^\d+(\.\d+)?$' then
    raise exception 'IMPORT_ROW_AMOUNT_INVALID: amount must be positive'
      using errcode = '22023';
  end if;
  v_amount := v_amount_text::numeric;
  v_scaled := v_amount * power(10::numeric, v_minor_unit);
  if v_amount <= 0 or v_scaled <> trunc(v_scaled)
     or v_scaled > 9223372036854775807::numeric then
    raise exception 'IMPORT_ROW_AMOUNT_INVALID: amount has invalid precision or range'
      using errcode = '22023';
  end if;
  v_amount_minor := v_scaled::bigint;

  v_rate_text := case when p_mapping ? 'exchange_rate'
    then nullif(trim(p_raw_data ->> (p_mapping ->> 'exchange_rate')), '') end;
  if v_currency = v_base then
    v_rate := 1;
  elsif v_rate_text is null or v_rate_text !~ '^\d+(\.\d+)?$'
        or v_rate_text::numeric <= 0 then
    raise exception 'INVALID_EXCHANGE_RATE: % to %', v_currency, v_base
      using errcode = '22023';
  else
    v_rate := v_rate_text::numeric;
  end if;

  if p_mapping ? 'counterparty' then
    v_counterparty_text := nullif(trim(p_raw_data ->> (p_mapping ->> 'counterparty')), '');
  end if;
  if v_counterparty_text is not null then
    select count(*) into v_match_count
    from public.counterparties cp
    where cp.organization_id = p_organization_id and not cp.is_archived
      and (cp.id::text = v_counterparty_text or lower(cp.name) = lower(v_counterparty_text));
    if v_match_count <> 1 then
      raise exception 'IMPORT_ROW_COUNTERPARTY_INVALID: counterparty is missing or ambiguous'
        using errcode = '22023';
    end if;
    select * into strict v_counterparty
    from public.counterparties cp
    where cp.organization_id = p_organization_id and not cp.is_archived
      and (cp.id::text = v_counterparty_text or lower(cp.name) = lower(v_counterparty_text))
    limit 1;
  end if;

  v_description := case when p_mapping ? 'description'
    then nullif(trim(p_raw_data ->> (p_mapping ->> 'description')), '') end;
  v_reference := case when p_mapping ? 'reference'
    then nullif(trim(p_raw_data ->> (p_mapping ->> 'reference')), '') end;
  if char_length(v_description) > 1000 or char_length(v_reference) > 120 then
    raise exception 'IMPORT_ROW_TEXT_TOO_LONG: description or reference exceeds its limit'
      using errcode = '22023';
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'type', v_type, 'transaction_date', v_date, 'amount_minor', v_amount_minor,
    'account_id', v_account.id, 'category_id', v_category.id,
    'counterparty_id', v_counterparty.id, 'currency_code', v_currency,
    'exchange_rate', v_rate, 'description', v_description, 'reference', v_reference
  ));
end;
$$;

create or replace function app.refresh_import_batch_counts(p_batch_id uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update public.import_batches b set
    total_rows = counts.total_rows,
    valid_rows = counts.valid_rows,
    invalid_rows = counts.invalid_rows,
    posted_rows = counts.posted_rows,
    duplicate_rows = counts.duplicate_rows,
    failed_rows = counts.failed_rows
  from (
    select count(*)::integer total_rows,
      count(*) filter (where status = 'valid')::integer valid_rows,
      count(*) filter (where status = 'invalid')::integer invalid_rows,
      count(*) filter (where status = 'posted')::integer posted_rows,
      count(*) filter (where status = 'duplicate')::integer duplicate_rows,
      count(*) filter (where status = 'failed')::integer failed_rows
    from public.import_rows where batch_id = p_batch_id
  ) counts
  where b.id = p_batch_id;
$$;

-- Validation previews can become stale before confirmation. Recheck the
-- accounting meaning of the selected account and category immediately before
-- the low-level posting engine is called.
create or replace function app.assert_csv_import_posting_semantics(
  p_organization_id uuid,
  p_normalized_data jsonb
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_type text := p_normalized_data ->> 'type';
  v_account public.accounts%rowtype;
  v_category public.categories%rowtype;
  v_category_account public.accounts%rowtype;
  v_expected_category_type public.account_type;
begin
  if v_type = 'income' then
    v_account := app.require_account(
      p_organization_id, (p_normalized_data ->> 'account_id')::uuid,
      array['asset']::public.account_type[], 'import destination account'
    );
    v_expected_category_type := 'revenue';
  elsif v_type = 'expense' then
    v_account := app.require_account(
      p_organization_id, (p_normalized_data ->> 'account_id')::uuid,
      array['asset', 'liability']::public.account_type[], 'import source account'
    );
    v_expected_category_type := 'expense';
  else
    raise exception 'IMPORT_ROW_TYPE_INVALID: expected income or expense'
      using errcode = '22023';
  end if;
  if not v_account.is_active then
    raise exception 'IMPORT_ROW_ACCOUNT_INVALID: selected account is inactive'
      using errcode = '22023';
  end if;

  select * into v_category from public.categories c
  where c.id = (p_normalized_data ->> 'category_id')::uuid;
  if not found or v_category.organization_id <> p_organization_id then
    raise exception 'TENANT_ACCESS_DENIED: import category does not belong to this organization'
      using errcode = '42501';
  end if;
  if not v_category.is_active or v_category.kind::text <> v_type
     or v_category.default_account_id is null then
    raise exception 'IMPORT_ROW_CATEGORY_INVALID: category is inactive or has the wrong kind'
      using errcode = '22023';
  end if;

  select * into v_category_account from public.accounts a
  where a.id = v_category.default_account_id;
  if not found or v_category_account.organization_id <> p_organization_id then
    raise exception 'TENANT_ACCESS_DENIED: import category account does not belong to this organization'
      using errcode = '42501';
  end if;
  if not v_category_account.is_active or v_category_account.is_archived
     or v_category_account.type <> v_expected_category_type then
    raise exception 'IMPORT_ROW_CATEGORY_INVALID: category ledger account must be an active % account',
      v_expected_category_type
      using errcode = '22023';
  end if;
  return v_category_account.id;
end;
$$;

create or replace function public.create_csv_import_batch(
  p_organization_id uuid,
  p_filename text,
  p_rows jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch_id uuid;
  v_row jsonb;
  v_row_number integer := 0;
begin
  perform app.require_capability(p_organization_id, 'imports.create');
  perform app.assert_plan_feature(p_organization_id, 'imports');

  if p_filename is null or char_length(trim(p_filename)) not between 1 and 255
     or lower(trim(p_filename)) not like '%.csv' then
    raise exception 'IMPORT_FILE_INVALID: a CSV filename is required'
      using errcode = '22023';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array'
     or jsonb_array_length(p_rows) not between 1 and 10000 then
    raise exception 'IMPORT_FILE_INVALID: provide between 1 and 10000 rows'
      using errcode = '22023';
  end if;

  insert into public.import_batches(organization_id, filename, created_by)
  values (p_organization_id, trim(p_filename), auth.uid())
  returning id into v_batch_id;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_row_number := v_row_number + 1;
    if jsonb_typeof(v_row) <> 'object' or pg_column_size(v_row) > 65536 then
      raise exception 'IMPORT_FILE_INVALID: row % must be an object under 64 KiB', v_row_number
        using errcode = '22023';
    end if;
    insert into public.import_rows(organization_id, batch_id, row_number, raw_data)
    values (p_organization_id, v_batch_id, v_row_number, v_row);
  end loop;

  perform app.refresh_import_batch_counts(v_batch_id);
  return v_batch_id;
end;
$$;

create or replace function public.validate_csv_import_batch(
  p_batch_id uuid,
  p_mapping jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.import_batches%rowtype;
  v_row public.import_rows%rowtype;
  v_normalized jsonb;
  v_key text;
  v_error text;
begin
  select * into v_batch from public.import_batches b where b.id = p_batch_id for update;
  if not found then
    raise exception 'TENANT_ACCESS_DENIED: import batch not found' using errcode = '42501';
  end if;
  perform app.require_capability(v_batch.organization_id, 'imports.create');
  perform app.assert_plan_feature(v_batch.organization_id, 'imports');
  perform app.validate_csv_import_mapping(p_mapping);
  if exists (select 1 from public.import_rows r
             where r.batch_id = p_batch_id and r.status in ('posted', 'duplicate')) then
    raise exception 'IMPORT_BATCH_FINALIZED: posted rows cannot be remapped'
      using errcode = '23514';
  end if;

  update public.import_rows set status = 'staged', normalized_data = null,
    deterministic_key = null, error_code = null, error_message = null
  where batch_id = p_batch_id;

  for v_row in select * from public.import_rows r
               where r.batch_id = p_batch_id order by r.row_number for update loop
    begin
      v_normalized := app.validate_csv_import_row(
        v_batch.organization_id, v_row.raw_data, p_mapping
      );
      v_key := encode(extensions.digest(v_normalized::text, 'sha256'), 'hex');

      if exists (
        select 1 from public.transactions t
        where t.organization_id = v_batch.organization_id
          and t.idempotency_key = 'csv-import:' || v_key
      ) or exists (
        select 1 from public.import_rows prior
        where prior.batch_id = p_batch_id and prior.row_number < v_row.row_number
          and prior.deterministic_key = v_key and prior.status = 'valid'
      ) then
        update public.import_rows set status = 'duplicate', normalized_data = v_normalized,
          deterministic_key = v_key, error_code = 'IMPORT_ROW_DUPLICATE',
          error_message = 'An identical row already exists.' where id = v_row.id;
      else
        update public.import_rows set status = 'valid', normalized_data = v_normalized,
          deterministic_key = v_key where id = v_row.id;
      end if;
    exception when others then
      v_error := sqlerrm;
      update public.import_rows set status = 'invalid', error_code = split_part(v_error, ':', 1),
        error_message = v_error where id = v_row.id;
    end;
  end loop;

  update public.import_batches set status = 'validated', mapping = p_mapping,
    validated_at = now() where id = p_batch_id;
  perform app.refresh_import_batch_counts(p_batch_id);
  return p_batch_id;
end;
$$;

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

revoke all on function public.create_csv_import_batch(uuid, text, jsonb) from public, anon;
revoke all on function public.validate_csv_import_batch(uuid, jsonb) from public, anon;
revoke all on function public.confirm_csv_import_batch(uuid) from public, anon;
grant execute on function public.create_csv_import_batch(uuid, text, jsonb),
  public.validate_csv_import_batch(uuid, jsonb),
  public.confirm_csv_import_batch(uuid) to authenticated, service_role;

revoke all on function app.validate_csv_import_mapping(jsonb),
  app.validate_csv_import_row(uuid, jsonb, jsonb),
  app.assert_csv_import_posting_semantics(uuid, jsonb),
  app.refresh_import_batch_counts(uuid) from public, anon, authenticated;
