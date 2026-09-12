-- Immutable workspace-calendar usage months for posted business transactions.

create table app.transaction_usage_buckets (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  bucket_start timestamptz not null,
  bucket_end timestamptz not null,
  timezone text not null,
  used_value bigint not null default 0 check (used_value >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, bucket_start),
  check (bucket_end > bucket_start)
);

create unique index transaction_usage_buckets_end_key
  on app.transaction_usage_buckets (organization_id, bucket_end);

create or replace function app.transaction_usage_month_bounds(
  p_organization_id uuid,
  p_posted_at timestamptz
)
returns table (bucket_start timestamptz, bucket_end timestamptz, timezone text)
language sql
stable
security definer
set search_path = ''
as $$
  select
    date_trunc('month', p_posted_at at time zone organization.timezone)
      at time zone organization.timezone,
    (date_trunc('month', p_posted_at at time zone organization.timezone) + interval '1 month')
      at time zone organization.timezone,
    organization.timezone
  from public.organizations organization
  where organization.id = p_organization_id;
$$;

-- Existing posted, reversed, and voided-after-posting rows already consumed
-- their customer-visible business transaction. Seed their immutable months.
insert into app.transaction_usage_buckets (
  organization_id, bucket_start, bucket_end, timezone, used_value
)
select
  transaction.organization_id,
  bounds.bucket_start,
  bounds.bucket_end,
  bounds.timezone,
  count(*)
from public.transactions transaction
cross join lateral app.transaction_usage_month_bounds(
  transaction.organization_id,
  transaction.posted_at
) bounds
where transaction.posted_at is not null
group by transaction.organization_id, bounds.bucket_start, bounds.bucket_end, bounds.timezone;

create or replace function app.consume_monthly_transaction_quota(
  p_organization_id uuid,
  p_posted_at timestamptz
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_entitlement record;
  v_bucket app.transaction_usage_buckets%rowtype;
  v_bounds record;
  v_previous_end timestamptz;
  v_previous_usage bigint;
  v_next_start timestamptz;
  v_initial_usage bigint := 0;
begin
  if p_organization_id is null or p_posted_at is null then
    raise exception 'TRANSACTION_USAGE_ARGUMENT_INVALID' using errcode = '22023';
  end if;

  perform app.lock_plan_quota(p_organization_id, 'max_monthly_transactions');
  select * into strict v_entitlement
  from app.resolve_plan_entitlement(p_organization_id, 'max_monthly_transactions');

  select * into v_bucket
  from app.transaction_usage_buckets bucket
  where bucket.organization_id = p_organization_id
    and p_posted_at >= bucket.bucket_start
    and p_posted_at < bucket.bucket_end
  order by bucket.bucket_start desc
  limit 1
  for update;

  if not found then
    select * into strict v_bounds
    from app.transaction_usage_month_bounds(p_organization_id, p_posted_at);

    -- A later workspace-timezone change must not create overlapping months or
    -- reset quota early. Existing boundaries win at either side of the new one.
    select bucket.bucket_end, bucket.used_value
    into v_previous_end, v_previous_usage
    from app.transaction_usage_buckets bucket
    where bucket.organization_id = p_organization_id
      and bucket.bucket_end <= p_posted_at
    order by bucket.bucket_end desc
    limit 1;
    select min(bucket.bucket_start) into v_next_start
    from app.transaction_usage_buckets bucket
    where bucket.organization_id = p_organization_id
      and bucket.bucket_start > p_posted_at;
    if v_previous_end is not null and v_bounds.bucket_start < v_previous_end then
      -- This is a shortened bridge caused by a timezone change, not a genuine
      -- calendar-month reset. Preserve the preceding month's consumption.
      v_bounds.bucket_start := v_previous_end;
      v_initial_usage := v_previous_usage;
    end if;
    v_bounds.bucket_end := least(v_bounds.bucket_end, v_next_start);

    insert into app.transaction_usage_buckets (
      organization_id, bucket_start, bucket_end, timezone, used_value
    ) values (
      p_organization_id, v_bounds.bucket_start, v_bounds.bucket_end,
      v_bounds.timezone, v_initial_usage
    )
    on conflict (organization_id, bucket_start) do nothing;

    select * into strict v_bucket
    from app.transaction_usage_buckets bucket
    where bucket.organization_id = p_organization_id
      and bucket.bucket_start = v_bounds.bucket_start
    for update;
  end if;

  if not v_entitlement.is_enabled
     or (v_entitlement.limit_value is not null
         and v_bucket.used_value + 1 > v_entitlement.limit_value) then
    raise exception 'PLAN_TRANSACTION_LIMIT_REACHED: usage %, requested 1, limit %',
      v_bucket.used_value,
      coalesce(v_entitlement.limit_value::text, 'unlimited')
      using errcode = 'P0001';
  end if;

  update app.transaction_usage_buckets
  set used_value = used_value + 1, updated_at = now()
  where organization_id = v_bucket.organization_id
    and bucket_start = v_bucket.bucket_start;
end;
$$;

create or replace function app.enforce_monthly_transaction_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'posted'
     and (tg_op = 'INSERT' or old.status <> 'posted') then
    perform app.consume_monthly_transaction_quota(new.organization_id, new.posted_at);
  end if;
  return new;
end;
$$;

create trigger transactions_enforce_monthly_quota
  before insert or update of status on public.transactions
  for each row execute function app.enforce_monthly_transaction_quota();

create or replace function app.guard_transaction_usage_bucket()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'TRANSACTION_USAGE_BUCKET_IMMUTABLE:' using errcode = '42501';
  end if;
  if new.organization_id is distinct from old.organization_id
     or new.bucket_start is distinct from old.bucket_start
     or new.bucket_end is distinct from old.bucket_end
     or new.timezone is distinct from old.timezone
     or new.used_value < old.used_value then
    raise exception 'TRANSACTION_USAGE_BUCKET_IMMUTABLE:' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger transaction_usage_buckets_guard
  before update or delete on app.transaction_usage_buckets
  for each row execute function app.guard_transaction_usage_bucket();

create or replace function app.plan_quota_usage(
  p_organization_id uuid,
  p_quota_key text
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_usage bigint;
begin
  case p_quota_key
    when 'max_members' then
      select
        (select count(*) from public.organization_members member
         where member.organization_id = p_organization_id and member.status = 'active')
        +
        (select count(*) from public.organization_invitations invitation
         where invitation.organization_id = p_organization_id
           and invitation.status = 'pending' and invitation.expires_at > now())
      into v_usage;
    when 'max_monthly_transactions' then
      select coalesce(max(bucket.used_value), 0) into v_usage
      from app.transaction_usage_buckets bucket
      where bucket.organization_id = p_organization_id
        and now() >= bucket.bucket_start and now() < bucket.bucket_end;
    when 'max_storage_bytes' then
      select
        coalesce((select sum(a.size_bytes) from public.attachments a
                  where a.organization_id = p_organization_id), 0)
        +
        coalesce((select sum(r.size_bytes) from app.attachment_storage_reservations r
                  where r.organization_id = p_organization_id
                    and r.status = 'reserved' and r.expires_at > now()), 0)
      into v_usage;
    when 'max_accounts' then
      select count(*) into v_usage from public.accounts a where a.organization_id = p_organization_id;
    when 'max_counterparties' then
      select count(*) into v_usage from public.counterparties c where c.organization_id = p_organization_id;
    when 'max_recurring_rules' then
      select count(*) into v_usage from public.recurring_rules r
      where r.organization_id = p_organization_id and r.status in ('active', 'paused', 'failed');
    when 'max_custom_roles' then
      select count(*) into v_usage from public.organization_roles r where r.organization_id = p_organization_id;
    else
      raise exception 'PLAN_QUOTA_NOT_SUPPORTED: %', p_quota_key using errcode = '22023';
  end case;
  return coalesce(v_usage, 0);
end;
$$;

comment on table app.transaction_usage_buckets is
  'Immutable workspace-timezone calendar months. used_value counts each business transaction when it first becomes posted.';
comment on function app.consume_monthly_transaction_quota(uuid, timestamptz) is
  'Serializes monthly quota consumption and increments the immutable bucket in the same transaction as posting.';

revoke all on table app.transaction_usage_buckets from public, anon, authenticated;
revoke all on function app.transaction_usage_month_bounds(uuid, timestamptz) from public, anon, authenticated;
revoke all on function app.consume_monthly_transaction_quota(uuid, timestamptz) from public, anon, authenticated;
revoke all on function app.enforce_monthly_transaction_quota() from public, anon, authenticated;
revoke all on function app.guard_transaction_usage_bucket() from public, anon, authenticated;
