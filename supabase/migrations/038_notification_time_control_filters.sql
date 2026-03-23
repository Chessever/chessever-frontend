-- Migration: User-configurable notification filters and heads-up lead time
-- Adds three time-control filter columns (opt-out, default true so existing
-- users keep receiving all notifications) and a configurable heads-up lead
-- time (10 or 30 minutes before a round starts, default 30 to match the
-- previously hardcoded behaviour).
-- Created: 2026-03-21

ALTER TABLE public.user_notification_preferences
  ADD COLUMN IF NOT EXISTS notify_classical      BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notify_rapid          BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notify_blitz          BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS heads_up_lead_minutes INTEGER NOT NULL DEFAULT 30
    CONSTRAINT chk_heads_up_lead_minutes CHECK (heads_up_lead_minutes IN (10, 30));

-- Back-fill any existing rows so they are consistent with the new defaults.
-- (ADD COLUMN with DEFAULT already handles this in Postgres 11+, but the
--  explicit UPDATE makes the intent clear for future readers.)
UPDATE public.user_notification_preferences
SET
  notify_classical      = COALESCE(notify_classical,      true),
  notify_rapid          = COALESCE(notify_rapid,          true),
  notify_blitz          = COALESCE(notify_blitz,          true),
  heads_up_lead_minutes = COALESCE(heads_up_lead_minutes, 30)
WHERE
  notify_classical IS NULL
  OR notify_rapid IS NULL
  OR notify_blitz IS NULL
  OR heads_up_lead_minutes IS NULL;
