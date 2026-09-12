-- Aggregate attachment quota reservations and recoverable storage lifecycle.
begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select plan(25);

create temp table storage_quota_ids (key text primary key, value uuid not null);
grant all on storage_quota_ids to authenticated, service_role;
insert into storage_quota_ids select 'alpha', id from public.organizations where name = 'Alpha Trading';
insert into storage_quota_ids select 'beta', id from public.organizations where name = 'Beta Supplies';

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from storage_quota_ids where key = 'alpha');
update public.subscription_entitlements set limit_value = 100
where plan_id = (select id from public.subscription_plans where key = 'solo')
  and feature_key = 'max_storage_bytes';

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

insert into storage_quota_ids values (
  'reservation', public.reserve_attachment_upload(
    (select value from storage_quota_ids where key = 'alpha'), 'organization',
    (select value from storage_quota_ids where key = 'alpha'), 'quota.pdf',
    'application/pdf', 60,
    (select value::text from storage_quota_ids where key = 'alpha') || '/organization/' ||
      (select value::text from storage_quota_ids where key = 'alpha') || '/quota.pdf'
  )
);

select is(public.get_usage(
  (select value from storage_quota_ids where key = 'alpha'), 'max_storage_bytes'),
  60::bigint, 'live reservations count toward aggregate storage usage');

select ok(app.storage_upload_matches_reservation(
  'attachments',
  (select value::text from storage_quota_ids where key = 'alpha') || '/organization/' ||
    (select value::text from storage_quota_ids where key = 'alpha') || '/quota.pdf',
  '{"size":60,"mimetype":"application/pdf"}'::jsonb
), 'the upload policy accepts the exact reserved key, size, and MIME type');

select ok(not app.storage_upload_matches_reservation(
  'attachments',
  (select value::text from storage_quota_ids where key = 'alpha') || '/organization/' ||
    (select value::text from storage_quota_ids where key = 'alpha') || '/quota.pdf',
  '{"size":59,"mimetype":"application/pdf"}'::jsonb
), 'the upload policy rejects mismatched object metadata');

select throws_ok(
  format($sql$select public.reserve_attachment_upload(%L, 'organization', %L,
    'over.pdf', 'application/pdf', 41, %L)$sql$,
    (select value from storage_quota_ids where key = 'alpha'),
    (select value from storage_quota_ids where key = 'alpha'),
    (select value::text from storage_quota_ids where key = 'alpha') || '/organization/' ||
      (select value::text from storage_quota_ids where key = 'alpha') || '/over.pdf'),
  'P0001', 'PLAN_STORAGE_LIMIT_REACHED: usage 60, requested 41, limit 100',
  'a second reservation cannot exceed the aggregate plan limit');

select throws_ok(
  format($sql$select public.reserve_attachment_upload(%L, 'organization', %L,
    'large.pdf', 'application/pdf', 26214401, %L)$sql$,
    (select value from storage_quota_ids where key = 'alpha'),
    (select value from storage_quota_ids where key = 'alpha'),
    (select value::text from storage_quota_ids where key = 'alpha') || '/organization/' ||
      (select value::text from storage_quota_ids where key = 'alpha') || '/large.pdf'),
  '22023', 'ATTACHMENT_INVALID: upload metadata is invalid',
  'the existing 25 MiB per-file limit remains enforced');

select throws_ok(
  format($sql$select public.reserve_attachment_upload(%L, 'organization', %L,
    'foreign.pdf', 'application/pdf', 1, %L)$sql$,
    (select value from storage_quota_ids where key = 'beta'),
    (select value from storage_quota_ids where key = 'beta'),
    (select value::text from storage_quota_ids where key = 'beta') || '/organization/' ||
      (select value::text from storage_quota_ids where key = 'beta') || '/foreign.pdf'),
  '42501', null, 'reservations preserve tenant isolation');

select ok(public.abort_attachment_upload(
  (select value from storage_quota_ids where key = 'reservation')),
  'a failed upload can abort its reservation');
select ok(public.abort_attachment_upload(
  (select value from storage_quota_ids where key = 'reservation')),
  'aborting a reservation is idempotent');
select is(public.get_usage(
  (select value from storage_quota_ids where key = 'alpha'), 'max_storage_bytes'),
  0::bigint, 'aborted reservations release capacity immediately');

insert into storage_quota_ids values (
  'commit', public.reserve_attachment_upload(
    (select value from storage_quota_ids where key = 'alpha'), 'organization',
    (select value from storage_quota_ids where key = 'alpha'), 'committed.pdf',
    'application/pdf', 50,
    (select value::text from storage_quota_ids where key = 'alpha') || '/organization/' ||
      (select value::text from storage_quota_ids where key = 'alpha') || '/committed.pdf'
  )
);
reset role;
insert into storage.objects (bucket_id, name, owner, metadata)
values ('attachments',
  (select value::text from storage_quota_ids where key = 'alpha') || '/organization/' ||
    (select value::text from storage_quota_ids where key = 'alpha') || '/committed.pdf',
  'a0000000-0000-4000-8000-000000000001',
  '{"size":49,"mimetype":"application/pdf"}');
set local role authenticated;

select throws_ok(
  format('select public.commit_attachment_upload(%L)',
    (select value from storage_quota_ids where key = 'commit')),
  'P0001', 'ATTACHMENT_STORAGE_OBJECT_MISMATCH:',
  'commit rejects storage metadata that differs from the reservation');
reset role;
update storage.objects set metadata = '{"size":50,"mimetype":"application/pdf"}'
where bucket_id = 'attachments'
  and name = (select value::text from storage_quota_ids where key = 'alpha') || '/organization/' ||
    (select value::text from storage_quota_ids where key = 'alpha') || '/committed.pdf';
set local role authenticated;

insert into storage_quota_ids values (
  'attachment', public.commit_attachment_upload(
    (select value from storage_quota_ids where key = 'commit'))
);
select is(public.commit_attachment_upload(
  (select value from storage_quota_ids where key = 'commit')),
  (select value from storage_quota_ids where key = 'attachment'),
  'committing an uploaded reservation is idempotent');
select is((select count(*) from public.attachments
  where id = (select value from storage_quota_ids where key = 'attachment')),
  1::bigint, 'commit creates one authoritative metadata row');
select is((select count(*) from public.audit_logs
  where action = 'attachment.upload'
    and entity_id = (select value from storage_quota_ids where key = 'attachment')),
  1::bigint, 'commit audits the upload once');
select is(public.get_usage(
  (select value from storage_quota_ids where key = 'alpha'), 'max_storage_bytes'),
  50::bigint, 'committed metadata replaces rather than duplicates reserved usage');

select is((select count(*) from public.begin_attachment_delete(
  (select value from storage_quota_ids where key = 'attachment'))),
  1::bigint, 'delete removes metadata and queues object cleanup atomically');
select is((select count(*) from public.attachments
  where id = (select value from storage_quota_ids where key = 'attachment')),
  0::bigint, 'metadata is gone even while object cleanup is pending');
select ok(app.storage_delete_allowed(
  'attachments',
  (select value::text from storage_quota_ids where key = 'alpha') || '/organization/' ||
    (select value::text from storage_quota_ids where key = 'alpha') || '/committed.pdf'),
  'the deleting user may remove a cleanup-pending object');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
set local role service_role;
select ok((select count(*) >= 2 from public.claim_attachment_storage_cleanup(100)),
  'the cleanup worker claims aborted and delete-pending objects');
select ok(public.complete_attachment_storage_cleanup(
  (select value from storage_quota_ids where key = 'commit'), null),
  'cleanup completion succeeds');
select ok(public.complete_attachment_storage_cleanup(
  (select value from storage_quota_ids where key = 'commit'), null),
  'cleanup completion is idempotent');

reset role;
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
where organization_id = (select value from storage_quota_ids where key = 'alpha');
insert into public.attachments (
  organization_id, entity_type, entity_id, file_name, mime_type, size_bytes, storage_key
) values (
  (select value from storage_quota_ids where key = 'alpha'), 'organization',
  (select value from storage_quota_ids where key = 'alpha'), 'legacy.pdf',
  'application/pdf', 101,
  (select value::text from storage_quota_ids where key = 'alpha') || '/legacy.pdf'
);
update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from storage_quota_ids where key = 'alpha');
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  format($sql$select public.reserve_attachment_upload(%L, 'organization', %L,
    'downgraded.pdf', 'application/pdf', 1, %L)$sql$,
    (select value from storage_quota_ids where key = 'alpha'),
    (select value from storage_quota_ids where key = 'alpha'),
    (select value::text from storage_quota_ids where key = 'alpha') || '/organization/' ||
      (select value::text from storage_quota_ids where key = 'alpha') || '/downgraded.pdf'),
  'P0001', 'PLAN_STORAGE_LIMIT_REACHED: usage 101, requested 1, limit 100',
  'an over-limit downgrade blocks new storage reservations');
select is((select count(*) from public.begin_attachment_delete(
  (select id from public.attachments where file_name = 'legacy.pdf'))),
  1::bigint, 'an over-limit organization can still delete existing metadata');

select throws_ok(
  format($sql$insert into public.attachments (
    organization_id, entity_type, entity_id, file_name, mime_type, size_bytes, storage_key
  ) values (%L, 'organization', %L, 'bypass.pdf', 'application/pdf', 1, %L)$sql$,
    (select value from storage_quota_ids where key = 'alpha'),
    (select value from storage_quota_ids where key = 'alpha'),
    (select value::text from storage_quota_ids where key = 'alpha') || '/bypass.pdf'),
  '42501', null, 'authenticated clients cannot bypass reservation commit with direct metadata inserts');

reset role;
select extensions.dblink_connect('storage_quota_1',
  format('host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()));
select extensions.dblink_connect('storage_quota_2',
  format('host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()));
create temp table storage_quota_concurrency_outcomes (outcome text not null);
select extensions.dblink_exec('storage_quota_1', $setup$
  create or replace function public.test_storage_quota_reserve(p_key text)
  returns text language plpgsql security definer set search_path = '' as $function$
  begin
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    perform public.reserve_attachment_upload(
      (select id from public.organizations where name = 'Beta Supplies'), 'organization',
      (select id from public.organizations where name = 'Beta Supplies'), p_key || '.pdf',
      'application/pdf', 20971520,
      (select id::text || '/organization/' || id::text from public.organizations
        where name = 'Beta Supplies') || '/concurrency/' || p_key || '.pdf');
    return 'success';
  exception when others then return sqlerrm;
  end;
  $function$;
  delete from app.attachment_storage_reservations where storage_key like
    (select id::text || '/organization/' || id::text from public.organizations
      where name = 'Beta Supplies') || '/concurrency/%';
  delete from public.attachments where storage_key like
    (select id::text || '/organization/' || id::text from public.organizations
      where name = 'Beta Supplies') || '/concurrency/%';
  update public.subscriptions set plan_id =
    (select id from public.subscription_plans where key = 'solo')
  where organization_id = (select id from public.organizations where name = 'Beta Supplies');
  insert into public.attachments (
    organization_id, entity_type, entity_id, file_name, mime_type, size_bytes, storage_key
  ) select o.id, 'organization', o.id, n || '.pdf', 'application/pdf', 26214400,
      o.id::text || '/organization/' || o.id::text || '/concurrency/committed-' || n || '.pdf'
    from public.organizations o cross join generate_series(1, 40) n
    where o.name = 'Beta Supplies';
$setup$);
select extensions.dblink_send_query('storage_quota_1',
  $$select public.test_storage_quota_reserve('race-1')$$);
select extensions.dblink_send_query('storage_quota_2',
  $$select public.test_storage_quota_reserve('race-2')$$);
insert into storage_quota_concurrency_outcomes
select outcome from extensions.dblink_get_result('storage_quota_1') as result(outcome text);
insert into storage_quota_concurrency_outcomes
select outcome from extensions.dblink_get_result('storage_quota_2') as result(outcome text);
select extensions.dblink_get_result('storage_quota_1');
select extensions.dblink_get_result('storage_quota_2');
select is((select count(*) from storage_quota_concurrency_outcomes where outcome = 'success'),
  1::bigint, 'concurrent reservations serialize so only one consumes the remaining capacity');
select is((select count(*) from storage_quota_concurrency_outcomes
  where outcome like 'PLAN_STORAGE_LIMIT_REACHED:%'),
  1::bigint, 'the competing reservation fails with the stable storage quota error');
select extensions.dblink_exec('storage_quota_1', $cleanup$
  delete from app.attachment_storage_reservations where storage_key like
    (select id::text || '/organization/' || id::text from public.organizations
      where name = 'Beta Supplies') || '/concurrency/%';
  delete from public.attachments where storage_key like
    (select id::text || '/organization/' || id::text from public.organizations
      where name = 'Beta Supplies') || '/concurrency/%';
  update public.subscriptions set plan_id =
    (select id from public.subscription_plans where key = 'ledger_suit')
  where organization_id = (select id from public.organizations where name = 'Beta Supplies');
  drop function public.test_storage_quota_reserve(text);
$cleanup$);
select extensions.dblink_disconnect('storage_quota_1');
select extensions.dblink_disconnect('storage_quota_2');

select * from finish();
rollback;
