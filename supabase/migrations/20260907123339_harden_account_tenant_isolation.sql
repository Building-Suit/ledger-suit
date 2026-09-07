-- Reassert the account tenant boundary in a forward migration. This repairs
-- environments where the original policy migration was not applied cleanly
-- and makes the membership requirement explicit alongside capabilities.

alter table public.accounts enable row level security;
alter table public.accounts force row level security;

revoke all on public.accounts from anon;
revoke delete on public.accounts from authenticated;
grant select, insert, update on public.accounts to authenticated;

drop policy if exists "accounts are visible with accounts.read" on public.accounts;
drop policy if exists "accounts are created with accounts.create" on public.accounts;
drop policy if exists "accounts are edited with accounts.update" on public.accounts;

create policy "accounts are visible with accounts.read"
  on public.accounts for select to authenticated
  using (
    app.is_org_member(organization_id)
    and app.has_capability(organization_id, 'accounts.read')
  );

create policy "accounts are created with accounts.create"
  on public.accounts for insert to authenticated
  with check (
    app.is_org_member(organization_id)
    and app.has_capability(organization_id, 'accounts.create')
  );

create policy "accounts are edited with accounts.update"
  on public.accounts for update to authenticated
  using (
    app.is_org_member(organization_id)
    and app.has_capability(organization_id, 'accounts.update')
  )
  with check (
    app.is_org_member(organization_id)
    and app.has_capability(organization_id, 'accounts.update')
  );

-- The Accounts page reads this view. A privileged view owner must not bypass
-- the underlying account and entry RLS policies.
alter view public.account_balances set (security_invoker = true);
