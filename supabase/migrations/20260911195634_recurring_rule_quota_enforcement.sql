-- Active, paused, and failed recurring rules consume plan capacity. Completed
-- rules remain available as history and regain capacity only when reactivated.

create or replace function app.enforce_recurring_rule_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status in ('active', 'paused', 'failed') then
      perform app.assert_plan_quota(new.organization_id, 'max_recurring_rules');
    end if;
  elsif old.status = 'completed'
        and new.status in ('active', 'paused', 'failed') then
    perform app.assert_plan_quota(new.organization_id, 'max_recurring_rules');
  end if;

  return new;
end;
$$;

comment on function app.enforce_recurring_rule_quota() is
  'Enforces max_recurring_rules on counted inserts and completed-to-live reactivation under the organization quota lock.';

drop trigger if exists recurring_rules_enforce_plan_quota
  on public.recurring_rules;
create trigger recurring_rules_enforce_plan_quota
  before insert or update of status on public.recurring_rules
  for each row execute function app.enforce_recurring_rule_quota();

revoke all on function app.enforce_recurring_rule_quota()
  from public, anon, authenticated;
