-- Regression coverage for Phase 1–3 closure work.
begin;

create extension if not exists pgtap with schema extensions;
select plan(13);

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

create temp table hardening_ids (key text primary key, value text);
grant all on hardening_ids to authenticated;

insert into hardening_ids values
  ('org', (select id::text from public.organizations where name = 'Alpha Trading'));
insert into hardening_ids values
  ('commitment', (select id::text from public.commitments
                  where organization_id = (select value::uuid from hardening_ids where key = 'org')
                    and settled_amount_minor = 0 limit 1)),
  ('rule', (select id::text from public.recurring_rules
            where organization_id = (select value::uuid from hardening_ids where key = 'org') limit 1)),
  ('bank', (select id::text from public.accounts
            where organization_id = (select value::uuid from hardening_ids where key = 'org')
              and system_key = 'bank'));

select throws_ok(
  format('update public.commitments set settled_amount_minor = amount_minor, status = %L where id = %L',
         'paid', (select value from hardening_ids where key = 'commitment')),
  '42501', null,
  'clients cannot forge commitment settlement state'
);

select throws_ok(
  format('update public.recurring_rules set template = %L::jsonb, occurrences_created = 999 where id = %L',
         '{}', (select value from hardening_ids where key = 'rule')),
  '42501', null,
  'clients cannot rewrite recurring templates or scheduler cursors'
);

select lives_ok(
  format('select public.update_commitment(%L, %L, p_notes => %L)',
         (select value from hardening_ids where key = 'commitment'),
         'Updated commitment', 'controlled edit'),
  'controlled commitment edits remain available'
);

select is(
  (select title from public.commitments where id =
    (select value::uuid from hardening_ids where key = 'commitment')),
  'Updated commitment',
  'controlled commitment edit persisted'
);

select lives_ok(
  format('select public.create_account(%L, %L, %L, %L, p_code => %L)',
         (select value from hardening_ids where key = 'org'),
         'Audit Test Bank', 'asset', 'bank', '1199'),
  'an authorized owner can create an account through the controlled RPC'
);

select is(
  (select count(*) from public.accounts
   where organization_id = (select value::uuid from hardening_ids where key = 'org')
     and code = '1199'),
  1::bigint,
  'controlled account creation writes one tenant-scoped account'
);

select lives_ok(
  format($fmt$select * from public.create_organization_invitation(%L, %L, 'viewer')$fmt$,
         (select value from hardening_ids where key = 'org'), 'owner@beta.test'),
  'an owner can create a controlled invitation'
);

insert into hardening_ids
select 'token', invitation_token
from public.create_organization_invitation(
  (select value::uuid from hardening_ids where key = 'org'),
  'new-invitee@ledgersuit.test', 'viewer'
);

reset role;
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at, confirmation_token, recovery_token,
                        email_change_token_new, email_change_token_current, email_change,
                        phone_change, phone_change_token, reauthentication_token)
values ('f0000000-0000-4000-8000-000000000001',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'new-invitee@ledgersuit.test', extensions.crypt('pw', extensions.gen_salt('bf')),
        now(), '{"provider":"email"}', '{}', now(), now(), '', '', '', '', '', '', '', '');

select set_config('request.jwt.claims',
  '{"sub":"f0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  format('select public.accept_organization_invitation(%L)',
         (select value from hardening_ids where key = 'token')),
  'the matching signed-in user can accept an invitation'
);

select is(
  (select count(*) from public.organization_members
   where organization_id = (select value::uuid from hardening_ids where key = 'org')
     and user_id = 'f0000000-0000-4000-8000-000000000001'),
  1::bigint,
  'accepting creates exactly one membership'
);

select throws_ok(
  format('select public.accept_organization_invitation(%L)',
         (select value from hardening_ids where key = 'token')),
  '42501', null,
  'an accepted token cannot be replayed'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  format('select public.mark_all_notifications_read(%L)',
         (select value from hardening_ids where key = 'org')),
  'notification read state is changed through its controlled RPC'
);

select throws_ok(
  format('update public.notifications set title = %L where organization_id = %L',
         'forged', (select value from hardening_ids where key = 'org')),
  '42501', null,
  'clients cannot rewrite notification content'
);

select is(
  (select count(*) from public.commitment_settlements s
   join public.commitments c on c.id = s.commitment_id
   where c.organization_id = (select value::uuid from hardening_ids where key = 'org')
     and c.status in ('partially_paid', 'paid')) > 0,
  true,
  'existing legitimate commitment settlements remain intact'
);

select * from finish();
rollback;
