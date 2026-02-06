-- Migration: Add call_to_action_alerts column to user_notification_preferences
-- Purpose: Enable users to opt-in to call-to-action notifications (chess/Chessever world updates)
-- Created: 2026-02-06

-- Add call_to_action_alerts column if it doesn't exist (OFF by default)
ALTER TABLE public.user_notification_preferences
ADD COLUMN IF NOT EXISTS call_to_action_alerts BOOLEAN NOT NULL DEFAULT false;

-- Comment for documentation
COMMENT ON COLUMN public.user_notification_preferences.call_to_action_alerts IS
  'User preference for receiving call-to-action notifications about chess and Chessever world updates (opt-in, off by default)';
