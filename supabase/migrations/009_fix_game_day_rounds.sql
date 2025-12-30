-- Fix game_day to use round start when last_move_time is null.

CREATE OR REPLACE FUNCTION public.games_set_game_day()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  round_start date;
BEGIN
  IF NEW.round_id IS NOT NULL THEN
    SELECT starts_at::date
      INTO round_start
      FROM public.rounds
     WHERE id = NEW.round_id;
  END IF;

  NEW.game_day := COALESCE(NEW.last_move_time::date, round_start, NEW.date_start);
  RETURN NEW;
END;
$$;

-- Backfill game_day for existing rows using round starts when available.
UPDATE public.games g
   SET game_day = COALESCE(g.last_move_time::date, r.starts_at::date, g.date_start)
  FROM public.rounds r
 WHERE g.round_id = r.id
   AND g.game_day IS DISTINCT FROM COALESCE(g.last_move_time::date, r.starts_at::date, g.date_start);

-- Fallback backfill when round_id is missing.
UPDATE public.games g
   SET game_day = COALESCE(g.last_move_time::date, g.date_start)
 WHERE g.round_id IS NULL
   AND g.game_day IS DISTINCT FROM COALESCE(g.last_move_time::date, g.date_start);

ANALYZE public.games;
