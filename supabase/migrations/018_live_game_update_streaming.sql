-- Migration: Stream live game updates on board/clock changes
-- Purpose: Ensure Live Activities and Android live notifications update on
--          clock, FEN, move, or status changes (not just move timestamps).
-- Created: 2026-02-05

-- Keep cron-based function updated with richer dedupe key
CREATE OR REPLACE FUNCTION public.queue_live_game_updates()
RETURNS void AS $$
BEGIN
  INSERT INTO public.notification_outbox (
    event_type,
    game_id,
    tour_id,
    round_id,
    group_broadcast_id,
    payload,
    dedupe_key
  )
  SELECT
    'live_game_update',
    g.id,
    g.tour_id,
    g.round_id,
    t.group_broadcast_id,
    jsonb_build_object(
      'last_move', g.last_move,
      'last_move_uci', g.last_move,
      'last_move_time', g.last_move_time,
      'player_white', g.player_white,
      'player_black', g.player_black,
      'players', g.players,
      'fen', g.fen,
      'status', g.status,
      'last_clock_white', g.last_clock_white,
      'last_clock_black', g.last_clock_black
    ),
    'live_game_update:' || g.id || ':' ||
      coalesce(g.last_move_time::text, '') || ':' ||
      coalesce(g.last_clock_white::text, '') || ':' ||
      coalesce(g.last_clock_black::text, '') || ':' ||
      coalesce(g.status, '') || ':' ||
      md5(coalesce(g.fen, ''))
  FROM public.games g
  LEFT JOIN public.tours t ON t.id = g.tour_id
  WHERE g.status IS NOT NULL
    AND g.status IN ('*', 'ongoing')
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

-- Trigger-based enqueue for immediate updates when clocks/FEN/status/move changes
CREATE OR REPLACE FUNCTION public.queue_live_game_update_on_change()
RETURNS TRIGGER AS $$
DECLARE
  gb_id TEXT;
  dedupe TEXT;
BEGIN
  -- Only act when there is a meaningful change
  IF (OLD.last_move_time IS NOT DISTINCT FROM NEW.last_move_time)
     AND (OLD.last_clock_white IS NOT DISTINCT FROM NEW.last_clock_white)
     AND (OLD.last_clock_black IS NOT DISTINCT FROM NEW.last_clock_black)
     AND (OLD.fen IS NOT DISTINCT FROM NEW.fen)
     AND (OLD.status IS NOT DISTINCT FROM NEW.status)
     AND (OLD.last_move IS NOT DISTINCT FROM NEW.last_move) THEN
    RETURN NEW;
  END IF;

  -- Only enqueue while game is active, or when transitioning out of active
  IF NOT (NEW.status IN ('*', 'ongoing') OR OLD.status IN ('*', 'ongoing')) THEN
    RETURN NEW;
  END IF;

  SELECT t.group_broadcast_id INTO gb_id
    FROM public.tours t
   WHERE t.id = NEW.tour_id
   LIMIT 1;

  dedupe := 'live_game_update:' || NEW.id || ':' ||
    coalesce(NEW.last_move_time::text, '') || ':' ||
    coalesce(NEW.last_clock_white::text, '') || ':' ||
    coalesce(NEW.last_clock_black::text, '') || ':' ||
    coalesce(NEW.status, '') || ':' ||
    md5(coalesce(NEW.fen, ''));

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
    'live_game_update',
    NEW.id,
    NEW.tour_id,
    NEW.round_id,
    gb_id,
    jsonb_build_object(
      'last_move', NEW.last_move,
      'last_move_uci', NEW.last_move,
      'last_move_time', NEW.last_move_time,
      'player_white', NEW.player_white,
      'player_black', NEW.player_black,
      'players', NEW.players,
      'fen', NEW.fen,
      'status', NEW.status,
      'last_clock_white', NEW.last_clock_white,
      'last_clock_black', NEW.last_clock_black
    ),
    dedupe
  )
  ON CONFLICT (dedupe_key) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS queue_live_game_update_on_move ON public.games;
DROP TRIGGER IF EXISTS queue_live_game_update_on_change ON public.games;

CREATE TRIGGER queue_live_game_update_on_change
  AFTER UPDATE OF last_move_time, last_clock_white, last_clock_black, fen, status, last_move
  ON public.games
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_live_game_update_on_change();
