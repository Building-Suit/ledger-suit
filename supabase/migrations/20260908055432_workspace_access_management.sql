-- Ledger Suit — workspace access management
--
-- Member mutations are intentionally RPC-only. This keeps role, suspension,
-- capability override, removal and invitation lifecycle rules in one audited
-- boundary instead of trusting browser-authored row updates.

revoke update, delete on public.organization_members from authenticated;
revoke update on public.organization_invitations from authenticated;

-- Active administrators must still be able to identify suspended members in
-- the access console. The caller's membership remains the authorization gate.
drop policy if exists "profiles are visible to self and fellow members" on public.profiles;
create policy "profiles are visible to self and fellow members"
  on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.organization_members mine
      join public.organization_members theirs
        on theirs.organization_id = mine.organization_id
      where mine.user_id = auth.uid()
        and mine.status = 'active'
        and theirs.user_id = public.profiles.id
    )
  );

create or replace function public.preview_organization_invitation(p_token text)
returns table (
  email text,
  organization_name text,
  role public.organization_role,
  inviter_name text,
  inviter_job_title text,
  expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_token is null or char_length(p_token) <> 64 then
    raise exception 'INVALID_INVITATION: invitation is invalid or expired'
      using errcode = '42501';
  end if;

  return query
  select
    i.email::text,
    o.name,
    i.role,
    coalesce(nullif(trim(p.full_name), ''), 'A Ledger Suit administrator'),
    nullif(trim(p.job_title), ''),
    i.expires_at
  from public.organization_invitations i
  join public.organizations o on o.id = i.organization_id
  left join public.profiles p on p.id = i.invited_by
  where i.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and i.status = 'pending'
    and i.expires_at > now();

  if not found then
    raise exception 'INVALID_INVITATION: invitation is invalid or expired'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function public.manage_organization_member(
  p_member_id uuid,
  p_role public.organization_role,
  p_status public.membership_status,
  p_granted_capabilities text[] default '{}',
  p_revoked_capabilities text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.organization_members%rowtype;
  v_actor_role public.organization_role;
  v_unknown text[];
begin
  select * into v_member
  from public.organization_members m
  where m.id = p_member_id
  for update;

  if not found then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform app.require_capability(v_member.organization_id, 'members.update');
  v_actor_role := app.member_role(v_member.organization_id);

  if v_member.user_id = auth.uid() and p_status = 'suspended' then
    raise exception 'INVALID_MEMBER_CHANGE: you cannot suspend yourself'
      using errcode = '22023';
  end if;
  if (v_member.role = 'owner' or p_role = 'owner') and v_actor_role <> 'owner' then
    raise exception 'INSUFFICIENT_PERMISSION: only an owner can manage owners'
      using errcode = '42501';
  end if;
  if p_granted_capabilities && p_revoked_capabilities then
    raise exception 'INVALID_MEMBER_CHANGE: a capability cannot be both granted and revoked'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(requested), '{}') into v_unknown
  from (
    select distinct unnest(p_granted_capabilities || p_revoked_capabilities) requested
  ) requested
  where not exists (
    select 1 from public.capabilities c where c.key = requested.requested
  );
  if cardinality(v_unknown) > 0 then
    raise exception 'INVALID_MEMBER_CHANGE: unknown capabilities'
      using errcode = '22023';
  end if;

  update public.organization_members m
  set role = p_role,
      status = p_status,
      granted_capabilities = coalesce(p_granted_capabilities, '{}'),
      revoked_capabilities = coalesce(p_revoked_capabilities, '{}')
  where m.id = p_member_id;

  perform app.write_audit(
    v_member.organization_id,
    'member.updated',
    'organization_member',
    p_member_id,
    jsonb_build_object(
      'role', v_member.role,
      'status', v_member.status,
      'granted_capabilities', v_member.granted_capabilities,
      'revoked_capabilities', v_member.revoked_capabilities
    ),
    jsonb_build_object(
      'role', p_role,
      'status', p_status,
      'granted_capabilities', p_granted_capabilities,
      'revoked_capabilities', p_revoked_capabilities
    )
  );
  return p_member_id;
end;
$$;

create or replace function public.remove_organization_member(p_member_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.organization_members%rowtype;
  v_actor_role public.organization_role;
begin
  select * into v_member
  from public.organization_members m
  where m.id = p_member_id
  for update;
  if not found then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_member.user_id <> auth.uid() then
    perform app.require_capability(v_member.organization_id, 'members.remove');
  end if;
  v_actor_role := app.member_role(v_member.organization_id);
  if v_member.role = 'owner' and v_member.user_id <> auth.uid() and v_actor_role <> 'owner' then
    raise exception 'INSUFFICIENT_PERMISSION: only an owner can remove owners'
      using errcode = '42501';
  end if;

  delete from public.organization_members where id = p_member_id;
  perform app.write_audit(
    v_member.organization_id,
    'member.removed',
    'organization_member',
    p_member_id,
    jsonb_build_object('user_id', v_member.user_id, 'role', v_member.role),
    null
  );
  return p_member_id;
end;
$$;

create or replace function public.revoke_organization_invitation(p_invitation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitation public.organization_invitations%rowtype;
begin
  select * into v_invitation
  from public.organization_invitations i
  where i.id = p_invitation_id
  for update;
  if not found then
    raise exception 'INVITATION_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform app.require_capability(v_invitation.organization_id, 'members.update');

  update public.organization_invitations
  set status = 'revoked'
  where id = p_invitation_id and status = 'pending';

  perform app.write_audit(
    v_invitation.organization_id,
    'member.invitation_revoked',
    'organization_invitation',
    p_invitation_id,
    jsonb_build_object('email', v_invitation.email, 'role', v_invitation.role),
    null
  );
  return p_invitation_id;
end;
$$;

create or replace function public.renew_organization_invitation(p_invitation_id uuid)
returns table (invitation_id uuid, invitation_token text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitation public.organization_invitations%rowtype;
  v_token text;
begin
  select * into v_invitation
  from public.organization_invitations i
  where i.id = p_invitation_id
  for update;
  if not found or v_invitation.status <> 'pending' then
    raise exception 'INVITATION_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform app.require_capability(v_invitation.organization_id, 'members.invite');

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  update public.organization_invitations
  set token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex'),
      expires_at = now() + interval '14 days'
  where id = p_invitation_id;

  perform app.write_audit(
    v_invitation.organization_id,
    'member.invitation_renewed',
    'organization_invitation',
    p_invitation_id,
    null,
    jsonb_build_object('email', v_invitation.email, 'role', v_invitation.role)
  );
  invitation_id := p_invitation_id;
  invitation_token := v_token;
  return next;
end;
$$;

revoke all on function public.preview_organization_invitation(text) from public;
grant execute on function public.preview_organization_invitation(text) to anon, authenticated, service_role;

revoke all on function public.manage_organization_member(uuid, public.organization_role, public.membership_status, text[], text[]) from public, anon;
grant execute on function public.manage_organization_member(uuid, public.organization_role, public.membership_status, text[], text[]) to authenticated, service_role;

revoke all on function public.remove_organization_member(uuid) from public, anon;
grant execute on function public.remove_organization_member(uuid) to authenticated, service_role;

revoke all on function public.revoke_organization_invitation(uuid) from public, anon;
grant execute on function public.revoke_organization_invitation(uuid) to authenticated, service_role;

revoke all on function public.renew_organization_invitation(uuid) from public, anon;
grant execute on function public.renew_organization_invitation(uuid) to authenticated, service_role;
