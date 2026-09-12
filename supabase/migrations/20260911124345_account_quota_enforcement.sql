-- Account capacity counts every chart-of-accounts row, including archived
-- accounts. Enforce at the table boundary so RPC, REST, and privileged paths
-- share the same organization-scoped lock and authoritative recount.

create or replace function app.enforce_account_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.assert_plan_quota(new.organization_id, 'max_accounts');
  return new;
end;
$$;

comment on function app.enforce_account_quota() is
  'Blocks account inserts that would exceed max_accounts; archived accounts continue to count.';

drop trigger if exists accounts_enforce_plan_quota on public.accounts;
create trigger accounts_enforce_plan_quota
  before insert on public.accounts
  for each row execute function app.enforce_account_quota();

revoke all on function app.enforce_account_quota()
  from public, anon, authenticated;
