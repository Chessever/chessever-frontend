-- Let the hourly prewarmer scan past reports produced by earlier hourly runs.
-- The Worker still queues at most ten new reports; this wider ranked pool is
-- what turns ten repeatedly inspected games into up to 240 unique games/day.

create or replace function public.get_report_prewarm_candidates(
  p_since timestamptz default (now() - interval '24 hours'),
  p_limit integer default 10
)
returns table (
  game_id text,
  pgn text,
  white_rating integer,
  black_rating integer,
  average_rating numeric,
  finished_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  with rated_finished_games as (
    select
      g.id as game_id,
      g.pgn,
      (g.players->0->>'rating')::integer as white_rating,
      (g.players->1->>'rating')::integer as black_rating,
      (
        (g.players->0->>'rating')::numeric
        + (g.players->1->>'rating')::numeric
      ) / 2 as average_rating,
      g.last_move_time as finished_at
    from public.games g
    where public.is_game_finished(g.status)
      and g.last_move_time >= coalesce(p_since, now() - interval '24 hours')
      and coalesce(g.pgn, '') ~ '(?m)^1[.]'
      and jsonb_typeof(g.players) = 'array'
      and jsonb_array_length(g.players) >= 2
      and g.players->0->>'rating' ~ '^[0-9]+$'
      and g.players->1->>'rating' ~ '^[0-9]+$'
      and (g.players->0->>'rating')::integer between 1 and 4000
      and (g.players->1->>'rating')::integer between 1 and 4000
  )
  select
    candidate.game_id,
    candidate.pgn,
    candidate.white_rating,
    candidate.black_rating,
    candidate.average_rating,
    candidate.finished_at
  from rated_finished_games candidate
  order by
    candidate.average_rating desc,
    candidate.finished_at desc,
    candidate.game_id
  limit greatest(1, least(coalesce(p_limit, 10), 500));
$$;

revoke all on function public.get_report_prewarm_candidates(timestamptz, integer)
  from public, anon, authenticated;
grant execute on function public.get_report_prewarm_candidates(timestamptz, integer)
  to service_role;
