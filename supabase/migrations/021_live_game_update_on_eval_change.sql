-- Migration: Trigger live game updates when evals change
-- Purpose: Ensure eval bar/text updates in Live Activities + Android live notifications
-- Created: 2026-02-05

CREATE OR REPLACE FUNCTION public.queue_live_game_update_on_eval_change()
RETURNS TRIGGER AS $$
DECLARE
  fen_text text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF (OLD.depth IS NOT DISTINCT FROM NEW.depth)
       AND (OLD.pvs IS NOT DISTINCT FROM NEW.pvs)
       AND (OLD.knodes IS NOT DISTINCT FROM NEW.knodes)
       AND (OLD.multi_pv IS NOT DISTINCT FROM NEW.multi_pv)
       AND (OLD.pvs_count IS NOT DISTINCT FROM NEW.pvs_count) THEN
      RETURN NEW;
    END IF;
  END IF;

  SELECT p.fen INTO fen_text
    FROM public.positions p
   WHERE p.id = NEW.position_id
   LIMIT 1;

  IF fen_text IS NULL OR fen_text = '' THEN
    RETURN NEW;
  END IF;

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
    'live_game_eval:' || g.id || ':' ||
      NEW.id::text || ':' ||
      coalesce(NEW.depth::text, '') || ':' ||
      md5(NEW.pvs::text)
  FROM public.games g
  LEFT JOIN public.tours t ON t.id = g.tour_id
  WHERE g.fen = fen_text
    AND g.status IN ('*', 'ongoing')
  ON CONFLICT (dedupe_key) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS queue_live_game_update_on_eval_change ON public.evals;

CREATE TRIGGER queue_live_game_update_on_eval_change
  AFTER INSERT OR UPDATE OF depth, pvs, knodes, multi_pv, pvs_count
  ON public.evals
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_live_game_update_on_eval_change();

