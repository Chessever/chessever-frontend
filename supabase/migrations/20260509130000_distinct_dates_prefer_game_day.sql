-- Fix Favorites/Countrymen "Games" date bucketing: live games getting hidden
-- under earlier dates because the RPC's COALESCE prefers games.date_start.
--
-- The current production definitions resolve to
--   COALESCE(date_start, game_day, last_move_time::date)
-- but games.date_start is the day the broadcast pairings were uploaded to
-- Lichess, not the round day. For tournaments whose pairings are pre-created
-- (e.g. GCT Super Rapid & Blitz Poland 2026 — all 18 rounds uploaded on
-- 2026-05-03), date_start is several days off from the actual play day, while
-- games.game_day (PGN [Date]) and last_move_time agree with rounds.starts_at.
--
-- Restore the order originally established in 008/010:
--   COALESCE(game_day, last_move_time::date, date_start)
-- This preserves the existing return shape (column aliased as `date_start`)
-- so all callers stay backwards-compatible.

CREATE OR REPLACE FUNCTION public.get_distinct_dates_for_favorites(
  fide_ids bigint[],
  limit_count int DEFAULT 30,
  offset_count int DEFAULT 0
)
RETURNS TABLE(date_start date)
LANGUAGE sql
STABLE
AS $$
  SELECT DISTINCT COALESCE(games.game_day, games.last_move_time::date, games.date_start) AS date_start
  FROM public.games
  WHERE COALESCE(games.game_day, games.last_move_time::date, games.date_start) IS NOT NULL
    AND COALESCE(games.game_day, games.last_move_time::date, games.date_start) <= CURRENT_DATE
    AND games.player_fide_ids && fide_ids
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
  SELECT DISTINCT COALESCE(games.game_day, games.last_move_time::date, games.date_start) AS date_start
  FROM public.games
  WHERE COALESCE(games.game_day, games.last_move_time::date, games.date_start) IS NOT NULL
    AND COALESCE(games.game_day, games.last_move_time::date, games.date_start) <= CURRENT_DATE
    AND games.player_feds @> ARRAY[upper(country_code)]
    AND games.player_max_rating >= min_elo
  ORDER BY date_start DESC
  OFFSET offset_count
  LIMIT limit_count;
$$;
