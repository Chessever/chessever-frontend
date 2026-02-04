-- Migration: Add heads_up_alerts column to user_notification_preferences
-- Purpose: Enable users to opt-in to heads-up notifications for upcoming rounds
-- Created: 2026-02-04

-- Add heads_up_alerts column if it doesn't exist
ALTER TABLE public.user_notification_preferences
ADD COLUMN IF NOT EXISTS heads_up_alerts BOOLEAN NOT NULL DEFAULT false;

-- Comment for documentation
COMMENT ON COLUMN public.user_notification_preferences.heads_up_alerts IS
  'User preference for receiving heads-up notifications before rounds start (30 min lead time)';
