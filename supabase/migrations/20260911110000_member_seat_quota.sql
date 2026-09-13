-- Enforce workspace seats at the database boundary. A seat is consumed by an
-- active member or by an unexpired pending invitation, so every transition
-- that increases either population must share the same organization lock.

create index if not exists organization_members_active_org_idx
  on public.organization_members (organization_id)
  where status = 'active';

create index if not exists organization_invitations_live_org_expiry_idx
  on public.organization_invitations (organization_id, expires_at)
  where status = 'pending';

create or replace function app.enforce_member_seat_on_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old_consumed boolean := false;
begin
  if tg_op = 'UPDATE' then
    v_old_consumed := old.status = 'active'
      and old.organization_id = new.organization_id;
  end if;

  if new.status = 'active' and not v_old_consumed then
    perform app.assert_plan_quota(new.organization_id, 'max_members');
  end if;

  return new;
end;
$$;

comment on function app.enforce_member_seat_on_membership() is
  'Blocks membership inserts and suspended-to-active transitions that would exceed max_members.';

drop trigger if exists organization_members_enforce_seat_quota
  on public.organization_members;
create trigger organization_members_enforce_seat_quota
  before insert or update of organization_id, status
  on public.organization_members
  for each row execute function app.enforce_member_seat_on_membership();

create or replace function app.enforce_member_seat_on_invitation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old_consumed boolean := false;
begin
  if tg_op = 'UPDATE' then
    v_old_consumed := old.status = 'pending'
      and old.expires_at > pg_catalog.now()
      and old.organization_id = new.organization_id;
  end if;

  if new.status = 'pending'
     and new.expires_at > pg_catalog.now()
     and not v_old_consumed then
    perform app.assert_plan_quota(new.organization_id, 'max_members');
  end if;

  return new;
end;
$$;

comment on function app.enforce_member_seat_on_invitation() is
  'Blocks new or renewed live invitation reservations that would exceed max_members.';

drop trigger if exists organization_invitations_enforce_seat_quota
  on public.organization_invitations;
create trigger organization_invitations_enforce_seat_quota
  before insert or update of organization_id, status, expires_at
  on public.organization_invitations
  for each row execute function app.enforce_member_seat_on_invitation();

-- Resolve the organization without locking the row, take the canonical quota
-- lock, and only then lock and revalidate the invitation. This keeps the lock
-- order consistent with concurrent invitation creation.
create or replace function public.renew_organization_invitation(
  p_invitation_id uuid
)
returns table (invitation_id uuid, invitation_token text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid;
  v_invitation public.organization_invitations%rowtype;
  v_token text;
begin
  select invitation.organization_id
  into v_organization_id
  from public.organization_invitations invitation
  where invitation.id = p_invitation_id;

  if not found then
    raise exception 'INVITATION_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform app.lock_plan_quota(v_organization_id, 'max_members');

  select *
  into v_invitation
  from public.organization_invitations invitation
  where invitation.id = p_invitation_id
  for update;

  if not found or v_invitation.status <> 'pending' then
    raise exception 'INVITATION_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform app.require_capability(v_invitation.organization_id, 'members.invite');

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  update public.organization_invitations invitation
  set token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex'),
      expires_at = pg_catalog.now() + interval '14 days'
  where invitation.id = p_invitation_id;

  perform app.write_audit(
    v_invitation.organization_id,
    'member.invitation_renewed',
    'organization_invitation',
    p_invitation_id,
    null,
    jsonb_build_object(
      'email', v_invitation.email,
      'role', v_invitation.role
    )
  );

  invitation_id := p_invitation_id;
  invitation_token := v_token;
  return next;
end;
$$;

-- Accepting an invitation exchanges one live reservation for one active
-- membership. Hold max_members from validation through both writes so another
-- invitation or reactivation cannot take the reserved seat between them.
create or replace function public.accept_organization_invitation(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid;
  v_inv public.organization_invitations%rowtype;
  v_email extensions.citext;
begin
  if auth.uid() is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;

  select profile.email
  into v_email
  from public.profiles profile
  where profile.id = auth.uid();

  select invitation.organization_id
  into v_organization_id
  from public.organization_invitations invitation
  where invitation.token_hash = encode(
    extensions.digest(p_token, 'sha256'),
    'hex'
  );

  if not found then
    raise exception 'INVALID_INVITATION: invitation is invalid or expired'
      using errcode = '42501';
  end if;

  perform app.lock_plan_quota(v_organization_id, 'max_members');

  select *
  into v_inv
  from public.organization_invitations invitation
  where invitation.token_hash = encode(
    extensions.digest(p_token, 'sha256'),
    'hex'
  )
  for update;

  if not found
     or v_inv.status <> 'pending'
     or v_inv.expires_at <= pg_catalog.now()
     or v_inv.email <> v_email then
    raise exception 'INVALID_INVITATION: invitation is invalid or expired'
      using errcode = '42501';
  end if;

  update public.organization_invitations invitation
  set status = 'accepted',
      accepted_by = auth.uid(),
      accepted_at = pg_catalog.now()
  where invitation.id = v_inv.id;

  if not exists (
    select 1
    from public.organization_members member
    where member.organization_id = v_inv.organization_id
      and member.user_id = auth.uid()
  ) then
    insert into public.organization_members (
      organization_id,
      user_id,
      role,
      role_id,
      invited_by
    ) values (
      v_inv.organization_id,
      auth.uid(),
      v_inv.role,
      v_inv.role_id,
      v_inv.invited_by
    );
  end if;

  perform app.write_audit(
    v_inv.organization_id,
    'member.invitation_accepted',
    'organization_invitation',
    v_inv.id,
    null,
    jsonb_build_object(
      'user_id', auth.uid(),
      'role', v_inv.role,
      'role_id', v_inv.role_id
    )
  );

  return v_inv.organization_id;
end;
$$;

comment on function public.accept_organization_invitation(text) is
  'Atomically converts a live invitation reservation into membership while holding the organization member-seat lock.';

comment on function public.renew_organization_invitation(uuid) is
  'Renews a pending invitation while holding the organization member-seat lock; an expired invitation must reacquire capacity.';

revoke all on function app.enforce_member_seat_on_membership()
  from public, anon, authenticated;
revoke all on function app.enforce_member_seat_on_invitation()
  from public, anon, authenticated;

revoke all on function public.accept_organization_invitation(text)
  from public, anon;
grant execute on function public.accept_organization_invitation(text)
  to authenticated, service_role;

revoke all on function public.renew_organization_invitation(uuid)
  from public, anon;
grant execute on function public.renew_organization_invitation(uuid)
  to authenticated, service_role;
