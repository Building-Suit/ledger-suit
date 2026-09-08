-- Onboarding pre-checks
--
-- Lightweight boolean-only availability helpers used by the signup stepper
-- before the user commits to account creation. They never leak user data;
-- only report whether a value is already taken.

-- ---------------------------------------------------------------------------
-- Step 1 → 2: email + phone availability
-- ---------------------------------------------------------------------------
create or replace function public.check_owner_availability(
  p_email text,
  p_phone text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email_taken boolean := false;
  v_phone_taken boolean := false;
begin
  if p_email is not null and char_length(trim(p_email)) > 0 then
    select exists(
      select 1 from auth.users u where lower(u.email) = lower(trim(p_email))
    ) into v_email_taken;
  end if;

  if p_phone is not null and char_length(trim(p_phone)) > 0 then
    select exists(
      select 1 from public.profiles p where p.phone = trim(p_phone)
    ) into v_phone_taken;
  end if;

  return jsonb_build_object('email_taken', v_email_taken, 'phone_taken', v_phone_taken);
end;
$$;

comment on function public.check_owner_availability(text, text) is
  'Returns which of email / phone are already registered. Boolean only — never leaks user data.';

revoke all on function public.check_owner_availability(text, text) from public;
grant execute on function public.check_owner_availability(text, text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Step 2 → 3: legal business name availability
-- ---------------------------------------------------------------------------
create or replace function public.check_legal_name_availability(
  p_legal_name text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_legal_name is null or char_length(btrim(p_legal_name)) = 0 then
    return true;
  end if;

  return not exists(
    select 1 from public.organizations o
    where lower(btrim(o.legal_name)) = lower(btrim(p_legal_name))
  );
end;
$$;

comment on function public.check_legal_name_availability(text) is
  'Returns true when the legal business name is not yet registered. Case-insensitive, whitespace-trimmed.';

revoke all on function public.check_legal_name_availability(text) from public;
grant execute on function public.check_legal_name_availability(text) to anon, authenticated, service_role;
