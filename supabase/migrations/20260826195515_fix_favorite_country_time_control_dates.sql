-- Date pagination must use the games.tour_id foreign key. tour_slug is legacy
-- denormalized data and is null/stale for otherwise valid broadcast games,
-- which made the Blitz filter omit dates that the per-day game query returned.

-- Remove obsolete short overloads so PostgREST cannot see an ambiguous RPC.
DROP FUNCTION IF EXISTS public.get_distinct_dates_for_favorites(
  bigint[], integer, integer
);
DROP FUNCTION IF EXISTS public.get_distinct_dates_for_country(
  text, integer, integer, integer
);

CREATE OR REPLACE FUNCTION public.get_distinct_dates_for_favorites(
  fide_ids bigint[],
  limit_count integer DEFAULT 30,
  offset_count integer DEFAULT 0,
  p_status text DEFAULT NULL,
  p_result text DEFAULT NULL,
  p_time_control text DEFAULT NULL,
  p_min_year integer DEFAULT NULL,
  p_max_year integer DEFAULT NULL,
  p_min_rating integer DEFAULT NULL,
  p_max_rating integer DEFAULT NULL,
  p_eco text DEFAULT NULL,
  p_color text DEFAULT NULL
)
RETURNS TABLE(date_start date)
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT DISTINCT COALESCE(g.game_day, g.last_move_time::date, g.date_start) AS date_start
  FROM public.games g
  WHERE g.player_fide_ids && fide_ids
    AND COALESCE(g.game_day, g.last_move_time::date, g.date_start) IS NOT NULL
    AND COALESCE(g.game_day, g.last_move_time::date, g.date_start) <= CURRENT_DATE
    AND (p_status IS NULL
         OR (p_status = 'live'      AND (g.status IS NULL OR g.status = '*'))
         OR (p_status = 'completed' AND g.status IS NOT NULL AND g.status <> '*'))
    AND (p_result IS NULL
         OR (p_result = '1-0' AND g.status = '1-0')
         OR (p_result = '0-1' AND g.status = '0-1')
         OR (p_result IN ('1/2', '1/2-1/2', 'draw')
             AND g.status IN ('1/2', '1/2-1/2', '½-½')))
    AND (p_time_control IS NULL
         OR g.tour_id IN (
              SELECT t.id
              FROM public.tours t
              JOIN public.group_broadcasts gb ON gb.id = t.group_broadcast_id
              WHERE gb.time_control = p_time_control))
    AND (p_min_year IS NULL
         OR EXTRACT(year FROM COALESCE(g.game_day, g.last_move_time::date, g.date_start)) >= p_min_year)
    AND (p_max_year IS NULL
         OR EXTRACT(year FROM COALESCE(g.game_day, g.last_move_time::date, g.date_start)) <= p_max_year)
    AND (p_min_rating IS NULL OR g.player_max_rating >= p_min_rating)
    AND (p_max_rating IS NULL OR g.player_max_rating <= p_max_rating)
    AND (p_eco IS NULL OR g.eco ILIKE (p_eco || '%'))
    AND (p_color IS NULL
         OR (p_color = 'white'
             AND (NULLIF(g.players->0->>'fideId', ''))::bigint = ANY(fide_ids))
         OR (p_color = 'black'
             AND (NULLIF(g.players->1->>'fideId', ''))::bigint = ANY(fide_ids)))
  ORDER BY date_start DESC
  OFFSET offset_count
  LIMIT limit_count;
$function$;

CREATE OR REPLACE FUNCTION public.get_distinct_dates_for_country(
  country_code text,
  min_elo integer DEFAULT 0,
  limit_count integer DEFAULT 30,
  offset_count integer DEFAULT 0,
  p_status text DEFAULT NULL,
  p_result text DEFAULT NULL,
  p_time_control text DEFAULT NULL,
  p_min_year integer DEFAULT NULL,
  p_max_year integer DEFAULT NULL,
  p_max_rating integer DEFAULT NULL,
  p_eco text DEFAULT NULL,
  p_color text DEFAULT NULL
)
RETURNS TABLE(date_start date)
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT DISTINCT COALESCE(g.game_day, g.last_move_time::date, g.date_start) AS date_start
  FROM public.games g
  WHERE g.player_feds @> ARRAY[upper(country_code)]
    AND g.player_max_rating >= min_elo
    AND COALESCE(g.game_day, g.last_move_time::date, g.date_start) IS NOT NULL
    AND COALESCE(g.game_day, g.last_move_time::date, g.date_start) <= CURRENT_DATE
    AND (p_status IS NULL
         OR (p_status = 'live'      AND (g.status IS NULL OR g.status = '*'))
         OR (p_status = 'completed' AND g.status IS NOT NULL AND g.status <> '*'))
    AND (p_result IS NULL
         OR (p_result = '1-0' AND g.status = '1-0')
         OR (p_result = '0-1' AND g.status = '0-1')
         OR (p_result IN ('1/2', '1/2-1/2', 'draw')
             AND g.status IN ('1/2', '1/2-1/2', '½-½')))
    AND (p_time_control IS NULL
         OR g.tour_id IN (
              SELECT t.id
              FROM public.tours t
              JOIN public.group_broadcasts gb ON gb.id = t.group_broadcast_id
              WHERE gb.time_control = p_time_control))
    AND (p_min_year IS NULL
         OR EXTRACT(year FROM COALESCE(g.game_day, g.last_move_time::date, g.date_start)) >= p_min_year)
    AND (p_max_year IS NULL
         OR EXTRACT(year FROM COALESCE(g.game_day, g.last_move_time::date, g.date_start)) <= p_max_year)
    AND (p_max_rating IS NULL OR g.player_max_rating <= p_max_rating)
    AND (p_eco IS NULL OR g.eco ILIKE (p_eco || '%'))
    AND (p_color IS NULL
         OR (p_color = 'white' AND upper(g.players->0->>'fed') = upper(country_code))
         OR (p_color = 'black' AND upper(g.players->1->>'fed') = upper(country_code)))
  ORDER BY date_start DESC
  OFFSET offset_count
  LIMIT limit_count;
$function$;
