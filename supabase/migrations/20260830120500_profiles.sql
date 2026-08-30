-- Ledger Suit — 02. Profiles
--
-- One row per authenticated user, mirroring auth.users with the product-facing
-- attributes we are allowed to read from the client. auth.users itself is never
-- exposed to the API.

create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  email        extensions.citext not null,
  full_name    text,
  avatar_url   text,
  locale       text        not null default 'en',
  timezone     text        not null default 'UTC',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint profiles_full_name_length check (
    full_name is null or char_length(full_name) between 1 and 160
  )
);

comment on table public.profiles is
  'Public profile mirror of auth.users. Readable by the owner and by fellow '
  'members of any organization the owner belongs to.';

create unique index if not exists profiles_email_key on public.profiles (email);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function app.set_updated_at();

alter table public.profiles enable row level security;

-- ---------------------------------------------------------------------------
-- Auto-provision a profile whenever an auth user is created
-- ---------------------------------------------------------------------------
create or replace function app.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name, avatar_url)
  values (
    new.id,
    coalesce(new.email, new.id::text || '@placeholder.invalid'),
    nullif(trim(coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      ''
    )), ''),
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'avatar_url', '')), '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function app.handle_new_auth_user() is
  'AFTER INSERT ON auth.users: provisions the matching public.profiles row.';

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_auth_user();

-- Keep the mirrored email in step with auth.users.
create or replace function app.handle_auth_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is distinct from old.email and new.email is not null then
    update public.profiles set email = new.email where id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function app.handle_auth_user_email_change();
