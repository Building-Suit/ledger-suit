-- Ledger Suit — 08. Categories
--
-- Categories are the friendly, user-facing labels ("Office Rent"). They are not
-- ledger accounts. Each category points at the ledger account its postings land
-- in, which is what lets a non-accountant pick "Rent" and still get a correct
-- Dr Rent Expense / Cr Bank journal.

create table if not exists public.categories (
  id                 uuid primary key default gen_random_uuid(),
  organization_id    uuid not null references public.organizations (id) on delete cascade,
  parent_id          uuid,
  name               text not null,
  kind               public.category_kind not null,
  default_account_id uuid,
  icon               text,
  color              text,
  sort_order         integer not null default 0,
  is_system          boolean not null default false,
  is_active          boolean not null default true,
  created_by         uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  constraint categories_name_length check (char_length(name) between 1 and 120),
  constraint categories_color_format check (color is null or color ~ '^#[0-9A-Fa-f]{6}$'),
  constraint categories_no_self_parent check (parent_id is distinct from id),
  constraint categories_id_org_unique unique (id, organization_id),
  constraint categories_parent_same_org foreign key (parent_id, organization_id)
    references public.categories (id, organization_id) on delete set null,
  constraint categories_account_same_org foreign key (default_account_id, organization_id)
    references public.accounts (id, organization_id) on delete restrict
);

comment on table public.categories is
  'User-facing classification. Maps to a default ledger account so the UI never '
  'has to ask for debit/credit.';
comment on column public.categories.default_account_id is
  'Ledger account used when a transaction carries this category. Tenant-checked '
  'through the composite foreign key.';

create unique index if not exists categories_org_name_key
  on public.categories (organization_id, lower(name));
create index if not exists categories_org_kind_idx
  on public.categories (organization_id, kind) where is_active;
create index if not exists categories_parent_idx
  on public.categories (parent_id) where parent_id is not null;

create trigger categories_set_updated_at
  before update on public.categories
  for each row execute function app.set_updated_at();

alter table public.categories enable row level security;
