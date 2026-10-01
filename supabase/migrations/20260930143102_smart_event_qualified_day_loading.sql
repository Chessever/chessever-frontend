-- Resolve the newest ACTUALLY qualifying day, rather than walking candidate
-- days over HTTP and declaring a sparse smart event empty after thirteen days.
-- Invoker functions preserve the games/tours/rounds/broadcast RLS boundary.
create or replace function public.smart_event_average_rating(players jsonb)
returns integer
language sql immutable parallel safe security invoker
set search_path = ''
as $$
  select case when jsonb_typeof(players->0->'rating') = 'number'
                   and jsonb_typeof(players->1->'rating') = 'number'
    then case when trunc((players->0->>'rating')::numeric) > 0
                    and trunc((players->1->>'rating')::numeric) > 0
      then floor((trunc((players->0->>'rating')::numeric)
                + trunc((players->1->>'rating')::numeric)) / 2)::integer
      else 0 end
    else 0 end;
$$;

create index if not exists idx_games_eco_game_day_last_move
on public.games (
  eco, game_day desc nulls last, last_move_time desc nulls last,
  player_max_rating desc nulls last, id
)
where eco is not null and game_day is not null;

-- Ordered day lookup restricted to rated boards. The stored expression lets
-- all four level floors reject weak boards in the index, before reading JSON
-- or joining event metadata. Build CONCURRENTLY first on a running database;
-- the transactional migration then sees the existing index and skips it.
create index if not exists idx_games_smart_rating_day
on public.games (
  game_day desc nulls last, public.smart_event_average_rating(players), id
)
where game_day is not null and public.smart_event_average_rating(players) >= 2200;

create or replace function public.get_current_smart_event_day(
  p_before date default null,
  p_min_rating integer default null,
  p_max_rating integer default null,
  p_eco_codes text[] default null,
  p_time_controls text[] default null,
  p_live_only boolean default false,
  p_completed_only boolean default false,
  p_search text default null,
  p_results text[] default null,
  p_min_year integer default null,
  p_max_year integer default null,
  p_online boolean default null
)
returns date
language plpgsql stable security invoker
set search_path = ''
as $$
declare
  predicates text := 'g.game_day is not null
    and g.game_day <= (now() at time zone ''UTC'')::date
    and exists (select 1 from public.rounds r where r.id = g.round_id
      and (r.starts_at is null or r.starts_at <= now()))';
  query_text text;
  result_day date;
begin
  -- Build only the selected predicates. EXECUTE prevents a generic prepared
  -- plan for All Games from being reused for a rare ECO+rating+format query.
  -- Every user value is bound through USING, never concatenated into SQL.
  if p_before is not null then
    predicates := predicates || ' and g.game_day < $1';
  end if;
  if p_min_rating is not null then
    predicates := predicates || ' and g.player_max_rating >= $2
      and public.smart_event_average_rating(g.players) >= $2';
  end if;
  if p_max_rating is not null then
    predicates := predicates || ' and public.smart_event_average_rating(g.players) > 0
      and public.smart_event_average_rating(g.players) <= $3';
  end if;
  if coalesce(cardinality(p_time_controls), 0) > 0 then
    predicates := predicates || ' and exists (
      select 1 from public.tours t
      join public.group_broadcasts b on b.id = t.group_broadcast_id
      where t.id = g.tour_id and lower(btrim(b.time_control)) = any($5))';
  end if;
  if p_live_only and not p_completed_only then
    predicates := predicates || ' and g.status in (''*'', ''ongoing'', ''live'')
      and g.last_move is not null and g.last_move_time >= now() - interval ''8 hours''
      and g.last_clock_white > 0 and g.last_clock_black > 0';
  elsif p_completed_only and not p_live_only then
    predicates := predicates || ' and g.status is not null
      and g.status not in (''*'', ''ongoing'', ''live'')';
  end if;
  if nullif(btrim(p_search), '') is not null then
    predicates := predicates || ' and (
      g.name ilike ''%'' || $8 || ''%'' or g.player_white ilike ''%'' || $8 || ''%''
      or g.player_black ilike ''%'' || $8 || ''%'' or g.eco ilike ''%'' || $8 || ''%''
      or g.opening_name ilike ''%'' || $8 || ''%'')';
  end if;
  if p_results is not null then
    predicates := predicates || ' and g.status = any($9)';
  end if;
  if p_min_year is not null then
    predicates := predicates || ' and g.game_day >= make_date($10, 1, 1)';
  end if;
  if p_max_year is not null then
    predicates := predicates || ' and g.game_day < make_date($11 + 1, 1, 1)';
  end if;
  if p_online is true then
    predicates := predicates || ' and g.lichess_id is not null';
  elsif p_online is false then
    predicates := predicates || ' and g.lichess_id is null';
  end if;

  if coalesce(cardinality(p_eco_codes), 0) > 1 then
    -- One ordered LIMIT per exact ECO lets an irregular family use the same
    -- index as a single code, without sorting the entire family's history.
    query_text := 'select max(hit.game_day) from unnest($4) code(eco)
      cross join lateral (
        select g.game_day from public.games g
        where g.eco = code.eco and ' || predicates ||
        ' order by g.game_day desc nulls last limit 1
      ) hit';
  else
    if cardinality(p_eco_codes) = 1 then
      predicates := predicates || ' and g.eco = ($4)[1]';
    end if;
    query_text := 'select g.game_day from public.games g where ' || predicates ||
      ' order by g.game_day desc nulls last limit 1';
  end if;
  execute query_text into result_day using
    p_before, p_min_rating, p_max_rating, p_eco_codes, p_time_controls,
    p_live_only, p_completed_only, btrim(p_search), p_results,
    p_min_year, p_max_year, p_online;
  return result_day;
end;
$$;

-- This pure argument-only utility reads no database data. Existing writer
-- roles can continue maintaining the expression index without new grants.
grant execute on function public.smart_event_average_rating(jsonb)
  to public;
revoke all on function public.get_current_smart_event_day(
  date, integer, integer, text[], text[], boolean, boolean, text,
  text[], integer, integer, boolean
) from public;
grant execute on function public.get_current_smart_event_day(
  date, integer, integer, text[], text[], boolean, boolean, text,
  text[], integer, integer, boolean
) to anon, authenticated, service_role;

notify pgrst, 'reload schema';
