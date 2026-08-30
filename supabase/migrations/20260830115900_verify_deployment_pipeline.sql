-- Connectivity smoke test for the Git-linked Supabase deployment.
--
-- This migration exists to prove exactly one thing: that a migration committed
-- to the production branch is detected and applied to the linked project.
--
-- It creates nothing, drops nothing and touches no data. It only sets a comment
-- on the public schema, so it runs successfully against a completely empty
-- database and has nothing to roll back.
--
-- Confirm it landed:
--
--   select obj_description('public'::regnamespace, 'pg_namespace');
--   select version, name from supabase_migrations.schema_migrations
--   order by version desc limit 5;
--
-- Timestamped 11:59 on purpose — earlier than every foundation migration
-- (12:00 onwards). Applying a later-versioned migration first would leave the
-- real chain out of order and could block it from deploying afterwards.
--
-- This is still permanent migration history. Leave it in place; do not delete
-- it later to tidy up.

comment on schema public is
  'Ledger Suit application schema. Git-linked deployment pipeline verified 2026-08-30.';
