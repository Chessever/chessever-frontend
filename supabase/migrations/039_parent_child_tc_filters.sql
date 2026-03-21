-- Migration: Independent time-control filters per notification category
-- Replaces the three shared notify_classical/rapid/blitz columns with six
-- independent columns — one set for Favourite Players, one for Starred Events.
-- The old notify_* columns are intentionally retained (not dropped) so that
-- any already-deployed builds that still read them continue to work without
-- errors.  The edge function will use the new columns exclusively after
-- deploying the corresponding function update.
-- Created: 2026-03-22

ALTER TABLE public.user_notification_preferences
  ADD COLUMN IF NOT EXISTS fp_classical  BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS fp_rapid      BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS fp_blitz      BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS se_classical  BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS se_rapid      BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS se_blitz      BOOLEAN NOT NULL DEFAULT true;

-- Seed the new columns from the existing shared columns so that users who
-- already customised their preferences (e.g. turned off notify_blitz) keep
-- the same effective behaviour after the migration.
UPDATE public.user_notification_preferences
SET
  fp_classical = COALESCE(fp_classical, notify_classical, true),
  fp_rapid     = COALESCE(fp_rapid,     notify_rapid,     true),
  fp_blitz     = COALESCE(fp_blitz,     notify_blitz,     true),
  se_classical = COALESCE(se_classical, notify_classical, true),
  se_rapid     = COALESCE(se_rapid,     notify_rapid,     true),
  se_blitz     = COALESCE(se_blitz,     notify_blitz,     true)
WHERE
  fp_classical IS NULL OR fp_rapid IS NULL OR fp_blitz IS NULL
  OR se_classical IS NULL OR se_rapid IS NULL OR se_blitz IS NULL;
-- (ADD COLUMN NOT NULL DEFAULT in PG 15+ already fills all existing rows via
-- the DEFAULT, so the WHERE clause will match zero rows in practice.  The
-- UPDATE is kept for explicit intent and defensive correctness.)
