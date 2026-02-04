-- Migration: Immediate live game update enqueue on move
-- Purpose: Ensure Live Activities / Android live notifications update as soon as moves are saved
-- Created: 2026-02-04

-- Keep cron-based function updated with richer payload
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
    'live_game_update:' || g.id || ':' || coalesce(g.last_move_time::text, 'unknown')
  FROM public.games g
  LEFT JOIN public.tours t ON t.id = g.tour_id
  WHERE g.status IN ('*', 'ongoing')
    AND g.last_move_time IS NOT NULL
    AND g.last_move_time >= now() - interval '2 minutes'
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

-- Trigger-based enqueue for immediate updates when a move arrives
CREATE OR REPLACE FUNCTION public.queue_live_game_update_on_move()
RETURNS TRIGGER AS $$
DECLARE
  gb_id TEXT;
BEGIN
  -- Only act on new move timestamps
  IF NEW.last_move_time IS NULL THEN
    RETURN NEW;
  END IF;
  IF OLD.last_move_time IS NOT DISTINCT FROM NEW.last_move_time THEN
    RETURN NEW;
  END IF;
  IF NOT (NEW.status IN ('*', 'ongoing')) THEN
    RETURN NEW;
  END IF;

  SELECT t.group_broadcast_id INTO gb_id
    FROM public.tours t
   WHERE t.id = NEW.tour_id
   LIMIT 1;

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
    'live_game_update:' || NEW.id || ':' || coalesce(NEW.last_move_time::text, 'unknown')
  )
  ON CONFLICT (dedupe_key) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS queue_live_game_update_on_move ON public.games;
CREATE TRIGGER queue_live_game_update_on_move
  AFTER UPDATE OF last_move_time ON public.games
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_live_game_update_on_move();
