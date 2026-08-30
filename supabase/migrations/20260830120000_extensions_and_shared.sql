-- Ledger Suit — 01. Extensions and shared primitives
--
-- Creates the private `app` schema used for internal helper functions that must
-- never be reachable through PostgREST, plus shared trigger helpers used by
-- every subsequent migration.
--
-- Safe to replay from an empty database. No tenant data is touched.

create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "citext" with schema extensions;

-- ---------------------------------------------------------------------------
-- Private helper schema
-- ---------------------------------------------------------------------------
-- `app` is deliberately NOT added to the PostgREST exposed schema list, so
-- nothing inside it is callable by anon/authenticated over the REST API.
create schema if not exists app;

revoke all on schema app from public;
grant usage on schema app to postgres, service_role;

comment on schema app is
  'Private helper schema. Not exposed through PostgREST. Holds authorization '
  'helpers, trigger functions and internal accounting primitives.';

-- ---------------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------------
create or replace function app.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function app.set_updated_at() is
  'BEFORE UPDATE trigger: stamps updated_at with the server clock so clients '
  'cannot forge it.';

-- ---------------------------------------------------------------------------
-- Immutability guard
-- ---------------------------------------------------------------------------
-- Generic guard used by append-only tables (audit log, ledger entries of
-- posted transactions, billing events).
create or replace function app.reject_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'IMMUTABLE_RECORD: % rows cannot be modified or deleted',
    tg_table_name
    using errcode = '42501';
end;
$$;

comment on function app.reject_mutation() is
  'BEFORE UPDATE/DELETE trigger that unconditionally raises. Used to make '
  'append-only tables append-only at the database level.';

-- ---------------------------------------------------------------------------
-- Currency reference data
-- ---------------------------------------------------------------------------
-- Money is stored as integer minor units everywhere in this schema. The number
-- of minor units per major unit is currency dependent (USD = 2, JPY = 0,
-- KWD = 3), so it must be looked up rather than assumed.
create table if not exists public.currencies (
  code          char(3) primary key,
  name          text        not null,
  symbol        text,
  minor_unit    smallint    not null default 2
                            check (minor_unit between 0 and 4),
  is_active     boolean     not null default true,
  created_at    timestamptz not null default now()
);

comment on table public.currencies is
  'Global (non-tenant) currency reference data. Read-only to clients.';
comment on column public.currencies.minor_unit is
  'Decimal exponent: number of minor units per major unit. USD=2, JPY=0, KWD=3.';

alter table public.currencies enable row level security;

insert into public.currencies (code, name, symbol, minor_unit) values
  ('EGP', 'Egyptian Pound',        E'ج.م', 2),
  ('USD', 'US Dollar',             '$',   2),
  ('EUR', 'Euro',                  E'€', 2),
  ('GBP', 'Pound Sterling',        E'£', 2),
  ('SAR', 'Saudi Riyal',           E'﷼', 2),
  ('AED', 'UAE Dirham',            E'د.إ', 2),
  ('KWD', 'Kuwaiti Dinar',         E'د.ك', 3),
  ('QAR', 'Qatari Riyal',          E'ر.ق', 2),
  ('BHD', 'Bahraini Dinar',        E'.د.ب', 3),
  ('OMR', 'Omani Rial',            E'ر.ع', 3),
  ('JOD', 'Jordanian Dinar',       E'د.ا', 3),
  ('TRY', 'Turkish Lira',          E'₺', 2),
  ('JPY', 'Japanese Yen',          E'¥', 0),
  ('CNY', 'Chinese Yuan',          E'¥', 2),
  ('CAD', 'Canadian Dollar',       'CA$', 2),
  ('AUD', 'Australian Dollar',     'A$',  2),
  ('CHF', 'Swiss Franc',           'CHF', 2),
  ('SEK', 'Swedish Krona',         'kr',  2),
  ('NOK', 'Norwegian Krone',       'kr',  2),
  ('ZAR', 'South African Rand',    'R',   2),
  ('NGN', 'Nigerian Naira',        E'₦', 2),
  ('KES', 'Kenyan Shilling',       'KSh', 2),
  ('MAD', 'Moroccan Dirham',       E'د.م.', 2),
  ('TND', 'Tunisian Dinar',        E'د.ت', 3),
  ('INR', 'Indian Rupee',          E'₹', 2),
  ('PKR', 'Pakistani Rupee',       E'₨', 2),
  ('SGD', 'Singapore Dollar',      'S$',  2)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- Money helpers
-- ---------------------------------------------------------------------------
create or replace function app.currency_minor_unit(p_code char(3))
returns smallint
language sql
stable
set search_path = ''
as $$
  select c.minor_unit from public.currencies c where c.code = p_code;
$$;

comment on function app.currency_minor_unit(char) is
  'Minor-unit exponent for a currency code, or NULL if the code is unknown.';

-- Converts an amount expressed in transaction-currency minor units into base
-- currency minor units. Rounds half-up at the final minor unit; the rounding
-- residual is never silently dropped because the caller (post_transaction)
-- forces the journal to balance in BOTH currencies before it commits.
create or replace function app.convert_minor(
  p_amount_minor    bigint,
  p_from_currency   char(3),
  p_to_currency     char(3),
  p_exchange_rate   numeric
)
returns bigint
language plpgsql
-- STABLE, not IMMUTABLE: it reads public.currencies for the minor-unit
-- exponent. Marking it immutable would let the planner cache a result across a
-- change to that table.
stable
set search_path = ''
as $$
declare
  v_from_unit smallint;
  v_to_unit   smallint;
begin
  if p_from_currency = p_to_currency then
    return p_amount_minor;
  end if;

  if p_exchange_rate is null or p_exchange_rate <= 0 then
    raise exception 'INVALID_EXCHANGE_RATE: rate must be a positive number'
      using errcode = '22023';
  end if;

  select minor_unit into v_from_unit from public.currencies where code = p_from_currency;
  select minor_unit into v_to_unit   from public.currencies where code = p_to_currency;

  if v_from_unit is null or v_to_unit is null then
    raise exception 'INVALID_CURRENCY: unknown currency code (% or %)',
      p_from_currency, p_to_currency
      using errcode = '22023';
  end if;

  -- major_amount = minor / 10^from_unit ; base_major = major * rate
  -- base_minor   = base_major * 10^to_unit
  return round(
    (p_amount_minor::numeric / power(10::numeric, v_from_unit))
      * p_exchange_rate
      * power(10::numeric, v_to_unit)
  )::bigint;
end;
$$;

comment on function app.convert_minor(bigint, char, char, numeric) is
  'Currency conversion in integer minor units. Never uses binary floating point.';
