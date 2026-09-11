-- Counterparty creation is a controlled, audited operation. Archived rows keep
-- consuming capacity, as defined by app.plan_quota_usage.

create or replace function app.enforce_counterparty_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.assert_plan_quota(new.organization_id, 'max_counterparties');
  return new;
end;
$$;

comment on function app.enforce_counterparty_quota() is
  'Blocks counterparty inserts that would exceed max_counterparties; archived rows continue to count.';

drop trigger if exists counterparties_enforce_plan_quota on public.counterparties;
create trigger counterparties_enforce_plan_quota
  before insert on public.counterparties
  for each row execute function app.enforce_counterparty_quota();

revoke all on function app.enforce_counterparty_quota()
  from public, anon, authenticated;

create or replace function public.create_counterparty(
  p_organization_id uuid,
  p_name text,
  p_type public.counterparty_type default 'other',
  p_phone text default null,
  p_email text default null,
  p_tax_identifier text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform app.require_capability(p_organization_id, 'counterparties.manage');

  if p_name is null or char_length(trim(p_name)) = 0 then
    raise exception 'INVALID_INPUT: counterparty name is required'
      using errcode = '22023';
  end if;

  insert into public.counterparties (
    organization_id, name, type, phone, email, tax_identifier, notes, created_by
  ) values (
    p_organization_id,
    trim(p_name),
    coalesce(p_type, 'other'),
    nullif(trim(p_phone), ''),
    nullif(trim(p_email), ''),
    nullif(trim(p_tax_identifier), ''),
    nullif(trim(p_notes), ''),
    auth.uid()
  )
  returning id into v_id;

  perform app.write_audit(
    p_organization_id,
    'counterparty.created',
    'counterparty',
    v_id,
    null,
    jsonb_build_object('name', trim(p_name), 'type', coalesce(p_type, 'other'))
  );

  return v_id;
end;
$$;

comment on function public.create_counterparty(
  uuid, text, public.counterparty_type, text, text, text, text
) is
  'Creates and audits a counterparty after tenant authorization and a serialized plan-quota check.';

revoke insert on public.counterparties from authenticated;
drop policy if exists "counterparties are created with counterparties.manage"
  on public.counterparties;

revoke all on function public.create_counterparty(
  uuid, text, public.counterparty_type, text, text, text, text
) from public, anon;
grant execute on function public.create_counterparty(
  uuid, text, public.counterparty_type, text, text, text, text
) to authenticated, service_role;
