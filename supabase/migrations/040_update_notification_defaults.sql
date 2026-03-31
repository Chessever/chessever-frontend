-- Migration: Update notification preference defaults
-- 1. heads_up_alerts defaults to true (round starting notification on by default)
-- 2. heads_up_lead_minutes defaults to 5 and allows 5 as an option
-- 3. book_update_alerts defaults to false (database updates not default)
-- 4. call_to_action_alerts defaults to true (Chess World is default)

-- Update column defaults
ALTER TABLE public.user_notification_preferences
  ALTER COLUMN heads_up_alerts SET DEFAULT true;

ALTER TABLE public.user_notification_preferences
  ALTER COLUMN book_update_alerts SET DEFAULT false;

ALTER TABLE public.user_notification_preferences
  ALTER COLUMN call_to_action_alerts SET DEFAULT true;

-- Drop old constraint and add new one that includes 5
ALTER TABLE public.user_notification_preferences
  DROP CONSTRAINT IF EXISTS chk_heads_up_lead_minutes;

ALTER TABLE public.user_notification_preferences
  ALTER COLUMN heads_up_lead_minutes SET DEFAULT 5;

ALTER TABLE public.user_notification_preferences
  ADD CONSTRAINT chk_heads_up_lead_minutes CHECK (heads_up_lead_minutes IN (5, 10, 30));
