-- Migration: Remove round-based suppression of game_started, add board_nr to game payloads
-- Purpose: Per-game notifications should always fire independently of round_started.
--          Board number is included in payloads so downstream can display "Board 3" etc.
-- Created: 2026-03-02

CREATE OR REPLACE FUNCTION public.queue_game_notifications()
RETURNS TRIGGER AS $$
DECLARE
  is_live BOOLEAN;
  was_live BOOLEAN;
  is_finished BOOLEAN;
  was_finished BOOLEAN;
  gb_id TEXT;
  v_board_nr SMALLINT;
BEGIN
  is_live := NEW.status IN ('*', 'ongoing');
  was_live := OLD.status IN ('*', 'ongoing');
  is_finished := public.is_game_finished(NEW.status);
  was_finished := public.is_game_finished(OLD.status);

  SELECT t.group_broadcast_id INTO gb_id
    FROM public.tours t
   WHERE t.id = NEW.tour_id
   LIMIT 1;

  v_board_nr := NEW.board_nr;

  -- Game started: status became live or first move arrived while live.
  IF is_live AND NEW.last_move_time IS NOT NULL AND (NOT was_live OR OLD.last_move_time IS NULL) THEN

    -- Piggyback round_started when game goes live and has a round_id.
    -- Catches rounds without starts_at or missed by cron.
    IF NEW.round_id IS NOT NULL THEN
      INSERT INTO public.notification_outbox (
        event_type,
        round_id,
        tour_id,
        group_broadcast_id,
        payload,
        dedupe_key
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
      event_type,
      game_id,
      tour_id,
      round_id,
      group_broadcast_id,
      payload,
      dedupe_key
    )
    VALUES (
      'game_started',
      NEW.id,
      NEW.tour_id,
      NEW.round_id,
      gb_id,
      jsonb_build_object(
        'status', NEW.status,
        'last_move_time', NEW.last_move_time,
        'player_white', NEW.player_white,
        'player_black', NEW.player_black,
        'board_nr', v_board_nr
      ),
      'game_started:' || NEW.id
    )
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;

  -- Game finished: status transitioned to a finished state.
  IF is_finished AND NOT was_finished THEN
    INSERT INTO public.notification_outbox (
      event_type,
      game_id,
      tour_id,
      round_id,
      group_broadcast_id,
      payload,
      dedupe_key
    )
    VALUES (
      'game_finished',
      NEW.id,
      NEW.tour_id,
      NEW.round_id,
      gb_id,
      jsonb_build_object(
        'status', NEW.status,
        'last_move_time', NEW.last_move_time,
        'player_white', NEW.player_white,
        'player_black', NEW.player_black,
        'board_nr', v_board_nr
      ),
      'game_finished:' || NEW.id
    )
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
