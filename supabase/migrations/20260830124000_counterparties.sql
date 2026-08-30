-- Ledger Suit — 09. Counterparties
--
-- Lightweight customers/vendors/lenders. Managed inline from the transaction
-- form and in settings; deliberately not a primary navigation page.

create table if not exists public.counterparties (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name            text not null,
  type            public.counterparty_type not null default 'other',
  phone           text,
  email           extensions.citext,
  tax_identifier  text,
  notes           text,
  is_archived     boolean not null default false,
  archived_at     timestamptz,
  created_by      uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint counterparties_name_length check (char_length(name) between 1 and 160),
  constraint counterparties_email_format check (
    email is null or email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  ),
  constraint counterparties_archived_consistency check (
    (is_archived = false and archived_at is null)
    or (is_archived = true and archived_at is not null)
  ),
  constraint counterparties_id_org_unique unique (id, organization_id)
);

comment on table public.counterparties is
  'Customers, vendors, lenders, employees and other external parties, scoped to '
  'one organization.';

create unique index if not exists counterparties_org_name_key
  on public.counterparties (organization_id, lower(name));
create index if not exists counterparties_org_type_idx
  on public.counterparties (organization_id, type) where is_archived = false;

create trigger counterparties_set_updated_at
  before update on public.counterparties
  for each row execute function app.set_updated_at();

alter table public.counterparties enable row level security;
