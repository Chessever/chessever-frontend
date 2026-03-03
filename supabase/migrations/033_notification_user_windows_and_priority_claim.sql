-- Migration: Start-family cooldown table + priority-aware outbox claiming
-- Purpose: When game_started is sent to a user, suppress redundant round_started
--          for the same round within a cooldown window. Prioritize game-level events
--          over round/informational items in the claim queue.
-- Created: 2026-03-02

-- 1. Cooldown state table for start-family precedence
CREATE TABLE IF NOT EXISTS public.notification_user_windows (
  user_id UUID NOT NULL,
  round_id TEXT NOT NULL,
  family TEXT NOT NULL,           -- e.g. 'game_start'
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '20 seconds'),
  PRIMARY KEY (user_id, round_id, family)
);

-- No RLS needed — service-role only table
ALTER TABLE public.notification_user_windows ENABLE ROW LEVEL SECURITY;

-- Auto-cleanup: remove expired windows periodically (reuse existing cleanup cron pattern)
CREATE INDEX IF NOT EXISTS idx_nuw_expires_at
  ON public.notification_user_windows (expires_at);

-- Cleanup function for expired cooldown windows
CREATE OR REPLACE FUNCTION public.cleanup_notification_user_windows()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count integer;
BEGIN
  DELETE FROM public.notification_user_windows
  WHERE expires_at < now();
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

-- 2. Update claim function with priority ordering
-- Priority: game_started/game_finished first, then round/heads-up, then live_game_update last
CREATE OR REPLACE FUNCTION public.claim_notification_outbox_batch(p_limit integer DEFAULT 50)
RETURNS SETOF public.notification_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit integer := GREATEST(1, LEAST(COALESCE(p_limit, 50), 500));
BEGIN
  RETURN QUERY
  WITH candidates AS (
    SELECT n.id
    FROM public.notification_outbox n
    WHERE n.status = 'pending'
      AND n.not_before <= now()
    ORDER BY
      -- Priority: immediate game events first, round events next, live updates last
      CASE n.event_type
        WHEN 'game_started'  THEN 0
        WHEN 'game_finished' THEN 0
        WHEN 'round_started' THEN 1
        WHEN 'round_heads_up' THEN 1
        WHEN 'book_game_added' THEN 2
        WHEN 'call_to_action' THEN 3
        WHEN 'live_game_update' THEN 4
        ELSE 3
      END ASC,
      n.not_before ASC,
      n.created_at ASC
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.notification_outbox n
  SET status = 'processing',
      attempts = n.attempts + 1,
      updated_at = now()
  FROM candidates c
  WHERE n.id = c.id
  RETURNING n.*;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_notification_outbox_batch(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_notification_outbox_batch(integer) TO service_role;

-- 3. Helper: check if a user already received a game_started for this round (cooldown active)
CREATE OR REPLACE FUNCTION public.has_active_game_start_window(
  p_user_id UUID,
  p_round_id TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.notification_user_windows
    WHERE user_id = p_user_id
      AND round_id = p_round_id
      AND family = 'game_start'
      AND expires_at > now()
  );
$$;

-- 4. Helper: record that a user received a game_started for a round
CREATE OR REPLACE FUNCTION public.record_game_start_window(
  p_user_ids UUID[],
  p_round_id TEXT,
  p_cooldown_seconds INTEGER DEFAULT 20
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.notification_user_windows (user_id, round_id, family, expires_at)
  SELECT unnest(p_user_ids), p_round_id, 'game_start', now() + (p_cooldown_seconds || ' seconds')::interval
  ON CONFLICT (user_id, round_id, family)
  DO UPDATE SET expires_at = EXCLUDED.expires_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.has_active_game_start_window(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_active_game_start_window(UUID, TEXT) TO service_role;
REVOKE EXECUTE ON FUNCTION public.record_game_start_window(UUID[], TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_game_start_window(UUID[], TEXT, INTEGER) TO service_role;

-- 5. Update the priority index to support the new ordering
DROP INDEX IF EXISTS idx_notification_outbox_pending_claim;
CREATE INDEX idx_notification_outbox_pending_claim
  ON public.notification_outbox (
    (CASE event_type
      WHEN 'game_started'    THEN 0
      WHEN 'game_finished'   THEN 0
      WHEN 'round_started'   THEN 1
      WHEN 'round_heads_up'  THEN 1
      WHEN 'book_game_added' THEN 2
      WHEN 'call_to_action'  THEN 3
      WHEN 'live_game_update' THEN 4
      ELSE 3
    END),
    not_before,
    created_at,
    id
  )
  WHERE status = 'pending';
