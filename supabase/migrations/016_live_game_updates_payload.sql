-- Migration: Enrich live game update payload with FEN + players metadata
-- Purpose: Support Live Activities / live notifications rendering
-- Created: 2026-02-03

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
      'last_move_time', g.last_move_time,
      'player_white', g.player_white,
      'player_black', g.player_black,
      'players', g.players,
      'fen', g.fen,
      'status', g.status
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
