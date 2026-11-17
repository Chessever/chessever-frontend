-- Starred smart events: a story worth tapping, up to twice a day (Trello #1411).
--
-- Until now a starred smart event sent one push a day, in the reader's evening,
-- whose title was a count ("28 GM-level games played today"). This keeps that
-- evening recap and gives the reader two better reasons to tap, on the rules
-- the Prep star already proved (20261017120000): never while the reader
-- sleeps, at most two smart event pushes a local day, at least four hours
-- apart, one smart event per push with the others counted.
--
--   * Live moment (smart_event_live), the first run in the reader's
--     12:00-18:59 that finds one of their smart events live: the strongest
--     board in play right now, its players' titles and the move it is on.
--   * Evening recap (smart_event_digest, as before), 19:00-22:59: the day's
--     story first. An upset (the winner rated 150+ below the loser) leads,
--     then the strongest game with the players' titles and how many moves it
--     took; the count moves to the body.
--
-- The four-hour cron is unchanged: its 00/04/08/12/16/20 UTC grid puts at
-- least one run in every reader's 12:00-18:59 and exactly one in their
-- 19:00-22:59, whatever their offset, so the two pushes are four hours apart
-- by construction. The guard below holds it if a run is late.
--
-- Deploy onesignal-dispatch (smart_event_live, story copy) BEFORE this
-- migration: an older dispatcher skips smart_event_live rows as unknown.
--
-- Additive: one new function; queue_smart_event_digests() is replaced with
-- the same signature; smart_event_digest payloads gain keys, none removed.
-- smart_event_digest_rows_since is left as it is.

begin;

-- smart_event_digest_rows_since with the story fields: per starred smart
-- event that caught games since each reader's p_since, its tallies, its
-- strongest game, its biggest upset and its strongest live board, each with
-- the players' titles and ratings. Matching is the same as
-- smart_event_digest_rows_since (mirror games excluded).
create or replace function public.smart_event_stories_since(
  p_window_end timestamptz,
  p_user_ids uuid[],
  p_since timestamptz[]
)
returns table (
  user_id uuid,
  smart_event_id text,
  smart_event_name text,
  label text,
  min_elo integer,
  max_elo integer,
  formats text[],
  eco_code text,
  games integer,
  live_games integer,
  white_wins integer,
  black_wins integer,
  draws integer,
  top_game_id text,
  top_white text,
  top_black text,
  top_white_title text,
  top_black_title text,
  top_status text,
  top_average integer,
  top_moves integer,
  top_opening text,
  top_event text,
  upset_game_id text,
  upset_winner text,
  upset_winner_title text,
  upset_winner_rating integer,
  upset_loser text,
  upset_loser_title text,
  upset_loser_rating integer,
  upset_moves integer,
  live_game_id text,
  live_white text,
  live_black text,
  live_white_title text,
  live_black_title text,
  live_average integer,
  live_move integer,
  live_opening text
)
language sql stable
set search_path = ''
as $$
  with readers as (
    -- A day is at most 25 hours (a DST change), never more.
    select r.user_id,
           greatest(r.since, p_window_end - interval '25 hours') as since
      from unnest(p_user_ids, p_since) as r(user_id, since)
     where r.user_id is not null and r.since is not null and r.since < p_window_end
  ),
  stars as (
    select
      f.user_id,
      rd.since,
      f.event_id,
      f.event_name,
      f.metadata,
      coalesce(case when f.metadata->>'minElo' ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$'
        then round((f.metadata->>'minElo')::numeric)::integer end, 0) as min_elo,
      coalesce(case when f.metadata->>'maxElo' ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$'
        then round((f.metadata->>'maxElo')::numeric)::integer end, 3200) as max_elo,
      case
        when jsonb_typeof(f.metadata->'formatsAndStates') = 'array' then array(
          select distinct lower(btrim(token))
          from jsonb_array_elements_text(f.metadata->'formatsAndStates') token
          where btrim(token) <> '')
        -- Saves older than the field: the app reads them off the label.
        else array(
          select distinct case word when 'classical' then 'standard' else word end
          from regexp_split_to_table(lower(coalesce(
            nullif(btrim(f.metadata->>'tierLabel'), ''), f.event_name, '')), '\s+') word
          where word in ('live', 'completed', 'rapid', 'blitz', 'classical'))
      end as formats,
      nullif(btrim(coalesce(f.metadata->>'ecoCode', f.metadata->>'eco', '')), '') as eco_code
    from public.user_favorite_events f
    join readers rd on rd.user_id = f.user_id
    where f.event_id like 'smart\_event:%'
  ),
  criteria as (
    select
      s.*,
      -- smartEventFetchScopeFor: the band's floor and ceiling only count when
      -- the band is narrower than the full 0-3200 scale.
      case when (s.min_elo > 0 or s.max_elo < 3200) and s.min_elo > 0
        then s.min_elo end as min_bound,
      case when (s.min_elo > 0 or s.max_elo < 3200) and s.max_elo < 3200
        then s.max_elo end as max_bound,
      'live' = any(s.formats) and not 'completed' = any(s.formats) as live_only,
      'completed' = any(s.formats) and not 'live' = any(s.formats) as completed_only,
      (select case when count(distinct bucket) between 1 and 2
          then array_agg(value) end
        from (
          select bucket, value
          from unnest(s.formats) token
          cross join lateral (values
            (case when token in ('standard', 'classical') then 'classical'
                  when token = 'rapid' then 'rapid'
                  when token in ('blitz', 'bullet') then 'blitz' end)
          ) b(bucket)
          cross join lateral unnest(case b.bucket
            when 'classical' then array['standard', 'classical']
            when 'rapid' then array['rapid']
            when 'blitz' then array['blitz', 'bullet'] end) value
          where b.bucket is not null
        ) chosen) as time_controls,
      public.smart_event_eco_codes(s.eco_code) as eco_codes
    from stars s
  ),
  window_games as (
    select
      g.id,
      g.status,
      g.eco,
      g.opening_name,
      g.player_white,
      g.player_black,
      -- players[0] is White and players[1] Black on every relay row.
      nullif(btrim(g.players->0->>'title'), '') as white_title,
      nullif(btrim(g.players->1->>'title'), '') as black_title,
      case when g.players->0->>'rating' ~ '^[0-9]{3,4}$'
        then (g.players->0->>'rating')::integer end as white_rating,
      case when g.players->1->>'rating' ~ '^[0-9]{3,4}$'
        then (g.players->1->>'rating')::integer end as black_rating,
      -- Full moves: ply 41 is White's 21st move.
      case when g.live_ply_count > 0 then (g.live_ply_count + 1) / 2 end as moves,
      g.player_max_rating,
      g.last_move_time,
      public.smart_event_average_rating(g.players) as average,
      lower(btrim(b.time_control)) as time_control,
      b.name as event_name,
      g.status in ('*', 'ongoing', 'live')
        and g.last_move is not null
        and g.last_move_time >= now() - interval '8 hours'
        and g.last_clock_white > 0 and g.last_clock_black > 0 as is_live,
      g.status is not null
        and g.status not in ('*', 'ongoing', 'live') as is_finished
    from public.games g
    left join public.tours t on t.id = g.tour_id
    left join public.group_broadcasts b on b.id = t.group_broadcast_id
    where g.last_move_time > (select min(since) from readers)
      and g.last_move_time <= p_window_end
      and not g.is_mirror
      and g.game_day is not null
      and g.game_day <= (now() at time zone 'UTC')::date
      and exists (
        select 1 from public.rounds r
        where r.id = g.round_id and (r.starts_at is null or r.starts_at <= now()))
  ),
  matched as (
    select c.user_id, c.event_id, w.*
    from criteria c
    join window_games w
      on w.last_move_time > c.since
      and (c.min_bound is null
          or (w.player_max_rating >= c.min_bound and w.average >= c.min_bound))
      and (c.max_bound is null or (w.average > 0 and w.average <= c.max_bound))
      and (c.time_controls is null or w.time_control = any(c.time_controls))
      and (c.eco_codes is null or w.eco = any(c.eco_codes))
      and (not c.live_only or w.is_live)
      and (not c.completed_only or w.is_finished)
  ),
  tallies as (
    select
      m.user_id,
      m.event_id,
      count(*)::integer as games,
      count(*) filter (where m.is_live)::integer as live_games,
      count(*) filter (where m.status = '1-0')::integer as white_wins,
      count(*) filter (where m.status = '0-1')::integer as black_wins,
      count(*) filter (where m.status in ('1/2-1/2', '½-½'))::integer as draws
    from matched m
    group by m.user_id, m.event_id
  ),
  tops as (
    select distinct on (m.user_id, m.event_id) m.*
    from matched m
    order by m.user_id, m.event_id, m.average desc nulls last,
      m.last_move_time desc nulls last, m.id
  ),
  -- Decisive games the lower-rated player won, by 150 points or more: the
  -- widest gap is the day's upset.
  upsets as (
    select distinct on (u.user_id, u.event_id) u.*
    from (
      select m.user_id, m.event_id, m.id, m.moves, m.last_move_time,
        case when m.status = '1-0' then m.player_white else m.player_black end as winner,
        case when m.status = '1-0' then m.white_title else m.black_title end as winner_title,
        case when m.status = '1-0' then m.white_rating else m.black_rating end as winner_rating,
        case when m.status = '1-0' then m.player_black else m.player_white end as loser,
        case when m.status = '1-0' then m.black_title else m.white_title end as loser_title,
        case when m.status = '1-0' then m.black_rating else m.white_rating end as loser_rating
      from matched m
      where m.status in ('1-0', '0-1')
    ) u
    where u.winner_rating > 0 and u.loser_rating > 0
      and u.loser_rating - u.winner_rating >= 150
    order by u.user_id, u.event_id, u.loser_rating - u.winner_rating desc,
      u.last_move_time desc, u.id
  ),
  lives as (
    select distinct on (m.user_id, m.event_id) m.*
    from matched m
    where m.is_live
    order by m.user_id, m.event_id, m.average desc nulls last,
      m.moves desc nulls last, m.id
  )
  select
    c.user_id,
    c.event_id,
    c.event_name,
    nullif(btrim(c.metadata->>'tierLabel'), ''),
    c.min_elo,
    c.max_elo,
    c.formats,
    c.eco_code,
    t.games,
    t.live_games,
    t.white_wins,
    t.black_wins,
    t.draws,
    top.id,
    top.player_white,
    top.player_black,
    top.white_title,
    top.black_title,
    top.status,
    top.average,
    top.moves,
    top.opening_name,
    top.event_name,
    up.id,
    up.winner,
    up.winner_title,
    up.winner_rating,
    up.loser,
    up.loser_title,
    up.loser_rating,
    up.moves,
    lv.id,
    lv.player_white,
    lv.player_black,
    lv.white_title,
    lv.black_title,
    lv.average,
    lv.moves,
    lv.opening_name
  from criteria c
  join tallies t on t.user_id = c.user_id and t.event_id = c.event_id
  join tops top on top.user_id = c.user_id and top.event_id = c.event_id
  left join upsets up on up.user_id = c.user_id and up.event_id = c.event_id
  left join lives lv on lv.user_id = c.user_id and lv.event_id = c.event_id;
$$;

-- Reads every user's stars: service only.
revoke all on function public.smart_event_stories_since(timestamptz, uuid[], timestamptz[])
  from public, anon, authenticated;
grant execute on function public.smart_event_stories_since(timestamptz, uuid[], timestamptz[])
  to service_role;

create or replace function public.queue_smart_event_digests()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  run_at timestamptz := now();
  queued integer;
  v_users uuid[];
  v_since timestamptz[];
  v_days date[];
  v_zones text[];
  v_hours integer[];
begin
  -- Starrers OneSignal was not asked about for a day: onesignal-dispatch
  -- looks them up (user_timezone_refresh). The device's own zone is read
  -- first; this keeps the fallback fresh.
  insert into public.notification_outbox (event_type, payload, dedupe_key)
  select
    'user_timezone_refresh',
    jsonb_build_object('user_ids', jsonb_agg(stale.user_id)),
    'user_timezone_refresh:' || extract(epoch from date_trunc('hour', run_at))::bigint ||
      ':' || stale.batch
  from (
    select s.user_id, (row_number() over (order by s.user_id) - 1) / 100 as batch
    from (
      select distinct f.user_id
      from public.user_favorite_events f
      where f.event_id like 'smart\_event:%' and f.user_id is not null
    ) s
    left join public.user_timezones tz on tz.user_id = s.user_id
    where tz.user_id is null or tz.checked_at < run_at - interval '1 day'
  ) stale
  group by stale.batch
  on conflict (dedupe_key) do nothing;

  -- Whose afternoon or evening it is, and when their day began.
  with starrers as (
    select distinct f.user_id
    from public.user_favorite_events f
    where f.event_id like 'smart\_event:%' and f.user_id is not null
  ),
  zones as (
    select z.user_id, z.timezone
    from public.reader_timezones(array(select s.user_id from starrers s)) z
  ),
  -- The offset a reader's Prep stars carry, for a reader no zone is known
  -- for: no DST, but the right evening.
  offsets as (
    select w.user_id, max(w.utc_offset_minutes)::integer as minutes
    from public.prep_profile_watches w
    where w.user_id in (select s.user_id from starrers s)
    group by w.user_id
  ),
  -- Readers whose app opens the push where it points (the smart event's
  -- Games tab): any device on build 3676 (37.0.4) or later. Older builds
  -- would open the strongest game instead.
  ready as (
    select distinct d.user_id
    from admin_portal.devices d
    where d.user_id in (select s.user_id from starrers s)
      and case when split_part(d.app_version, '+', 2) ~ '^[0-9]{1,9}$'
        then split_part(d.app_version, '+', 2)::integer end >= 3676
  ),
  clocks as (
    select r.user_id,
           z.timezone,
           o.minutes,
           case
             when z.timezone is not null then run_at at time zone z.timezone
             else (run_at at time zone 'utc') + make_interval(mins => o.minutes)
           end as local_now
    from ready r
    left join zones z on z.user_id = r.user_id
    left join offsets o on o.user_id = r.user_id
    where z.timezone is not null or o.minutes is not null
  )
  select array_agg(c.user_id),
         array_agg(
           case
             when c.timezone is not null
               then date_trunc('day', c.local_now) at time zone c.timezone
             else (date_trunc('day', c.local_now) - make_interval(mins => c.minutes))
               at time zone 'utc'
           end),
         array_agg(c.local_now::date),
         array_agg(c.timezone),
         array_agg(extract(hour from c.local_now)::integer)
    into v_users, v_since, v_days, v_zones, v_hours
  from clocks c
  where extract(hour from c.local_now) between 12 and 22;

  if v_users is null then
    return 0;
  end if;

  with readers as (
    select r.user_id, r.since, r.local_day, r.timezone, r.local_hour
    from unnest(v_users, v_since, v_days, v_zones, v_hours)
      as r(user_id, since, local_day, timezone, local_hour)
  ),
  -- Smart event pushes already queued for these readers in the last day.
  earlier as (
    select (o.payload->>'user_id')::uuid as user_id,
           o.payload->>'local_day' as local_day,
           o.created_at
    from public.notification_outbox o
    where o.event_type in ('smart_event_digest', 'smart_event_live')
      and o.created_at > run_at - interval '26 hours'
      and o.payload->>'user_id' in (select r.user_id::text from readers r)
  ),
  run as (
    select d.*, rd.since, rd.local_day, rd.local_hour, rd.timezone,
      -- At most two smart event pushes a local day, four hours apart.
      (select count(*) from earlier e
        where e.user_id = d.user_id and e.local_day = rd.local_day::text) as sent_today,
      exists (select 1 from earlier e
        where e.user_id = d.user_id
          and e.created_at > run_at - interval '3 hours 50 minutes') as sent_recently
    from public.smart_event_stories_since(run_at, v_users, v_since) d
    join readers rd on rd.user_id = d.user_id
    where d.games > 0
  ),
  -- Afternoon: the strongest board in play on one of the reader's smart
  -- events, once a day.
  live_picks as (
    select s.*,
      row_number() over (partition by s.user_id
        order by s.live_average desc nulls last, s.live_games desc,
          s.smart_event_id) as pick,
      count(*) over (partition by s.user_id) as caught
    from run s
    where s.local_hour between 12 and 18
      and s.live_game_id is not null
      and s.sent_today = 0
      and not s.sent_recently
  ),
  -- Evening: the day's story, once a day. An upset outranks a bigger count.
  evening_picks as (
    select s.*,
      row_number() over (partition by s.user_id
        order by (s.upset_game_id is not null) desc, s.games desc,
          s.top_average desc nulls last, s.smart_event_id) as pick,
      count(*) over (partition by s.user_id) as caught
    from run s
    where s.local_hour between 19 and 22
      and s.sent_today < 2
      and not s.sent_recently
  )
  insert into public.notification_outbox (event_type, payload, dedupe_key)
  select
    'smart_event_live',
    jsonb_build_object(
      'user_id', p.user_id,
      'smart_event_id', p.smart_event_id,
      'smart_event_name', p.smart_event_name,
      'label', p.label,
      'min_elo', p.min_elo,
      'max_elo', p.max_elo,
      'formats', to_jsonb(p.formats),
      'eco_code', p.eco_code,
      'games', p.games,
      'live_games', p.live_games,
      'live_game_id', p.live_game_id,
      'live_white', p.live_white,
      'live_black', p.live_black,
      'live_white_title', p.live_white_title,
      'live_black_title', p.live_black_title,
      'live_average', p.live_average,
      'live_move', p.live_move,
      'live_opening', p.live_opening,
      'other_smart_events', p.caught - 1,
      'timezone', p.timezone,
      'local_day', p.local_day,
      'since', p.since,
      'window_end', run_at),
    'smart_event_live:' || p.user_id || ':' || p.local_day
  from live_picks p
  where p.pick = 1
  union all
  select
    'smart_event_digest',
    jsonb_build_object(
      'user_id', p.user_id,
      'smart_event_id', p.smart_event_id,
      'smart_event_name', p.smart_event_name,
      'label', p.label,
      'min_elo', p.min_elo,
      'max_elo', p.max_elo,
      'formats', to_jsonb(p.formats),
      'eco_code', p.eco_code,
      'games', p.games,
      'live_games', p.live_games,
      'white_wins', p.white_wins,
      'black_wins', p.black_wins,
      'draws', p.draws,
      'top_game_id', p.top_game_id,
      'top_white', p.top_white,
      'top_black', p.top_black,
      'top_white_title', p.top_white_title,
      'top_black_title', p.top_black_title,
      'top_status', p.top_status,
      'top_average', p.top_average,
      'top_moves', p.top_moves,
      'top_opening', p.top_opening,
      'top_event', p.top_event,
      'upset_game_id', p.upset_game_id,
      'upset_winner', p.upset_winner,
      'upset_winner_title', p.upset_winner_title,
      'upset_winner_rating', p.upset_winner_rating,
      'upset_loser', p.upset_loser,
      'upset_loser_title', p.upset_loser_title,
      'upset_loser_rating', p.upset_loser_rating,
      'upset_moves', p.upset_moves,
      'other_smart_events', p.caught - 1,
      'timezone', p.timezone,
      'local_day', p.local_day,
      -- The counts run from the reader's local midnight to window_end.
      'since', p.since,
      'window_end', run_at),
    'smart_event_digest:' || p.user_id || ':' || p.local_day
  from evening_picks p
  where p.pick = 1
  on conflict (dedupe_key) do nothing;
  get diagnostics queued = row_count;

  return queued;
end;
$$;

revoke all on function public.queue_smart_event_digests()
  from public, anon, authenticated;
grant execute on function public.queue_smart_event_digests() to service_role;

commit;
