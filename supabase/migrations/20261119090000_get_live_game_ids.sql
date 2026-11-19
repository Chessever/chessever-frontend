-- "See N live" names the games in play right now, by one rule the label and
-- Live first share (AGENTS.md: "a game with a move that is not finished"):
--
-- * its round is in settings.live_round_ids and passes the 2-hour freshness
--   of get_strict_live_group_broadcast_ids (the round's latest move, else
--   its start, within 7200 seconds);
-- * status is '*', 'ongoing', 'live' or null;
-- * it has a move (a non-empty last_move, or a last_move_time);
-- * it is not a mirror game.
--
-- No calendar day is compared, so a 0-move shell, a game still in play past
-- UTC midnight and a '*' left over from an earlier day are all judged right
-- whatever the reader's time zone.
--
-- Scopes, any combination (null = not narrowed):
-- * p_tour_ids: an event's tours (selected, Combined categories, stages);
-- * p_fide_ids: the reader's favorite players (Favorites);
-- * p_country_code: a federation (Countrymen).
-- The list filters are the predicates of filter_games_for_favorites_on_date
-- and filter_games_for_country_on_date, copied verbatim, so the count is
-- exactly what those lists can show. The colour predicate follows the scope
-- (FIDE ids for Favorites, federation for Countrymen). Countrymen passes its
-- rating floor (min_elo, raised to the filter's minimum) as p_min_rating.
-- p_eco_codes is the exact-code form the app's list queries use
-- (GameEcoFilter.exactEcoCodes); p_eco is the RPCs' prefix form.
--
-- Additive: a new function, nothing else changes. Builds that never call it
-- are unaffected; builds that call it before it exists read an unknown
-- count ("See live").
create or replace function public.get_live_game_ids(
  p_tour_ids text[] default null,
  p_fide_ids bigint[] default null,
  p_country_code text default null,
  p_status text default null,
  p_result text default null,
  p_time_control text default null,
  p_min_year integer default null,
  p_max_year integer default null,
  p_min_rating integer default null,
  p_max_rating integer default null,
  p_eco text default null,
  p_eco_codes text[] default null,
  p_color text default null
)
returns table (id text, tour_id text, round_id text)
language sql
stable
security invoker
set search_path = ''
as $$
  with live_rounds as materialized (
    select
      r.id,
      r.starts_at
    from public.settings s
    cross join lateral unnest(coalesce(s.live_round_ids, '{}'::text[]))
      as c(round_id)
    join public.rounds r on r.id = c.round_id
    where s.id = 1
      and (p_tour_ids is null or r.tour_id = any(p_tour_ids))
  ),
  fresh_rounds as materialized (
    select lr.id
    from live_rounds lr
    left join lateral (
      select max(g.last_move_time) as last_move_time
      from public.games g
      where g.round_id = lr.id
        and g.last_move_time is not null
    ) activity on true
    where now() <= coalesce(activity.last_move_time, lr.starts_at)
      + pg_catalog.make_interval(secs => 7200)
  )
  select
    g.id,
    g.tour_id,
    g.round_id
  from fresh_rounds f
  join public.games g on g.round_id = f.id
  where not g.is_mirror
    and lower(btrim(coalesce(g.status, '*'))) in ('*', 'ongoing', 'live')
    and (nullif(btrim(g.last_move), '') is not null
         or g.last_move_time is not null)
    and (p_tour_ids is null or g.tour_id = any(p_tour_ids))
    and (p_fide_ids is null or g.player_fide_ids && p_fide_ids)
    and (p_country_code is null
         or g.player_feds @> array[upper(p_country_code)])
    -- From filter_games_for_favorites_on_date / _country_on_date, verbatim.
    and (p_status is null
         or (p_status = 'live'      and (g.status is null or g.status = '*'))
         or (p_status = 'completed' and g.status is not null and g.status <> '*'))
    and (p_result is null
         or (p_result = '1-0' and g.status = '1-0')
         or (p_result = '0-1' and g.status = '0-1')
         or (p_result in ('1/2','1/2-1/2','draw')
             and g.status in ('1/2','1/2-1/2','½-½')))
    and (p_time_control is null
         or g.tour_slug in (
              select t.slug
              from public.tours t
              join public.group_broadcasts gb on gb.id = t.group_broadcast_id
              where gb.time_control = p_time_control))
    and (p_min_year   is null or extract(year from coalesce(g.game_day, g.last_move_time::date, g.date_start)) >= p_min_year)
    and (p_max_year   is null or extract(year from coalesce(g.game_day, g.last_move_time::date, g.date_start)) <= p_max_year)
    and (p_min_rating is null or g.player_max_rating >= p_min_rating)
    and (p_max_rating is null or g.player_max_rating <= p_max_rating)
    and (p_eco is null or g.eco ilike (p_eco || '%'))
    and (p_eco_codes is null or g.eco = any(p_eco_codes))
    -- Colour, by the scope: the favorite on that side (Favorites), or the
    -- federation on that side (Countrymen). With neither, it narrows nothing.
    and (p_color is null
         or p_fide_ids is null
         or (p_color = 'white'
             and (nullif(g.players->0->>'fideId',''))::bigint = any(p_fide_ids))
         or (p_color = 'black'
             and (nullif(g.players->1->>'fideId',''))::bigint = any(p_fide_ids)))
    and (p_color is null
         or p_country_code is null
         or (p_color = 'white' and upper(g.players->0->>'fed') = upper(p_country_code))
         or (p_color = 'black' and upper(g.players->1->>'fed') = upper(p_country_code)))
  order by g.round_id, g.board_nr nulls last, g.id;
$$;

comment on function public.get_live_game_ids(
  text[], bigint[], text, text, text, text, integer, integer, integer,
  integer, text, text[], text
)
is 'Ids of the games in play (live round, fresh, has a move, not finished, '
   'not a mirror) for event tours, favorite FIDE ids or a federation, under '
   'the Favorites/Countrymen list filters. Drives "See N live".';

revoke all on function public.get_live_game_ids(
  text[], bigint[], text, text, text, text, integer, integer, integer,
  integer, text, text[], text
)
from public, anon;

-- Guests are anonymous Supabase sessions, so authenticated covers them, as
-- for get_strict_live_group_broadcast_ids.
grant execute on function public.get_live_game_ids(
  text[], bigint[], text, text, text, text, integer, integer, integer,
  integer, text, text[], text
)
to authenticated;
