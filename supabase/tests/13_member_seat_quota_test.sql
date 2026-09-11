-- Member-seat enforcement: active members plus live pending invitations.
begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select plan(32);

create temp table seat_test_ids (key text primary key, value uuid not null);
grant all on seat_test_ids to authenticated, service_role;

create temp table seat_test_invitations (
  key text primary key,
  invitation_id uuid not null,
  invitation_token text
);
grant all on seat_test_invitations to authenticated, service_role;

insert into seat_test_ids
select 'race_org', id
from public.organizations
where name = 'Beta Supplies';

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new,
  email_change_token_current, email_change, phone_change,
  phone_change_token, reauthentication_token
)
select
  ('f1000000-0000-4000-8000-' || lpad(ordinal::text, 12, '0'))::uuid,
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  email,
  extensions.crypt('member-seat-test', extensions.gen_salt('bf')),
  now(),
  '{"provider":"email"}'::jsonb,
  '{}'::jsonb,
  now(),
  now(),
  '', '', '', '', '', '', '', ''
from (values
  (1, 'solo-seat-owner@example.com'),
  (2, 'starter-seat-owner@example.com'),
  (3, 'business-seat-owner@example.com'),
  (5, 'reserved-seat-member@example.com'),
  (6, 'direct-seat-member@example.com')
) users(ordinal, email);

select set_config(
  'request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
insert into seat_test_ids values (
  'solo_org',
  public.create_organization('Solo Seat Boundary Co', 'EGP')
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;
insert into seat_test_ids values (
  'starter_org',
  public.create_organization('Starter Seat Boundary Co', 'EGP')
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;
insert into seat_test_ids values (
  'business_org',
  public.create_organization('Business Seat Boundary Co', 'EGP')
);

reset role;
set local role service_role;
update public.subscriptions subscription
set plan_id = plan.id
from public.subscription_plans plan
where subscription.organization_id in (
    (select value from seat_test_ids where key = 'solo_org'),
    (select value from seat_test_ids where key = 'starter_org'),
    (select value from seat_test_ids where key = 'business_org')
  )
  and plan.key = case subscription.organization_id
    when (select value from seat_test_ids where key = 'solo_org') then 'solo'
    when (select value from seat_test_ids where key = 'starter_org') then 'starter'
    when (select value from seat_test_ids where key = 'business_org') then 'business'
  end;

reset role;

select is(
  app.plan_quota_usage(
    (select value from seat_test_ids where key = 'solo_org'),
    'max_members'
  ),
  1::bigint,
  'the Solo owner consumes its only seat'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  format(
    'select * from public.create_organization_invitation(%L, %L, %L)',
    (select value from seat_test_ids where key = 'solo_org'),
    'solo-over-limit@example.com',
    'viewer'
  ),
  'P0001',
  'PLAN_MEMBER_LIMIT_REACHED: usage 1, requested 1, limit 1',
  'Solo rejects the first invitation above its one-seat boundary'
);

reset role;
set local role service_role;

select throws_ok(
  format(
    $$insert into public.organization_members (
        organization_id, user_id, role, status
      ) values (%L, %L, 'viewer', 'active')$$,
    (select value from seat_test_ids where key = 'solo_org'),
    'f1000000-0000-4000-8000-000000000006'
  ),
  'P0001',
  'PLAN_MEMBER_LIMIT_REACHED: usage 1, requested 1, limit 1',
  'the membership table trigger blocks privileged direct-insert bypasses'
);

select throws_ok(
  format(
    $$insert into public.organization_invitations (
        organization_id, email, token_hash, expires_at
      ) values (%L, %L, %L, now() + interval '1 day')$$,
    (select value from seat_test_ids where key = 'solo_org'),
    'solo-direct-over-limit@example.com',
    'solo-direct-over-limit'
  ),
  'P0001',
  'PLAN_MEMBER_LIMIT_REACHED: usage 1, requested 1, limit 1',
  'the invitation table trigger blocks privileged direct-insert bypasses'
);

with invitation as (
  insert into public.organization_invitations (
    organization_id, email, token_hash, expires_at
  ) values (
    (select value from seat_test_ids where key = 'solo_org'),
    'solo-expired@example.com',
    'solo-expired-seat',
    now() - interval '1 day'
  )
  returning id
)
insert into seat_test_invitations (key, invitation_id)
select 'expired', id from invitation;

reset role;
select is(
  app.plan_quota_usage(
    (select value from seat_test_ids where key = 'solo_org'),
    'max_members'
  ),
  1::bigint,
  'an expired pending invitation does not reserve a seat'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  format(
    'select * from public.renew_organization_invitation(%L)',
    (select invitation_id from seat_test_invitations where key = 'expired')
  ),
  'P0001',
  'PLAN_MEMBER_LIMIT_REACHED: usage 1, requested 1, limit 1',
  'renewing an expired invitation must reacquire seat capacity'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select * from public.create_organization_invitation(%L, %L, %L)',
    (select value from seat_test_ids where key = 'starter_org'),
    'starter-seat-two@example.com',
    'viewer'
  ),
  'Starter permits its second consumed seat'
);

insert into seat_test_invitations
select 'accept', invitation_id, invitation_token
from public.create_organization_invitation(
  (select value from seat_test_ids where key = 'starter_org'),
  'reserved-seat-member@example.com',
  'viewer'
);

select is(
  public.get_usage(
    (select value from seat_test_ids where key = 'starter_org'),
    'max_members'
  ),
  3::bigint,
  'Starter reaches its exact three-seat boundary with two live invitations'
);

select throws_ok(
  format(
    'select * from public.create_organization_invitation(%L, %L, %L)',
    (select value from seat_test_ids where key = 'starter_org'),
    'starter-seat-four@example.com',
    'viewer'
  ),
  'P0001',
  'PLAN_MEMBER_LIMIT_REACHED: usage 3, requested 1, limit 3',
  'Starter rejects a fourth consumed seat'
);

select lives_ok(
  format(
    'select * from public.renew_organization_invitation(%L)',
    (select id from public.organization_invitations
     where organization_id = (select value from seat_test_ids where key = 'starter_org')
       and email = 'starter-seat-two@example.com')
  ),
  'renewing a still-live invitation does not consume another seat'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select public.accept_organization_invitation(%L)',
    (select invitation_token from seat_test_invitations where key = 'accept')
  ),
  'acceptance converts a reserved seat at the exact limit'
);

select is(
  (select status::text
   from public.organization_invitations
   where id = (select invitation_id from seat_test_invitations where key = 'accept')),
  'accepted',
  'acceptance consumes the invitation reservation'
);

select is(
  (select status::text
   from public.organization_members
   where organization_id = (select value from seat_test_ids where key = 'starter_org')
     and user_id = 'f1000000-0000-4000-8000-000000000005'),
  'active',
  'acceptance creates the active member'
);

select is(
  public.get_usage(
    (select value from seat_test_ids where key = 'starter_org'),
    'max_members'
  ),
  3::bigint,
  'acceptance keeps seat usage constant'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    $$select public.manage_organization_member(
        %L, 'viewer', 'suspended', '{}', '{}'
      )$$,
    (select id from public.organization_members
     where organization_id = (select value from seat_test_ids where key = 'starter_org')
       and user_id = 'f1000000-0000-4000-8000-000000000005')
  ),
  'suspension remains available at the limit'
);

insert into seat_test_ids
select 'replacement_invitation', invitation_id
from public.create_organization_invitation(
  (select value from seat_test_ids where key = 'starter_org'),
  'starter-replacement@example.com',
  'viewer'
);

select throws_ok(
  format(
    $$select public.manage_organization_member(
        %L, 'viewer', 'active', '{}', '{}'
      )$$,
    (select id from public.organization_members
     where organization_id = (select value from seat_test_ids where key = 'starter_org')
       and user_id = 'f1000000-0000-4000-8000-000000000005')
  ),
  'P0001',
  'PLAN_MEMBER_LIMIT_REACHED: usage 3, requested 1, limit 3',
  'suspended-to-active transitions cannot exceed the seat limit'
);

select lives_ok(
  format(
    'select public.revoke_organization_invitation(%L)',
    (select value from seat_test_ids where key = 'replacement_invitation')
  ),
  'revoking an invitation remains available at the limit'
);

select lives_ok(
  format(
    $$select public.manage_organization_member(
        %L, 'viewer', 'active', '{}', '{}'
      )$$,
    (select id from public.organization_members
     where organization_id = (select value from seat_test_ids where key = 'starter_org')
       and user_id = 'f1000000-0000-4000-8000-000000000005')
  ),
  'reactivation succeeds after capacity is released'
);

reset role;
set local role service_role;
insert into public.organization_members (
  organization_id, user_id, role, status
) values (
  (select value from seat_test_ids where key = 'starter_org'),
  'f1000000-0000-4000-8000-000000000006',
  'viewer',
  'suspended'
);

update public.subscriptions
set plan_id = (select id from public.subscription_plans where key = 'solo')
where organization_id = (select value from seat_test_ids where key = 'starter_org');

select ok(
  (select is_over_limit
   from public.subscription_usage_summary(
     (select value from seat_test_ids where key = 'starter_org')
   )
   where quota_key = 'max_members'),
  'downgrade reports existing seat usage as over the new limit'
);

select is(
  (select count(*)
   from public.organization_members
   where organization_id = (select value from seat_test_ids where key = 'starter_org')),
  3::bigint,
  'downgrade preserves active and suspended membership rows'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select public.remove_organization_member(%L)',
    (select id from public.organization_members
     where organization_id = (select value from seat_test_ids where key = 'starter_org')
       and user_id = 'f1000000-0000-4000-8000-000000000006')
  ),
  'removing a suspended member remains available while downgraded over limit'
);

select lives_ok(
  format(
    'select public.revoke_organization_invitation(%L)',
    (select id from public.organization_invitations
     where organization_id = (select value from seat_test_ids where key = 'starter_org')
       and status = 'pending'
       and expires_at > now()
     limit 1)
  ),
  'revocation remains available while downgraded over limit'
);

select lives_ok(
  format(
    $$select public.manage_organization_member(
        %L, 'viewer', 'suspended', '{}', '{}'
      )$$,
    (select id from public.organization_members
     where organization_id = (select value from seat_test_ids where key = 'starter_org')
       and user_id = 'f1000000-0000-4000-8000-000000000005')
  ),
  'suspension remains available while downgraded over limit'
);

select is(
  (select count(*)
   from public.organization_members
   where organization_id = (select value from seat_test_ids where key = 'starter_org')),
  2::bigint,
  'safe reduction actions change only the selected membership rows'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    $$do $block$ begin
      for seat_number in 2..10 loop
        perform * from public.create_organization_invitation(
          %L,
          format('business-seat-%%s@example.com', seat_number),
          'viewer'
        );
      end loop;
    end $block$;$$,
    (select value from seat_test_ids where key = 'business_org')
  ),
  'Business permits nine reservations after its owner'
);

select is(
  public.get_usage(
    (select value from seat_test_ids where key = 'business_org'),
    'max_members'
  ),
  10::bigint,
  'Business reaches its exact ten-seat boundary'
);

select throws_ok(
  format(
    'select * from public.create_organization_invitation(%L, %L, %L)',
    (select value from seat_test_ids where key = 'business_org'),
    'business-seat-eleven@example.com',
    'viewer'
  ),
  'P0001',
  'PLAN_MEMBER_LIMIT_REACHED: usage 10, requested 1, limit 10',
  'Business rejects an eleventh consumed seat'
);

-- Use a committed seed workspace so independent database sessions can observe
-- the same fixture. Restore it explicitly before the test finishes.
reset role;
select extensions.dblink_connect(
  'seat_race_1',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);
select extensions.dblink_connect(
  'seat_race_2',
  format(
    'host=%s port=%s dbname=postgres user=postgres password=postgres',
    inet_server_addr(), inet_server_port()
  )
);

select extensions.dblink_exec(
  'seat_race_1',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'starter')
      where organization_id = %L$$,
    (select value from seat_test_ids where key = 'race_org')
  )
);
select extensions.dblink_exec(
  'seat_race_1',
  format(
    $$insert into public.organization_invitations (
        organization_id, email, token_hash, expires_at
      ) values (%L, 'race-reserved@example.com', 'race-reserved', now() + interval '1 day')$$,
    (select value from seat_test_ids where key = 'race_org')
  )
);

select extensions.dblink_exec('seat_race_1', 'begin');
select extensions.dblink_exec(
  'seat_race_1',
  format(
    $$do $block$ begin
      perform app.lock_plan_quota(%L, 'max_members');
    end $block$;$$,
    (select value from seat_test_ids where key = 'race_org')
  )
);
select extensions.dblink_exec(
  'seat_race_1',
  $$do $block$ begin
      perform set_config(
        'request.jwt.claims',
        '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
        false
      );
    end $block$;$$
);
select extensions.dblink_exec('seat_race_1', 'set role authenticated');

select extensions.dblink_exec(
  'seat_race_2',
  $$do $block$ begin
      perform set_config(
        'request.jwt.claims',
        '{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}',
        false
      );
    end $block$;$$
);
select extensions.dblink_exec('seat_race_2', 'set role authenticated');
select extensions.dblink_send_query(
  'seat_race_2',
  format(
    'select * from public.create_organization_invitation(%L, %L, %L)',
    (select value from seat_test_ids where key = 'race_org'),
    'race-loser@example.com',
    'viewer'
  )
);

select is(
  extensions.dblink_is_busy('seat_race_2'),
  1,
  'the concurrent invitation waits on the organization seat lock'
);

select lives_ok(
  format(
    $$select * from extensions.dblink(
        'seat_race_1',
        %L
      ) as invitation(invitation_id uuid, invitation_token text)$$,
    format(
      'select * from public.create_organization_invitation(%L, %L, %L)',
      (select value from seat_test_ids where key = 'race_org'),
      'race-winner@example.com',
      'viewer'
    )
  ),
  'the lock owner consumes the final available seat'
);

select extensions.dblink_exec('seat_race_1', 'commit');
select *
from extensions.dblink_get_result('seat_race_2', false)
  as result(invitation_id uuid, invitation_token text);

select is(
  (select count(*)
   from public.organization_invitations
   where organization_id = (select value from seat_test_ids where key = 'race_org')
     and status = 'pending'
     and expires_at > now()),
  2::bigint,
  'only one of two concurrent requests can consume the final seat'
);

select ok(
  extensions.dblink_error_message('seat_race_2')
    like '%PLAN_MEMBER_LIMIT_REACHED:%',
  'the losing concurrent request receives the stable member-limit error'
);

select is(
  app.plan_quota_usage(
    (select value from seat_test_ids where key = 'race_org'),
    'max_members'
  ),
  3::bigint,
  'concurrent requests cannot overbook the Starter seat limit'
);

select extensions.dblink_exec('seat_race_1', 'reset role');
select extensions.dblink_exec(
  'seat_race_1',
  format(
    $$delete from public.organization_invitations
      where organization_id = %L
        and email in ('race-reserved@example.com', 'race-winner@example.com', 'race-loser@example.com')$$,
    (select value from seat_test_ids where key = 'race_org')
  )
);
select extensions.dblink_exec(
  'seat_race_1',
  format(
    $$update public.subscriptions
      set plan_id = (select id from public.subscription_plans where key = 'ledger_suit')
      where organization_id = %L$$,
    (select value from seat_test_ids where key = 'race_org')
  )
);

select extensions.dblink_disconnect('seat_race_1');
select extensions.dblink_disconnect('seat_race_2');

select * from finish();
rollback;
