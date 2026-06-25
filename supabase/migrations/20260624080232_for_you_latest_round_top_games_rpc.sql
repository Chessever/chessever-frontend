create or replace function public.get_for_you_top_games(
  p_event_ids text[],
  p_boards_per_event integer default 4
)
returns table (
  event_id text,
  id text,
  round_id text,
  round_slug text,
  tour_id text,
  tour_slug text,
  name text,
  fen text,
  pgn text,
  players jsonb,
  last_move text,
  think_time integer,
  status text,
  search text[],
  lichess_id text,
  player_white text,
  player_black text,
  date_start date,
  time_start time without time zone,
  board_nr smallint,
  last_move_time timestamptz,
  game_day date,
  last_clock_white real,
  last_clock_black real,
  eco text,
  opening_name text,
  time_control text,
  avg_elo smallint
)
language sql
stable
security invoker
set search_path = public
as $$
  with params as (
    select greatest(1, least(coalesce(p_boards_per_event, 4), 12)) as board_count
  ),
  requested_events as (
    select distinct event_id
    from unnest(coalesce(p_event_ids, '{}'::text[])) as event_id
    where event_id is not null and event_id <> ''
  )
  select
    top_games.event_id,
    top_games.id,
    top_games.round_id,
    top_games.round_slug,
    top_games.tour_id,
    top_games.tour_slug,
    top_games.name,
    top_games.fen,
    top_games.pgn,
    top_games.players,
    top_games.last_move,
    top_games.think_time,
    top_games.status,
    top_games.search,
    top_games.lichess_id,
    top_games.player_white,
    top_games.player_black,
    top_games.date_start,
    top_games.time_start,
    top_games.board_nr,
    top_games.last_move_time,
    top_games.game_day,
    top_games.last_clock_white,
    top_games.last_clock_black,
    top_games.eco,
    top_games.opening_name,
    top_games.time_control,
    top_games.avg_elo
  from requested_events re
  cross join params p
  cross join lateral (
    select r.id as round_id
    from public.tours t
    join public.rounds r on r.tour_id = t.id
    where t.group_broadcast_id = re.event_id
      and exists (
        select 1
        from public.games g
        where g.round_id = r.id
      )
    order by
      r.starts_at desc nulls last,
      r.created_at desc,
      r.id desc
    limit 1
  ) latest_round
  cross join lateral (
    select
      re.event_id,
      g.id,
      g.round_id,
      g.round_slug,
      g.tour_id,
      g.tour_slug,
      g.name,
      g.fen,
      g.pgn,
      g.players,
      g.last_move,
      g.think_time,
      g.status,
      g.search,
      g.lichess_id,
      g.player_white,
      g.player_black,
      g.date_start,
      g.time_start,
      g.board_nr,
      g.last_move_time,
      g.game_day,
      g.last_clock_white,
      g.last_clock_black,
      g.eco,
      g.opening_name,
      gb.time_control,
      t.avg_elo,
      g.player_max_rating
    from public.games g
    join public.tours t on t.id = g.tour_id
    join public.group_broadcasts gb on gb.id = t.group_broadcast_id
    where g.round_id = latest_round.round_id
      and t.group_broadcast_id = re.event_id
    order by
      g.board_nr asc nulls last,
      g.player_max_rating desc nulls last,
      g.date_start desc nulls last,
      g.last_move_time desc nulls last,
      g.id asc
    limit p.board_count
  ) top_games
  order by
    top_games.event_id,
    top_games.board_nr asc nulls last,
    top_games.player_max_rating desc nulls last,
    top_games.date_start desc nulls last,
    top_games.last_move_time desc nulls last,
    top_games.id asc;
$$;

revoke all on function public.get_for_you_top_games(text[], integer) from public;
grant execute on function public.get_for_you_top_games(text[], integer) to authenticated;
