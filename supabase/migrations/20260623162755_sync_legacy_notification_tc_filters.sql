-- Migration: Sync legacy shared time-control notification filters
-- Purpose: Keep older dispatchers/builds from ignoring the newer independent
-- favorite-player/starred-event filter columns. The legacy notify_* columns
-- cannot represent category-specific preferences, so they are set to the most
-- restrictive union: a shared bucket stays enabled only when both categories
-- allow it.
-- Created: 2026-06-23

UPDATE public.user_notification_preferences
SET
  notify_classical = fp_classical AND se_classical,
  notify_rapid = fp_rapid AND se_rapid,
  notify_blitz = fp_blitz AND se_blitz
WHERE
  notify_classical IS DISTINCT FROM (fp_classical AND se_classical)
  OR notify_rapid IS DISTINCT FROM (fp_rapid AND se_rapid)
  OR notify_blitz IS DISTINCT FROM (fp_blitz AND se_blitz);
