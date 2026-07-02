-- For You feed: never surface idle placeholder boards.
--
-- Previously only fallback rounds (source_priority = 1) required a game to
-- have actually started; live rounds (source_priority = 0) returned every row,
-- so mid-broadcast placeholder games (start FEN, no moves, "?" player names)
-- leaked onto For You cards as grey idle boards.
--
-- This revision requires every returned game — live or fallback — to have
-- both a started position AND two resolved player names. A live round whose
-- games are all placeholders no longer claims the category: the feed falls
-- back to the latest round that has real games instead.

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
  ),
  live_round_ids as (
    select distinct live_round_id.round_id
    from public.settings s
    cross join lateral unnest(
      coalesce(s.live_round_ids, '{}'::text[])
    ) as live_round_id(round_id)
    where s.id = 1
      and live_round_id.round_id is not null
      and live_round_id.round_id <> ''
  ),
  event_categories as (
    select
      re.event_id,
      t.avg_elo as category_avg_elo
    from requested_events re
    join public.tours t on t.group_broadcast_id = re.event_id
    where exists (
      select 1
      from public.rounds r
      where r.tour_id = t.id
        and exists (
          select 1
          from public.games g
          where g.round_id = r.id
            and g.tour_id = t.id
        )
    )
    group by re.event_id, t.avg_elo
  ),
  live_round_sources as (
    select distinct on (ec.event_id, ec.category_avg_elo)
      ec.event_id,
      0 as source_priority,
      ec.category_avg_elo,
      r.id as source_round_id,
      nullif(r.slug, '') as source_round_slug,
      nullif(r.name, '') as source_round_name,
      coalesce(r.starts_at, r.created_at) as source_round_time
    from event_categories ec
    join public.tours t
      on t.group_broadcast_id = ec.event_id
     and t.avg_elo is not distinct from ec.category_avg_elo
    join public.rounds r on r.tour_id = t.id
    join live_round_ids lr on lr.round_id = r.id
    where exists (
      select 1
      from public.games g
      where g.round_id = r.id
        and g.tour_id = t.id
        and (
          g.fen is distinct from 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
          or nullif(g.last_move, '') is not null
          or g.last_move_time is not null
          or coalesce(g.pgn, '') ~ '(?m)^1[.]'
        )
        and jsonb_array_length(coalesce(g.players, '[]'::jsonb)) >= 2
        and lower(btrim(coalesce(g.players->0->>'name', ''))) not in ('', '?', '??', 'tbd', 'tba', 'unknown')
        and lower(btrim(coalesce(g.players->1->>'name', ''))) not in ('', '?', '??', 'tbd', 'tba', 'unknown')
    )
    order by
      ec.event_id,
      ec.category_avg_elo desc nulls last,
      coalesce(r.starts_at, r.created_at) desc nulls last,
      r.created_at desc,
      r.id desc
  ),
  fallback_round_sources as (
    select
      ec.event_id,
      1 as source_priority,
      ec.category_avg_elo,
      latest_round.round_id as source_round_id,
      latest_round.round_slug as source_round_slug,
      latest_round.round_name as source_round_name,
      latest_round.round_time as source_round_time
    from event_categories ec
    cross join lateral (
      select
        r.id as round_id,
        nullif(r.slug, '') as round_slug,
        nullif(r.name, '') as round_name,
        coalesce(r.starts_at, r.created_at) as round_time
      from public.tours t
      join public.rounds r on r.tour_id = t.id
      where t.group_broadcast_id = ec.event_id
        and t.avg_elo is not distinct from ec.category_avg_elo
        and exists (
          select 1
          from public.games g
          where g.round_id = r.id
            and g.tour_id = t.id
            and (
              g.fen is distinct from 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
              or nullif(g.last_move, '') is not null
              or g.last_move_time is not null
              or coalesce(g.pgn, '') ~ '(?m)^1[.]'
            )
            and jsonb_array_length(coalesce(g.players, '[]'::jsonb)) >= 2
            and lower(btrim(coalesce(g.players->0->>'name', ''))) not in ('', '?', '??', 'tbd', 'tba', 'unknown')
            and lower(btrim(coalesce(g.players->1->>'name', ''))) not in ('', '?', '??', 'tbd', 'tba', 'unknown')
        )
      order by
        r.starts_at desc nulls last,
        r.created_at desc,
        r.id desc
      limit 1
    ) latest_round
    where not exists (
      select 1
      from live_round_sources lrs
      where lrs.event_id = ec.event_id
        and lrs.category_avg_elo is not distinct from ec.category_avg_elo
    )
  ),
  round_sources as (
    select * from live_round_sources
    union all
    select * from fallback_round_sources
  ),
  candidate_games as (
    select
      rs.event_id,
      rs.source_priority,
      rs.category_avg_elo,
      rs.source_round_id,
      rs.source_round_time,
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
      g.player_max_rating,
      row_number() over (
        partition by
          rs.event_id,
          rs.source_priority,
          rs.category_avg_elo,
          rs.source_round_id
        order by
          g.board_nr asc nulls last,
          g.player_max_rating desc nulls last,
          g.date_start desc nulls last,
          g.last_move_time desc nulls last,
          g.id asc
      ) as board_rank
    from round_sources rs
    join public.tours t
      on t.group_broadcast_id = rs.event_id
     and t.avg_elo is not distinct from rs.category_avg_elo
    join public.rounds r on r.tour_id = t.id
    join public.games g on g.round_id = r.id and g.tour_id = t.id
    join public.group_broadcasts gb on gb.id = t.group_broadcast_id
    where (
        g.fen is distinct from 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
        or nullif(g.last_move, '') is not null
        or g.last_move_time is not null
        or coalesce(g.pgn, '') ~ '(?m)^1[.]'
      )
      and jsonb_array_length(coalesce(g.players, '[]'::jsonb)) >= 2
      and lower(btrim(coalesce(g.players->0->>'name', ''))) not in ('', '?', '??', 'tbd', 'tba', 'unknown')
      and lower(btrim(coalesce(g.players->1->>'name', ''))) not in ('', '?', '??', 'tbd', 'tba', 'unknown')
      and (
        (
          rs.source_round_slug is not null
          and nullif(r.slug, '') = rs.source_round_slug
          and coalesce(r.starts_at, r.created_at)
            between rs.source_round_time - interval '30 minutes'
                and rs.source_round_time + interval '30 minutes'
        )
        or (
          rs.source_round_slug is null
          and rs.source_round_name is not null
          and nullif(r.name, '') = rs.source_round_name
          and coalesce(r.starts_at, r.created_at)
            between rs.source_round_time - interval '30 minutes'
                and rs.source_round_time + interval '30 minutes'
        )
        or (
          rs.source_round_slug is null
          and rs.source_round_name is null
          and r.id = rs.source_round_id
        )
      )
  ),
  ranked_games as (
    select
      cg.*,
      row_number() over (
        partition by cg.event_id
        order by
          cg.source_priority asc,
          cg.category_avg_elo desc nulls last,
          cg.source_round_time desc nulls last,
          cg.board_rank asc,
          cg.player_max_rating desc nulls last,
          cg.id asc
      ) as event_game_rank
    from candidate_games cg
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
  from ranked_games top_games
  cross join params p
  where top_games.event_game_rank <= p.board_count
  order by
    top_games.event_id,
    top_games.event_game_rank;
$$;

revoke all on function public.get_for_you_top_games(text[], integer) from public;
grant execute on function public.get_for_you_top_games(text[], integer) to authenticated;
