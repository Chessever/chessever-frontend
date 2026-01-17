-- Exclude future dates from favorites/countrymen date tabs.

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
    AND COALESCE(game_day, last_move_time::date, date_start) <= CURRENT_DATE
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
    AND COALESCE(game_day, last_move_time::date, date_start) <= CURRENT_DATE
    AND player_feds @> ARRAY[upper(country_code)]
    AND player_max_rating >= min_elo
  ORDER BY date_start DESC
  OFFSET offset_count
  LIMIT limit_count;
$$;
