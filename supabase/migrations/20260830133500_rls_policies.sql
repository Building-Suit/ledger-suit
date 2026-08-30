-- Ledger Suit — 20. Row Level Security policies and table grants
--
-- Two independent layers protect every tenant table:
--
--   1. Grants  — a client role only holds the verbs it legitimately needs. The
--                ledger tables are SELECT-only for clients; all writes go
--                through the posting RPCs.
--   2. RLS     — every remaining verb is filtered by organization membership
--                and by the capability the action requires.
--
-- Knowing an organization UUID grants nothing on its own: every policy resolves
-- the caller from auth.uid() and checks membership.

-- ---------------------------------------------------------------------------
-- Start from zero, then grant deliberately.
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;

-- Reference data: readable by any signed-in user, writable by none.
grant select on public.currencies,
                public.capabilities,
                public.role_capabilities,
                public.subscription_plans,
                public.subscription_plan_prices,
                public.subscription_entitlements
  to authenticated;

grant select, update on public.profiles to authenticated;
grant select, update on public.organizations to authenticated;
grant select, update on public.organization_settings to authenticated;
grant select, update, delete on public.organization_members to authenticated;
grant select, insert, update on public.organization_invitations to authenticated;
grant select, insert, update on public.accounts to authenticated;
grant select, insert, update, delete on public.categories to authenticated;
grant select, insert, update on public.counterparties to authenticated;
grant select, insert, update, delete on public.tags to authenticated;
grant select, insert, delete on public.transaction_tags to authenticated;
grant select, insert, update, delete on public.saved_views to authenticated;
grant select, insert, delete on public.attachments to authenticated;
grant select, update on public.notifications to authenticated;
grant select on public.audit_logs to authenticated;
grant select on public.subscriptions, public.subscription_customers to authenticated;
grant select on public.billing_events to authenticated;

-- The ledger is read-only to clients. INSERT/UPDATE/DELETE exist only inside
-- the SECURITY DEFINER posting functions.
grant select on public.transactions, public.transaction_entries to authenticated;

-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------
create policy "currencies are readable by signed-in users"
  on public.currencies for select to authenticated using (true);

create policy "capabilities are readable by signed-in users"
  on public.capabilities for select to authenticated using (true);

create policy "role capabilities are readable by signed-in users"
  on public.role_capabilities for select to authenticated using (true);

create policy "plans are readable by signed-in users"
  on public.subscription_plans for select to authenticated using (is_active);

create policy "plan prices are readable by signed-in users"
  on public.subscription_plan_prices for select to authenticated using (is_active);

create policy "plan entitlements are readable by signed-in users"
  on public.subscription_entitlements for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
create policy "profiles are visible to self and fellow members"
  on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.organization_members mine
      join public.organization_members theirs
        on theirs.organization_id = mine.organization_id
      where mine.user_id = auth.uid()
        and mine.status = 'active'
        and theirs.user_id = public.profiles.id
        and theirs.status = 'active'
    )
  );

create policy "profiles are editable by their owner"
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- Organizations
-- ---------------------------------------------------------------------------
-- No INSERT policy: organizations are created only through
-- public.create_organization(), which also provisions the owner membership.
create policy "organizations are visible to their members"
  on public.organizations for select to authenticated
  using (app.is_org_member(id));

create policy "organizations are editable with organization.update"
  on public.organizations for update to authenticated
  using (app.has_capability(id, 'organization.update'))
  with check (app.has_capability(id, 'organization.update'));

create policy "organization settings are visible to members"
  on public.organization_settings for select to authenticated
  using (app.is_org_member(organization_id));

create policy "organization settings are editable with organization.update"
  on public.organization_settings for update to authenticated
  using (app.has_capability(organization_id, 'organization.update'))
  with check (app.has_capability(organization_id, 'organization.update'));

-- ---------------------------------------------------------------------------
-- Membership
-- ---------------------------------------------------------------------------
create policy "members are visible with members.read"
  on public.organization_members for select to authenticated
  using (
    user_id = auth.uid()
    or app.has_capability(organization_id, 'members.read')
  );

create policy "members are editable with members.update"
  on public.organization_members for update to authenticated
  using (app.has_capability(organization_id, 'members.update'))
  with check (app.has_capability(organization_id, 'members.update'));

create policy "members are removable with members.remove"
  on public.organization_members for delete to authenticated
  using (
    app.has_capability(organization_id, 'members.remove')
    -- A member can always remove themselves; app.guard_last_owner() still
    -- prevents the final owner from walking out.
    or user_id = auth.uid()
  );

create policy "invitations are visible with members.read"
  on public.organization_invitations for select to authenticated
  using (
    app.has_capability(organization_id, 'members.read')
    or email = (select p.email from public.profiles p where p.id = auth.uid())
  );

create policy "invitations are created with members.invite"
  on public.organization_invitations for insert to authenticated
  with check (app.has_capability(organization_id, 'members.invite'));

create policy "invitations are updated with members.update"
  on public.organization_invitations for update to authenticated
  using (app.has_capability(organization_id, 'members.update'))
  with check (app.has_capability(organization_id, 'members.update'));

-- ---------------------------------------------------------------------------
-- Chart of accounts
-- ---------------------------------------------------------------------------
create policy "accounts are visible with accounts.read"
  on public.accounts for select to authenticated
  using (app.has_capability(organization_id, 'accounts.read'));

create policy "accounts are created with accounts.create"
  on public.accounts for insert to authenticated
  with check (app.has_capability(organization_id, 'accounts.create'));

create policy "accounts are edited with accounts.update"
  on public.accounts for update to authenticated
  using (app.has_capability(organization_id, 'accounts.update'))
  with check (app.has_capability(organization_id, 'accounts.update'));

-- ---------------------------------------------------------------------------
-- Categories, counterparties, tags
-- ---------------------------------------------------------------------------
create policy "categories are visible with categories.read"
  on public.categories for select to authenticated
  using (app.has_capability(organization_id, 'categories.read'));

create policy "categories are managed with categories.manage"
  on public.categories for insert to authenticated
  with check (app.has_capability(organization_id, 'categories.manage'));

create policy "categories are updated with categories.manage"
  on public.categories for update to authenticated
  using (app.has_capability(organization_id, 'categories.manage'))
  with check (app.has_capability(organization_id, 'categories.manage'));

create policy "categories are deleted with categories.manage"
  on public.categories for delete to authenticated
  using (app.has_capability(organization_id, 'categories.manage') and is_system = false);

create policy "counterparties are visible with counterparties.read"
  on public.counterparties for select to authenticated
  using (app.has_capability(organization_id, 'counterparties.read'));

create policy "counterparties are created with counterparties.manage"
  on public.counterparties for insert to authenticated
  with check (app.has_capability(organization_id, 'counterparties.manage'));

create policy "counterparties are updated with counterparties.manage"
  on public.counterparties for update to authenticated
  using (app.has_capability(organization_id, 'counterparties.manage'))
  with check (app.has_capability(organization_id, 'counterparties.manage'));

create policy "tags are visible with tags.read"
  on public.tags for select to authenticated
  using (app.has_capability(organization_id, 'tags.read'));

create policy "tags are created with tags.manage"
  on public.tags for insert to authenticated
  with check (app.has_capability(organization_id, 'tags.manage'));

create policy "tags are updated with tags.manage"
  on public.tags for update to authenticated
  using (app.has_capability(organization_id, 'tags.manage'))
  with check (app.has_capability(organization_id, 'tags.manage'));

create policy "tags are deleted with tags.manage"
  on public.tags for delete to authenticated
  using (app.has_capability(organization_id, 'tags.manage'));

create policy "transaction tags are visible with transactions.read"
  on public.transaction_tags for select to authenticated
  using (app.has_capability(organization_id, 'transactions.read'));

create policy "transaction tags are assigned with transactions.create"
  on public.transaction_tags for insert to authenticated
  with check (app.has_capability(organization_id, 'transactions.create'));

create policy "transaction tags are removed with transactions.create"
  on public.transaction_tags for delete to authenticated
  using (app.has_capability(organization_id, 'transactions.create'));

-- ---------------------------------------------------------------------------
-- Ledger (read-only for clients)
-- ---------------------------------------------------------------------------
create policy "transactions are visible with transactions.read"
  on public.transactions for select to authenticated
  using (app.has_capability(organization_id, 'transactions.read'));

create policy "ledger entries are visible with transactions.read"
  on public.transaction_entries for select to authenticated
  using (app.has_capability(organization_id, 'transactions.read'));

-- ---------------------------------------------------------------------------
-- Saved views
-- ---------------------------------------------------------------------------
create policy "saved views are visible to their owner or the organization"
  on public.saved_views for select to authenticated
  using (
    app.is_org_member(organization_id)
    and (created_by = auth.uid() or visibility = 'organization')
  );

create policy "saved views are created by members"
  on public.saved_views for insert to authenticated
  with check (app.is_org_member(organization_id) and created_by = auth.uid());

create policy "saved views are edited by their owner"
  on public.saved_views for update to authenticated
  using (created_by = auth.uid() and app.is_org_member(organization_id))
  with check (created_by = auth.uid() and app.is_org_member(organization_id));

create policy "saved views are deleted by their owner"
  on public.saved_views for delete to authenticated
  using (created_by = auth.uid() and app.is_org_member(organization_id));

-- ---------------------------------------------------------------------------
-- Attachments
-- ---------------------------------------------------------------------------
create policy "attachments are visible with attachments.read"
  on public.attachments for select to authenticated
  using (app.has_capability(organization_id, 'attachments.read'));

create policy "attachments are created with attachments.create"
  on public.attachments for insert to authenticated
  with check (
    app.has_capability(organization_id, 'attachments.create')
    and uploaded_by = auth.uid()
  );

create policy "attachments are deleted with attachments.delete"
  on public.attachments for delete to authenticated
  using (app.has_capability(organization_id, 'attachments.delete'));

-- ---------------------------------------------------------------------------
-- Audit log — readable, never writable from a client
-- ---------------------------------------------------------------------------
create policy "audit log is visible with audit.read"
  on public.audit_logs for select to authenticated
  using (app.has_capability(organization_id, 'audit.read'));

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------
create policy "notifications are visible to their addressee"
  on public.notifications for select to authenticated
  using (
    app.is_org_member(organization_id)
    and (user_id is null or user_id = auth.uid())
  );

create policy "notifications are marked read by their addressee"
  on public.notifications for update to authenticated
  using (app.is_org_member(organization_id) and (user_id is null or user_id = auth.uid()))
  with check (app.is_org_member(organization_id) and (user_id is null or user_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- Billing
-- ---------------------------------------------------------------------------
create policy "subscriptions are visible with billing.read"
  on public.subscriptions for select to authenticated
  using (app.has_capability(organization_id, 'billing.read'));

create policy "billing customers are visible with billing.read"
  on public.subscription_customers for select to authenticated
  using (app.has_capability(organization_id, 'billing.read'));

create policy "billing events are visible with billing.read"
  on public.billing_events for select to authenticated
  using (
    organization_id is not null
    and app.has_capability(organization_id, 'billing.read')
  );

-- ---------------------------------------------------------------------------
-- RPC execution
-- ---------------------------------------------------------------------------
-- PostgreSQL grants EXECUTE to PUBLIC on new functions, so anon must be
-- stripped explicitly for anything that touches tenant data.
do $$
declare
  v_fn record;
begin
  for v_fn in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'create_organization', 'create_draft_transaction', 'post_transaction',
        'reverse_transaction', 'void_transaction', 'create_adjustment',
        'post_opening_balance', 'record_income', 'record_expense',
        'record_transfer', 'record_asset_purchase', 'record_liability_created',
        'record_liability_payment', 'record_owner_contribution',
        'record_owner_withdrawal', 'my_capabilities', 'can_use_feature',
        'get_limit'
      )
  loop
    execute format('revoke all on function %s from public, anon', v_fn.signature);
    execute format('grant execute on function %s to authenticated, service_role', v_fn.signature);
  end loop;
end;
$$;

-- app.* helpers are internal. They are reachable only because RLS policies are
-- evaluated as the calling role; PostgREST cannot see the schema at all.
revoke all on all functions in schema app from public, anon;

-- The reporting functions in the next migration run as the *caller* (so RLS
-- still filters their rows), which means `authenticated` needs execute on the
-- handful of helpers they lean on. Everything else in `app` stays closed.
grant execute on function
  app.is_org_member(uuid),
  app.has_capability(uuid, text),
  app.capabilities_for(uuid, uuid),
  app.member_role(uuid),
  app.require_capability(uuid, text),
  app.require_account(uuid, uuid, public.account_type[], text),
  app.org_base_currency(uuid),
  app.org_today(uuid),
  app.currency_minor_unit(char),
  app.convert_minor(bigint, char, char, numeric),
  app.normal_balance_for(public.account_type),
  app.try_uuid(text)
  to authenticated;
