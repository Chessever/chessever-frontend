-- Helpers for fast favorites/countrymen queries without missing games

-- 1) Extractors for generated columns
CREATE OR REPLACE FUNCTION public.games_player_fide_ids(players jsonb)
RETURNS bigint[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    array_agg(DISTINCT (p->>'fideId')::bigint)
      FILTER (WHERE (p->>'fideId') ~ '^[0-9]+$'),
    ARRAY[]::bigint[]
  )
  FROM jsonb_array_elements(COALESCE(players, '[]'::jsonb)) p;
$$;

CREATE OR REPLACE FUNCTION public.games_player_feds(players jsonb)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    array_agg(DISTINCT upper(p->>'fed'))
      FILTER (WHERE p ? 'fed' AND p->>'fed' <> ''),
    ARRAY[]::text[]
  )
  FROM jsonb_array_elements(COALESCE(players, '[]'::jsonb)) p;
$$;

CREATE OR REPLACE FUNCTION public.games_player_max_rating(players jsonb)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    MAX((p->>'rating')::int)
      FILTER (WHERE (p->>'rating') ~ '^[0-9]+$'),
    0
  )
  FROM jsonb_array_elements(COALESCE(players, '[]'::jsonb)) p;
$$;

-- 2) Generated columns on games
ALTER TABLE public.games
  ADD COLUMN IF NOT EXISTS player_fide_ids bigint[] GENERATED ALWAYS AS (public.games_player_fide_ids(players)) STORED;

ALTER TABLE public.games
  ADD COLUMN IF NOT EXISTS player_feds text[] GENERATED ALWAYS AS (public.games_player_feds(players)) STORED;

ALTER TABLE public.games
  ADD COLUMN IF NOT EXISTS player_max_rating int GENERATED ALWAYS AS (public.games_player_max_rating(players)) STORED;

-- 3) Indexes for overlap/contains + ordering
CREATE INDEX IF NOT EXISTS idx_games_player_fide_ids_gin
  ON public.games USING gin (player_fide_ids);

CREATE INDEX IF NOT EXISTS idx_games_player_feds_gin
  ON public.games USING gin (player_feds);

CREATE INDEX IF NOT EXISTS idx_games_player_max_rating
  ON public.games (player_max_rating);

CREATE INDEX IF NOT EXISTS idx_games_date_start_last_move
  ON public.games (date_start DESC NULLS LAST, last_move_time DESC NULLS LAST)
  WHERE date_start IS NOT NULL;

-- 4) RPCs for distinct dates (server-side paging)
CREATE OR REPLACE FUNCTION public.get_distinct_dates_for_favorites(
  fide_ids bigint[],
  limit_count int DEFAULT 30,
  offset_count int DEFAULT 0
)
RETURNS TABLE(date_start date)
LANGUAGE sql
STABLE
AS $$
  SELECT DISTINCT date_start
  FROM public.games
  WHERE date_start IS NOT NULL
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
  SELECT DISTINCT date_start
  FROM public.games
  WHERE date_start IS NOT NULL
    AND player_feds @> ARRAY[upper(country_code)]
    AND player_max_rating >= min_elo
  ORDER BY date_start DESC
  OFFSET offset_count
  LIMIT limit_count;
$$;

ANALYZE public.games;
