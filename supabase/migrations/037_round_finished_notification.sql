-- Migration: Round finished digest notification
-- Purpose: When the last game in a round finishes, queue a single round_finished
--          outbox row containing a full results snapshot. The edge function handler
--          sends one "Carlsen 1-0 · Caruana ½-½ +4" digest to event-starred users.
-- Strategy: Add the round_finished check inside the existing queue_game_notifications()
--           trigger rather than adding a separate trigger on the games table.
-- Created: 2026-03-21

-- 1. Extend queue_game_notifications() to also fire round_finished
--    when the last game in a round transitions to a finished state.
CREATE OR REPLACE FUNCTION public.queue_game_notifications()
RETURNS TRIGGER AS $$
DECLARE
  is_live      BOOLEAN;
  was_live     BOOLEAN;
  is_finished  BOOLEAN;
  was_finished BOOLEAN;
  gb_id        TEXT;
  v_board_nr   SMALLINT;
BEGIN
  is_live      := NEW.status IN ('*', 'ongoing');
  was_live     := OLD.status IN ('*', 'ongoing');
  is_finished  := public.is_game_finished(NEW.status);
  was_finished := public.is_game_finished(OLD.status);

  SELECT t.group_broadcast_id INTO gb_id
    FROM public.tours t
   WHERE t.id = NEW.tour_id
   LIMIT 1;

  v_board_nr := NEW.board_nr;

  -- Game started: status became live or first move arrived while live.
  IF is_live AND NEW.last_move_time IS NOT NULL
     AND (NOT was_live OR OLD.last_move_time IS NULL) THEN

    -- Piggyback round_started when game goes live and has a round_id.
    -- Catches rounds without starts_at or missed by cron.
    IF NEW.round_id IS NOT NULL THEN
      INSERT INTO public.notification_outbox (
        event_type, round_id, tour_id, group_broadcast_id, payload, dedupe_key
      )
      VALUES (
        'round_started',
        NEW.round_id,
        NEW.tour_id,
        gb_id,
        jsonb_build_object(
          'round_name', (SELECT r.name FROM public.rounds r WHERE r.id = NEW.round_id LIMIT 1),
          'starts_at', now()
        ),
        'round_started:' || NEW.round_id
      )
      ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;

    -- Always queue game_started (no round-based suppression).
    INSERT INTO public.notification_outbox (
      event_type, game_id, tour_id, round_id, group_broadcast_id, payload, dedupe_key
    )
    VALUES (
      'game_started',
      NEW.id,
      NEW.tour_id,
      NEW.round_id,
      gb_id,
      jsonb_build_object(
        'status',          NEW.status,
        'last_move_time',  NEW.last_move_time,
        'player_white',    NEW.player_white,
        'player_black',    NEW.player_black,
        'board_nr',        v_board_nr
      ),
      'game_started:' || NEW.id
    )
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;

  -- Game finished: status transitioned to a finished state.
  IF is_finished AND NOT was_finished THEN
    INSERT INTO public.notification_outbox (
      event_type, game_id, tour_id, round_id, group_broadcast_id, payload, dedupe_key
    )
    VALUES (
      'game_finished',
      NEW.id,
      NEW.tour_id,
      NEW.round_id,
      gb_id,
      jsonb_build_object(
        'status',          NEW.status,
        'last_move_time',  NEW.last_move_time,
        'player_white',    NEW.player_white,
        'player_black',    NEW.player_black,
        'board_nr',        v_board_nr
      ),
      'game_finished:' || NEW.id
    )
    ON CONFLICT (dedupe_key) DO NOTHING;

    -- Round finished: this was the last game in the round to finish.
    -- Guard: only fire when round_id is set AND no other game in the round
    -- is still unfinished. ON CONFLICT handles simultaneous last-game finishes.
    IF NEW.round_id IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.games
         WHERE round_id = NEW.round_id
           AND id       != NEW.id
           AND NOT public.is_game_finished(status)
      ) THEN
        INSERT INTO public.notification_outbox (
          event_type, round_id, tour_id, group_broadcast_id, payload, dedupe_key
        )
        VALUES (
          'round_finished',
          NEW.round_id,
          NEW.tour_id,
          gb_id,
          jsonb_build_object(
            'results', (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'white',    g2.player_white,
                  'black',    g2.player_black,
                  'status',   g2.status,
                  'board_nr', g2.board_nr
                ) ORDER BY COALESCE(g2.board_nr, 32767), g2.player_white NULLS LAST
              )
              FROM public.games g2
              WHERE g2.round_id = NEW.round_id
            )
          ),
          'round_finished:' || NEW.round_id
        )
        ON CONFLICT (dedupe_key) DO NOTHING;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Add round_finished to the priority claim function (priority 1 = same as round_started).
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
      CASE n.event_type
        WHEN 'game_started'   THEN 0
        WHEN 'game_finished'  THEN 0
        WHEN 'round_started'  THEN 1
        WHEN 'round_heads_up' THEN 1
        WHEN 'round_finished' THEN 1
        WHEN 'book_game_added'   THEN 2
        WHEN 'book_game_updated' THEN 2
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
  SET status     = 'processing',
      attempts   = n.attempts + 1,
      updated_at = now()
  FROM candidates c
  WHERE n.id = c.id
  RETURNING n.*;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_notification_outbox_batch(integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.claim_notification_outbox_batch(integer) TO service_role;

-- 3. Rebuild the claim index to include round_finished at priority 1.
DROP INDEX IF EXISTS idx_notification_outbox_pending_claim;
CREATE INDEX idx_notification_outbox_pending_claim
  ON public.notification_outbox (
    (CASE event_type
      WHEN 'game_started'    THEN 0
      WHEN 'game_finished'   THEN 0
      WHEN 'round_started'   THEN 1
      WHEN 'round_heads_up'  THEN 1
      WHEN 'round_finished'  THEN 1
      WHEN 'book_game_added'    THEN 2
      WHEN 'book_game_updated'  THEN 2
      WHEN 'call_to_action'  THEN 3
      WHEN 'live_game_update' THEN 4
      ELSE 3
    END),
    not_before,
    created_at,
    id
  )
  WHERE status = 'pending';
