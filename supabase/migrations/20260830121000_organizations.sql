-- Ledger Suit — 03. Organizations (tenants)
--
-- The organization is the tenant boundary. Every financial row in this database
-- carries organization_id and is reachable only through a membership.

create type public.organization_status as enum (
  'trial',
  'active',
  'past_due',
  'suspended',
  'cancelled',
  'archived'
);

create table if not exists public.organizations (
  id                  uuid primary key default gen_random_uuid(),
  name                text        not null,
  slug                extensions.citext not null,
  legal_name          text,
  country_code        char(2)     not null default 'EG',
  timezone            text        not null default 'UTC',
  base_currency       char(3)     not null references public.currencies (code),
  fiscal_year_start_month smallint not null default 1
                            check (fiscal_year_start_month between 1 and 12),
  tax_identifier      text,
  logo_url            text,
  status              public.organization_status not null default 'trial',
  created_by          uuid        not null references public.profiles (id),
  archived_at         timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint organizations_name_length check (char_length(name) between 1 and 160),
  constraint organizations_slug_format check (slug ~ '^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$'),
  constraint organizations_country_format check (country_code ~ '^[A-Z]{2}$')
);

comment on table public.organizations is
  'Tenant root. Financial data is never destroyed when status changes.';
comment on column public.organizations.base_currency is
  'Reporting currency. Every ledger entry stores a base-currency equivalent.';

create unique index if not exists organizations_slug_key on public.organizations (slug);
create index if not exists organizations_created_by_idx on public.organizations (created_by);
create index if not exists organizations_status_idx on public.organizations (status);

-- Tenant-safe composite target: child tables reference (id, organization_id)
-- pairs so a row can never point at a parent owned by a different tenant.
create unique index if not exists organizations_id_self_key
  on public.organizations (id, id);

create trigger organizations_set_updated_at
  before update on public.organizations
  for each row execute function app.set_updated_at();

alter table public.organizations enable row level security;

-- ---------------------------------------------------------------------------
-- Per-organization settings
-- ---------------------------------------------------------------------------
create table if not exists public.organization_settings (
  organization_id        uuid primary key
                           references public.organizations (id) on delete cascade,
  -- Postings dated on or before this date are refused for users without the
  -- books.override_lock capability. NULL means the books are fully open.
  books_locked_until     date,
  advanced_accounting_mode boolean   not null default false,
  require_adjustment_approval boolean not null default false,
  duplicate_detection_enabled boolean not null default true,
  default_transaction_currency char(3) references public.currencies (code),
  week_starts_on         smallint    not null default 1
                           check (week_starts_on between 0 and 6),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

comment on table public.organization_settings is
  'One row per organization. Created automatically with the organization.';
comment on column public.organization_settings.books_locked_until is
  'Inclusive lock date. Postings on or before it require books.override_lock.';

create trigger organization_settings_set_updated_at
  before update on public.organization_settings
  for each row execute function app.set_updated_at();

alter table public.organization_settings enable row level security;

-- ---------------------------------------------------------------------------
-- Preferred organization on the profile
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists default_organization_id uuid
    references public.organizations (id) on delete set null;

comment on column public.profiles.default_organization_id is
  'Last used organization, restored by the organization switcher on login.';
