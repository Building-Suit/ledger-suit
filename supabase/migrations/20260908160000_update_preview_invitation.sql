-- Add the minimum account-state signal required by the invitation screen.
-- The acceptance RPC remains the authorization boundary.

drop function if exists public.preview_organization_invitation(text);

create or replace function public.preview_organization_invitation(p_token text)
returns table (
  email text,
  organization_name text,
  role public.organization_role,
  inviter_name text,
  inviter_job_title text,
  expires_at timestamptz,
  user_exists boolean
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
    i.expires_at,
    exists(select 1 from public.profiles u where u.email = i.email::extensions.citext)
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

revoke all on function public.preview_organization_invitation(text) from public;
grant execute on function public.preview_organization_invitation(text) to anon, authenticated, service_role;
