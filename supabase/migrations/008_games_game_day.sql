-- Add normalized game day for favorites/countrymen paging

ALTER TABLE public.games
  ADD COLUMN IF NOT EXISTS game_day date;

CREATE OR REPLACE FUNCTION public.games_set_game_day()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.game_day := COALESCE(NEW.last_move_time::date, NEW.date_start);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_game_day ON public.games;
CREATE TRIGGER set_game_day
BEFORE INSERT OR UPDATE OF last_move_time, date_start
ON public.games
FOR EACH ROW
EXECUTE FUNCTION public.games_set_game_day();

-- Optional backfill for existing rows (run in batches if needed)
-- UPDATE public.games
-- SET game_day = COALESCE(last_move_time::date, date_start)
-- WHERE game_day IS NULL;

CREATE INDEX IF NOT EXISTS idx_games_game_day_last_move
  ON public.games (game_day DESC NULLS LAST, last_move_time DESC NULLS LAST)
  WHERE game_day IS NOT NULL;

-- Update distinct-date RPCs to use last_move_time day (fallback to date_start)
CREATE OR REPLACE FUNCTION public.get_distinct_dates_for_favorites(
  fide_ids bigint[],
  limit_count int DEFAULT 30,
  offset_count int DEFAULT 0
)
RETURNS TABLE(date_start date)
LANGUAGE sql
STABLE
AS $$
  SELECT DISTINCT COALESCE(game_day, last_move_time::date, date_start) AS date_start
  FROM public.games
  WHERE COALESCE(game_day, last_move_time::date, date_start) IS NOT NULL
    AND player_fide_ids && fide_ids
  ORDER BY date_start DESC
  OFFSET offset_count
  LIMIT limit_count;
$$;

CREATE OR REPLACE FUNCTION public.get_distinct_dates_for_country(
  country_code text,
  min_elo int DEFAULT 2000,
  limit_count int DEFAULT 30,
  offset_count int DEFAULT 0
)
RETURNS TABLE(date_start date)
LANGUAGE sql
STABLE
AS $$
  SELECT DISTINCT COALESCE(game_day, last_move_time::date, date_start) AS date_start
  FROM public.games
  WHERE COALESCE(game_day, last_move_time::date, date_start) IS NOT NULL
    AND player_feds @> ARRAY[upper(country_code)]
    AND player_max_rating >= min_elo
  ORDER BY date_start DESC
  OFFSET offset_count
  LIMIT limit_count;
$$;

ANALYZE public.games;
