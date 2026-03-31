-- Migration: Normalize notification preference defaults
-- Purpose: Fix rows where DB defaults set live_game_updates and daily_digest
--          to true, contradicting the app's intended defaults of false.
-- Created: 2026-03-31
--
-- Heuristic: The app's _updatePreferences always writes all columns together.
-- If both live_game_updates AND daily_digest are true, the row was created by
-- _syncPreferenceToSupabase (push_enabled only) or by bare DB defaults —
-- because no UI exists for daily_digest, so only untouched rows have it as true.
-- Users who explicitly enabled live_game_updates via the settings UI will also
-- have daily_digest = false (written by the app upsert), so they are unaffected.

UPDATE public.user_notification_preferences
SET live_game_updates = false,
    daily_digest = false
WHERE live_game_updates = true
  AND daily_digest = true;
