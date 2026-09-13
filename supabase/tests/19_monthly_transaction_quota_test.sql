-- Monthly posted business-transaction quota and immutable usage buckets.
begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select plan(23);

create temp table transaction_quota_ids (key text primary key, value uuid not null);
insert into transaction_quota_ids
select 'org', id from public.organizations where name = 'Alpha Trading';

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from transaction_quota_ids where key = 'org');
update public.subscription_entitlements set limit_value = 10
where plan_id = (select id from public.subscription_plans where key = 'solo')
  and feature_key = 'max_monthly_transactions';

select is(app.plan_quota_usage(
  (select value from transaction_quota_ids where key = 'org'),
  'max_monthly_transactions'), 0::bigint,
  'a workspace with no postings starts at zero usage');

insert into public.transactions (
  organization_id, type, status, source, transaction_date, posting_date,
  currency_code, exchange_rate, posted_at, description
)
select
  (select value from transaction_quota_ids where key = 'org'),
  case when source = 'reversal' then 'reversal' else 'income' end::public.transaction_type,
  'posted', source, date '2000-01-01', current_date, 'EGP', 1, now(),
  'Quota source ' || source
from unnest(enum_range(null::public.transaction_source)) source;

select is(app.plan_quota_usage(
  (select value from transaction_quota_ids where key = 'org'),
  'max_monthly_transactions'), 7::bigint,
  'all posting sources consume one business transaction each');
select is((select count(distinct source) from public.transactions
  where description like 'Quota source %'), 7::bigint,
  'manual, import, recurring, commitment, reversal, opening balance, and API sources share the boundary');
select is((select timezone from app.transaction_usage_buckets
  where organization_id = (select value from transaction_quota_ids where key = 'org')
    and now() >= bucket_start and now() < bucket_end),
  'Africa/Cairo', 'usage months freeze the workspace timezone used to create their boundaries');
select is((select count(*) from public.transaction_entries
  where transaction_id in (select id from public.transactions where description like 'Quota source %')),
  0::bigint, 'usage counts business transactions rather than ledger entries');

insert into public.transactions (
  organization_id, type, status, source, transaction_date, currency_code,
  exchange_rate, description, voided_at
) values
  ((select value from transaction_quota_ids where key = 'org'), 'income', 'draft',
   'manual', current_date, 'EGP', 1, 'Quota draft', null),
  ((select value from transaction_quota_ids where key = 'org'), 'income', 'failed',
   'manual', current_date, 'EGP', 1, 'Quota failed', null),
  ((select value from transaction_quota_ids where key = 'org'), 'income', 'voided',
   'manual', current_date, 'EGP', 1, 'Quota voided', now());
select is(app.plan_quota_usage(
  (select value from transaction_quota_ids where key = 'org'),
  'max_monthly_transactions'), 7::bigint,
  'draft, failed, and never-posted void transactions consume nothing');

insert into public.transactions (
  id, organization_id, type, status, source, transaction_date, currency_code,
  exchange_rate, description, idempotency_key
) values (
  '19000000-0000-4000-8000-000000000010',
  (select value from transaction_quota_ids where key = 'org'), 'income', 'draft',
  'manual', current_date - 3650, 'EGP', 1, 'Quota transition', 'quota-transition'
);

update public.transactions set status = 'posted', posted_at = now(), posting_date = current_date
where id = '19000000-0000-4000-8000-000000000010';
select is(app.plan_quota_usage(
  (select value from transaction_quota_ids where key = 'org'),
  'max_monthly_transactions'), 8::bigint,
  'backdated accounting dates consume the month in which posting occurs');

update public.transactions set status = 'posted'
where id = '19000000-0000-4000-8000-000000000010';
select is(app.plan_quota_usage(
  (select value from transaction_quota_ids where key = 'org'),
  'max_monthly_transactions'), 8::bigint,
  'replaying an already-posted transition does not consume twice');

select throws_ok($sql$
  do $rollback$ begin
    insert into public.transactions (
      organization_id, type, status, source, transaction_date, posting_date,
      currency_code, exchange_rate, posted_at, description
    ) values (
      (select value from transaction_quota_ids where key = 'org'), 'income',
      'posted', 'manual', current_date, current_date, 'EGP', 1, now(), 'Quota rollback'
    );
    raise exception 'QUOTA_ROLLBACK_TEST';
  end $rollback$;
$sql$, 'P0001', 'QUOTA_ROLLBACK_TEST',
  'a failed posting rolls its bucket increment back atomically');
select is(app.plan_quota_usage(
  (select value from transaction_quota_ids where key = 'org'),
  'max_monthly_transactions'), 8::bigint,
  'rolled-back postings leave usage unchanged');

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from transaction_quota_ids where key = 'org');
insert into public.transactions (
  organization_id, type, status, source, transaction_date, posting_date,
  currency_code, exchange_rate, posted_at, description
)
select (select value from transaction_quota_ids where key = 'org'), 'income',
  'posted', 'manual', current_date, current_date, 'EGP', 1, now(), 'Quota boundary ' || n
from generate_series(9, 10) n;
select is(app.plan_quota_usage(
  (select value from transaction_quota_ids where key = 'org'),
  'max_monthly_transactions'), 10::bigint,
  'the exact monthly boundary is permitted');
select throws_ok(
  format($sql$insert into public.transactions (
    organization_id, type, status, source, transaction_date, posting_date,
    currency_code, exchange_rate, posted_at, description
  ) values (%L, 'income', 'posted', 'manual', current_date, current_date,
    'EGP', 1, now(), 'Quota blocked')$sql$,
    (select value from transaction_quota_ids where key = 'org')),
  'P0001', 'PLAN_TRANSACTION_LIMIT_REACHED: usage 10, requested 1, limit 10',
  'the next posting is rejected with the stable plan error');

insert into public.transactions (
  organization_id, type, status, source, transaction_date, posting_date,
  currency_code, exchange_rate, posted_at, description
) values (
  (select value from transaction_quota_ids where key = 'org'), 'income', 'posted',
  'manual', current_date, current_date, 'EGP', 1, now() + interval '1 month',
  'Quota next month'
);
select is((select used_value from app.transaction_usage_buckets
  where organization_id = (select value from transaction_quota_ids where key = 'org')
    and now() + interval '1 month' >= bucket_start
    and now() + interval '1 month' < bucket_end),
  1::bigint, 'a new workspace-calendar month starts with fresh capacity');
select is(app.plan_quota_usage(
  (select value from transaction_quota_ids where key = 'org'),
  'max_monthly_transactions'), 10::bigint,
  'future-month usage does not alter the active month');
select throws_ok(
  format($sql$update app.transaction_usage_buckets set bucket_end = bucket_end + interval '1 day'
    where organization_id = %L and now() >= bucket_start and now() < bucket_end$sql$,
    (select value from transaction_quota_ids where key = 'org')),
  '42501', 'TRANSACTION_USAGE_BUCKET_IMMUTABLE:',
  'created usage-month boundaries cannot be rewritten');

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from transaction_quota_ids where key = 'org');
insert into public.transactions (
  organization_id, type, status, source, transaction_date, posting_date,
  currency_code, exchange_rate, posted_at, description
)
select (select value from transaction_quota_ids where key = 'org'), 'income',
  'posted', 'manual', current_date, current_date, 'EGP', 1, now(), 'Quota downgrade ' || n
from generate_series(11, 12) n;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from transaction_quota_ids where key = 'org');
select is(app.plan_quota_usage(
  (select value from transaction_quota_ids where key = 'org'),
  'max_monthly_transactions'), 12::bigint,
  'downgrade preserves historical rows and reports over-limit usage');
select throws_ok(
  format($sql$insert into public.transactions (
    organization_id, type, status, source, transaction_date, posting_date,
    currency_code, exchange_rate, posted_at
  ) values (%L, 'income', 'posted', 'manual', current_date, current_date,
    'EGP', 1, now())$sql$,
    (select value from transaction_quota_ids where key = 'org')),
  'P0001', 'PLAN_TRANSACTION_LIMIT_REACHED: usage 12, requested 1, limit 10',
  'an over-limit downgrade blocks only new postings');
select is((select count(*) from public.transactions
  where organization_id = (select value from transaction_quota_ids where key = 'org')
    and posted_at is not null and posted_at <= now()),
  12::bigint, 'quota enforcement never deletes existing transaction history');

-- A timezone change may create a shortened bridge between reset boundaries,
-- but that bridge must retain the preceding bucket's consumed allowance.
insert into public.organizations (
  id, name, slug, country_code, timezone, base_currency, created_by
) values (
  '19000000-0000-4000-8000-000000000020', 'Timezone Quota Safety',
  'timezone-quota-safety', 'EG', 'Africa/Cairo', 'EGP',
  'b0000000-0000-4000-8000-000000000001'
);
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = '19000000-0000-4000-8000-000000000020';
insert into public.transactions (
  organization_id, type, status, source, transaction_date, posting_date,
  currency_code, exchange_rate, posted_at, description
)
select '19000000-0000-4000-8000-000000000020', 'income', 'posted', 'manual',
  date '2026-09-30', date '2026-09-30', 'EGP', 1,
  timestamptz '2026-09-30 20:30:00+00', 'Cairo quota ' || n
from generate_series(1, 10) n;
select is((select used_value from app.transaction_usage_buckets
  where organization_id = '19000000-0000-4000-8000-000000000020'
    and timestamptz '2026-09-30 20:30:00+00' >= bucket_start
    and timestamptz '2026-09-30 20:30:00+00' < bucket_end),
  10::bigint, 'the Africa/Cairo month is filled to its exact limit');

update public.organizations set timezone = 'Pacific/Honolulu'
where id = '19000000-0000-4000-8000-000000000020';
select throws_ok($sql$
  insert into public.transactions (
    organization_id, type, status, source, transaction_date, posting_date,
    currency_code, exchange_rate, posted_at, description
  ) values (
    '19000000-0000-4000-8000-000000000020', 'income', 'posted', 'manual',
    date '2026-09-30', date '2026-09-30', 'EGP', 1,
    timestamptz '2026-09-30 22:00:00+00', 'Blocked timezone bridge'
  )
$sql$, 'P0001', 'PLAN_TRANSACTION_LIMIT_REACHED: usage 10, requested 1, limit 10',
  'a shortened Honolulu transition bucket does not grant fresh quota');

insert into public.transactions (
  organization_id, type, status, source, transaction_date, posting_date,
  currency_code, exchange_rate, posted_at, description
) values (
  '19000000-0000-4000-8000-000000000020', 'income', 'posted', 'manual',
  date '2026-10-01', date '2026-10-01', 'EGP', 1,
  timestamptz '2026-10-01 10:01:00+00', 'Honolulu legitimate reset'
);
select is((select used_value from app.transaction_usage_buckets
  where organization_id = '19000000-0000-4000-8000-000000000020'
    and bucket_start = timestamptz '2026-10-01 10:00:00+00'),
  1::bigint, 'fresh capacity begins only at Honolulu''s legitimate month boundary');

-- Two independent sessions race for Solo's five-hundredth slot.
select extensions.dblink_connect('transaction_quota_1',
  format('host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()));
select extensions.dblink_connect('transaction_quota_2',
  format('host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()));
create temp table transaction_quota_outcomes (outcome text not null);
select extensions.dblink_exec('transaction_quota_1', $setup$
  set session_replication_role = replica;
  delete from public.transaction_entries where organization_id = '19000000-0000-4000-8000-000000000001';
  delete from public.transactions where organization_id = '19000000-0000-4000-8000-000000000001';
  delete from public.accounts where organization_id = '19000000-0000-4000-8000-000000000001';
  delete from app.transaction_usage_buckets where organization_id = '19000000-0000-4000-8000-000000000001';
  delete from public.subscriptions where organization_id = '19000000-0000-4000-8000-000000000001';
  delete from public.organizations where id = '19000000-0000-4000-8000-000000000001';
  set session_replication_role = origin;
  drop function if exists public.test_consume_transaction_quota(uuid);
  insert into public.organizations (
    id, name, slug, country_code, timezone, base_currency, created_by
  ) values (
    '19000000-0000-4000-8000-000000000001', 'Transaction Quota Race',
    'transaction-quota-race', 'EG', 'Africa/Cairo', 'EGP',
    'b0000000-0000-4000-8000-000000000001'
  );
  update public.subscriptions set plan_id =
    (select id from public.subscription_plans where key = 'ledger_suit')
  where organization_id = '19000000-0000-4000-8000-000000000001';
  set session_replication_role = replica;
  insert into public.accounts (
    id, organization_id, name, type, subtype, currency
  ) values
    ('19000000-0000-4000-8000-000000000004', '19000000-0000-4000-8000-000000000001',
     'Race debit', 'asset', 'bank', 'EGP'),
    ('19000000-0000-4000-8000-000000000005', '19000000-0000-4000-8000-000000000001',
     'Race credit', 'revenue', 'other_income', 'EGP');
  insert into public.transactions (
    organization_id, type, status, source, transaction_date, posting_date,
    currency_code, exchange_rate, posted_at, description
  ) select '19000000-0000-4000-8000-000000000001', 'income', 'posted', 'api',
    current_date, current_date, 'EGP', 1, now(), 'Race seed ' || n
  from generate_series(1, 499) n;
  insert into public.transactions (
    id, organization_id, type, status, source, transaction_date,
    currency_code, exchange_rate, description
  ) values
    ('19000000-0000-4000-8000-000000000002', '19000000-0000-4000-8000-000000000001',
     'income', 'draft', 'api', current_date, 'EGP', 1, 'Race one'),
    ('19000000-0000-4000-8000-000000000003', '19000000-0000-4000-8000-000000000001',
     'income', 'draft', 'api', current_date, 'EGP', 1, 'Race two');
  insert into public.transaction_entries (
    organization_id, transaction_id, account_id, entry_index, side,
    amount_minor, currency_code, base_amount_minor, base_currency_code,
    exchange_rate, entry_date
  ) select
    '19000000-0000-4000-8000-000000000001', transaction_id,
    case side when 'debit' then '19000000-0000-4000-8000-000000000004'::uuid
      else '19000000-0000-4000-8000-000000000005'::uuid end,
    case side when 'debit' then 0 else 1 end,
    side::public.entry_side, 100, 'EGP', 100, 'EGP', 1, current_date
  from (values
    ('19000000-0000-4000-8000-000000000002'::uuid),
    ('19000000-0000-4000-8000-000000000003'::uuid)
  ) transaction_ids(transaction_id)
  cross join (values ('debit'), ('credit')) sides(side);
  insert into app.transaction_usage_buckets (
    organization_id, bucket_start, bucket_end, timezone, used_value
  ) select '19000000-0000-4000-8000-000000000001',
    bounds.bucket_start, bounds.bucket_end, bounds.timezone, 499
  from app.transaction_usage_month_bounds(
    '19000000-0000-4000-8000-000000000001', now()
  ) bounds;
  set session_replication_role = origin;
  update public.subscriptions set plan_id =
    (select id from public.subscription_plans where key = 'solo')
  where organization_id = '19000000-0000-4000-8000-000000000001';
  create or replace function public.test_consume_transaction_quota(p_id uuid)
  returns text language plpgsql security definer set search_path = '' as $function$
  begin
    update public.transactions set status = 'posted', posted_at = now(),
      posting_date = current_date where id = p_id;
    return 'success';
  exception when others then return sqlerrm;
  end;
  $function$;
$setup$);
select extensions.dblink_send_query('transaction_quota_1',
  $$select public.test_consume_transaction_quota('19000000-0000-4000-8000-000000000002')$$);
select extensions.dblink_send_query('transaction_quota_2',
  $$select public.test_consume_transaction_quota('19000000-0000-4000-8000-000000000003')$$);
insert into transaction_quota_outcomes
select outcome from extensions.dblink_get_result('transaction_quota_1') as result(outcome text);
insert into transaction_quota_outcomes
select outcome from extensions.dblink_get_result('transaction_quota_2') as result(outcome text);
select extensions.dblink_get_result('transaction_quota_1');
select extensions.dblink_get_result('transaction_quota_2');
select is((select count(*) from transaction_quota_outcomes where outcome = 'success'),
  1::bigint, 'concurrent postings serialize so only one consumes the final slot');
select is((select count(*) from transaction_quota_outcomes
  where outcome like 'PLAN_TRANSACTION_LIMIT_REACHED:%'),
  1::bigint, 'the competing posting receives the stable quota error');
select extensions.dblink_exec('transaction_quota_1', $cleanup$
  set session_replication_role = replica;
  delete from public.transaction_entries where organization_id = '19000000-0000-4000-8000-000000000001';
  delete from public.transactions where organization_id = '19000000-0000-4000-8000-000000000001';
  delete from public.accounts where organization_id = '19000000-0000-4000-8000-000000000001';
  delete from app.transaction_usage_buckets where organization_id = '19000000-0000-4000-8000-000000000001';
  delete from public.subscriptions where organization_id = '19000000-0000-4000-8000-000000000001';
  delete from public.organizations where id = '19000000-0000-4000-8000-000000000001';
  set session_replication_role = origin;
  drop function public.test_consume_transaction_quota(uuid);
$cleanup$);
select extensions.dblink_disconnect('transaction_quota_1');
select extensions.dblink_disconnect('transaction_quota_2');

select * from finish();
rollback;
