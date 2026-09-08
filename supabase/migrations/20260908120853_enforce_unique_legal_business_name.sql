-- Legal business names identify the registered entity and must be globally
-- unique. Normalize surrounding whitespace on every organization creation and
-- compare names case-insensitively so cosmetic differences cannot bypass the
-- rule. NULL remains allowed for the lower-level organization creation API.

create unique index organizations_legal_name_key
  on public.organizations (lower(btrim(legal_name)))
  where legal_name is not null;

create or replace function public.create_organization(
  p_name           text,
  p_base_currency  char(3) default 'EGP',
  p_country_code   char(2) default 'EG',
  p_timezone       text    default 'Africa/Cairo',
  p_legal_name     text    default null,
  p_fiscal_year_start_month smallint default 1
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_slug   text;
  v_base   text;
  v_suffix int := 0;
  v_user   uuid := auth.uid();
  v_constraint_name text;
begin
  if v_user is null then
    raise exception 'TENANT_ACCESS_DENIED: authentication required'
      using errcode = '42501';
  end if;

  if p_name is null or char_length(trim(p_name)) = 0 then
    raise exception 'INVALID_INPUT: organization name is required'
      using errcode = '22023';
  end if;

  if not exists (select 1 from public.currencies c
                 where c.code = p_base_currency and c.is_active) then
    raise exception 'INVALID_CURRENCY: % is not a supported currency', p_base_currency
      using errcode = '22023';
  end if;

  v_base := app.slugify(p_name);
  if char_length(v_base) < 3 then
    v_base := v_base || '-org';
  end if;
  v_base := left(v_base, 58);
  v_slug := v_base;

  while exists (select 1 from public.organizations o where o.slug = v_slug) loop
    v_suffix := v_suffix + 1;
    v_slug := v_base || '-' || v_suffix::text;
  end loop;

  begin
    insert into public.organizations (
      name, slug, legal_name, country_code, timezone, base_currency,
      fiscal_year_start_month, created_by
    )
    values (
      trim(p_name), v_slug, nullif(btrim(p_legal_name), ''),
      upper(p_country_code), p_timezone, p_base_currency,
      p_fiscal_year_start_month, v_user
    )
    returning id into v_org_id;
  exception when unique_violation then
    get stacked diagnostics v_constraint_name = CONSTRAINT_NAME;
    if v_constraint_name = 'organizations_legal_name_key' then
      raise exception 'LEGAL_NAME_ALREADY_EXISTS: legal business name must be unique'
        using errcode = '23505';
    end if;
    raise;
  end;

  insert into public.organization_settings (organization_id, default_transaction_currency)
  values (v_org_id, p_base_currency);

  insert into public.organization_members (organization_id, user_id, role, status)
  values (v_org_id, v_user, 'owner', 'active');

  update public.profiles p
  set default_organization_id = v_org_id
  where p.id = v_user and p.default_organization_id is null;

  perform app.write_audit(
    v_org_id, 'organization.created', 'organization', v_org_id,
    null, jsonb_build_object('name', trim(p_name), 'base_currency', p_base_currency)
  );

  return v_org_id;
end;
$$;

comment on index public.organizations_legal_name_key is
  'Globally prevents duplicate legal business names, ignoring case and surrounding whitespace.';
