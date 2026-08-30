-- Ledger Suit — 16. Tags and saved views

create table if not exists public.tags (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name            text not null,
  color           text,
  created_by      uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint tags_name_length check (char_length(name) between 1 and 60),
  constraint tags_color_format check (color is null or color ~ '^#[0-9A-Fa-f]{6}$'),
  constraint tags_id_org_unique unique (id, organization_id)
);

comment on table public.tags is 'Free-form analytical labels, scoped to one organization.';

create unique index if not exists tags_org_name_key on public.tags (organization_id, lower(name));

create trigger tags_set_updated_at
  before update on public.tags
  for each row execute function app.set_updated_at();

alter table public.tags enable row level security;

-- ---------------------------------------------------------------------------
create table if not exists public.transaction_tags (
  organization_id uuid not null,
  transaction_id  uuid not null,
  tag_id          uuid not null,
  created_by      uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),

  primary key (transaction_id, tag_id),

  constraint transaction_tags_transaction_same_org
    foreign key (transaction_id, organization_id)
    references public.transactions (id, organization_id) on delete cascade,
  constraint transaction_tags_tag_same_org
    foreign key (tag_id, organization_id)
    references public.tags (id, organization_id) on delete cascade
);

comment on table public.transaction_tags is
  'Tag assignments. Both sides are tenant-checked, so a transaction can never '
  'be tagged with another organization''s tag.';

create index if not exists transaction_tags_tag_idx
  on public.transaction_tags (organization_id, tag_id);
create index if not exists transaction_tags_transaction_idx
  on public.transaction_tags (transaction_id);

alter table public.transaction_tags enable row level security;

-- ---------------------------------------------------------------------------
-- Saved views (filters on the Transactions page)
-- ---------------------------------------------------------------------------
create type public.saved_view_visibility as enum ('private', 'organization');

create table if not exists public.saved_views (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name            text not null,
  resource        text not null default 'transactions',
  filters         jsonb not null default '{}'::jsonb,
  sort            jsonb not null default '[]'::jsonb,
  visibility      public.saved_view_visibility not null default 'private',
  created_by      uuid not null references public.profiles (id) on delete cascade,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint saved_views_name_length check (char_length(name) between 1 and 120)
);

create unique index if not exists saved_views_owner_name_key
  on public.saved_views (organization_id, created_by, lower(name));
create index if not exists saved_views_org_visibility_idx
  on public.saved_views (organization_id, visibility);

create trigger saved_views_set_updated_at
  before update on public.saved_views
  for each row execute function app.set_updated_at();

alter table public.saved_views enable row level security;
