-- Ledger Suit — 27. Phase 3 access control and reminders
--
-- Same two-layer model as the rest of the schema: grants decide which verbs a
-- client role holds at all, RLS decides which rows those verbs may touch.

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
revoke all on public.commitments,
              public.commitment_settlements,
              public.recurring_rules,
              public.recurring_occurrences
  from anon, authenticated;

-- Commitments are created through create_commitment() so the amount, dates and
-- tenant ownership are validated in one place; editing the descriptive fields
-- afterwards is an ordinary UPDATE.
grant select, update on public.commitments to authenticated;
grant select on public.commitment_settlements to authenticated;
grant select, update on public.recurring_rules to authenticated;
grant select on public.recurring_occurrences to authenticated;

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------
create policy "commitments are visible with commitments.read"
  on public.commitments for select to authenticated
  using (app.has_capability(organization_id, 'commitments.read'));

create policy "commitments are edited with commitments.update"
  on public.commitments for update to authenticated
  using (app.has_capability(organization_id, 'commitments.update'))
  with check (app.has_capability(organization_id, 'commitments.update'));

create policy "settlements are visible with commitments.read"
  on public.commitment_settlements for select to authenticated
  using (app.has_capability(organization_id, 'commitments.read'));

create policy "recurring rules are visible with recurring.read"
  on public.recurring_rules for select to authenticated
  using (app.has_capability(organization_id, 'recurring.read'));

create policy "recurring rules are edited with recurring.manage"
  on public.recurring_rules for update to authenticated
  using (app.has_capability(organization_id, 'recurring.manage'))
  with check (app.has_capability(organization_id, 'recurring.manage'));

create policy "recurring occurrences are visible with recurring.read"
  on public.recurring_occurrences for select to authenticated
  using (app.has_capability(organization_id, 'recurring.read'));

-- ---------------------------------------------------------------------------
-- Reminders
-- ---------------------------------------------------------------------------
-- Notifications are deduplicated on (type, entity, the date they are about)
-- rather than blindly inserted, so running the reminder sweep hourly does not
-- produce an hourly pile of identical rows.
create unique index if not exists notifications_dedupe_key
  on public.notifications (
    organization_id, type, entity_id, ((metadata ->> 'for_date'))
  )
  where entity_id is not null and metadata ? 'for_date';

create or replace function public.notify_due_commitments(p_organization_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row     record;
  v_created integer := 0;
begin
  perform app.require_capability(p_organization_id, 'commitments.read');

  for v_row in
    select
      c.id, c.title, c.due_date, c.created_by, c.amount_minor,
      c.settled_amount_minor, s.display_status
    from public.commitment_states s
    join public.commitments c on c.id = s.id
    where s.organization_id = p_organization_id
      and s.display_status in ('due', 'due_soon', 'overdue')
  loop
    begin
      insert into public.notifications (
        organization_id, user_id, type, title, body, entity_type, entity_id,
        severity, metadata
      )
      values (
        p_organization_id,
        v_row.created_by,
        case when v_row.display_status = 'overdue'
             then 'commitment.overdue' else 'commitment.due_soon' end,
        case when v_row.display_status = 'overdue'
             then 'A commitment is overdue' else 'A commitment is due soon' end,
        v_row.title,
        'commitment',
        v_row.id,
        case when v_row.display_status = 'overdue' then 'error' else 'warning' end,
        jsonb_build_object(
          'for_date', v_row.due_date::text,
          'outstanding_minor', v_row.amount_minor - v_row.settled_amount_minor
        )
      );
      v_created := v_created + 1;
    exception when unique_violation then
      -- Already told them about this commitment for this date.
      null;
    end;
  end loop;

  return v_created;
end;
$$;

comment on function public.notify_due_commitments(uuid) is
  'Idempotent reminder sweep. Safe to run on a schedule: the dedupe index means '
  'a commitment produces one notification per due date, not one per run.';

-- ---------------------------------------------------------------------------
-- Execute grants
-- ---------------------------------------------------------------------------
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
        'create_commitment', 'settle_commitment', 'cancel_commitment',
        'postpone_commitment', 'create_recurring_rule', 'run_recurring_schedule',
        'confirm_recurring_occurrence', 'skip_recurring_occurrence',
        'set_recurring_rule_status', 'notify_due_commitments'
      )
  loop
    execute format('revoke all on function %s from public, anon', v_fn.signature);
    execute format('grant execute on function %s to authenticated, service_role', v_fn.signature);
  end loop;
end;
$$;
