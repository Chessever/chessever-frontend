-- Starred smart event and Prep pushes: no reader left out, and every number
-- in a push true for the reader who reads it.
--
-- Smart events
--   * "Today" is the reader's own day. The count ran over the 24 hours before
--     the evening run, so a push read at 20:00 counted games from 20:00 the
--     day before and called them today's. It now counts from midnight where
--     the reader lives (smart_event_digest_rows_since).
--   * A reader OneSignal has no timezone for got no push at all. The app now
--     sends its IANA zone with every device registration
--     (admin_portal.devices.timezone); reader_timezones() reads that first and
--     falls back to OneSignal's, then to the offset the reader's Prep stars
--     carry.
--   * A reader whose current-build device had not been seen in 60 days got
--     no push. The build gate stays (older builds open the wrong screen); the
--     60-day cutoff is gone.
--
-- Collections
--   * A star is keyed by the collection's slug (`collection:<slug>`), so a
--     renamed collection lost every star, and with them its pushes and its
--     place in My Space. gamebase now calls rename_collection_stars when a
--     slug changes.
--
-- Prep players
--   * A push about one player cleared every player's new games, so a second
--     player playing the same day never got a push of their own. Only the
--     announced player is cleared now.
--   * Each account remembers how many games the reader was told about today
--     (announced_day / announced_games), so a later push about the same
--     player says "N more" and gives the day's total, and a push about a
--     different player never says "more".
--
-- Additive: three new functions, two new columns, three functions replaced
-- with the same signatures. The cron jobs are unchanged.

begin;

-- Each reader's IANA timezone, best source first:
--   1. the zone the app sent with its last registration, on a device seen in
--      the last 30 days (the phone's own clock, so DST and travel included);
--   2. the zone OneSignal reported (public.user_timezones);
--   3. any registered device's zone, however old.
-- Names PostgreSQL does not know are skipped: one would fail a whole run.
create or replace function public.reader_timezones(p_user_ids uuid[] default null)
returns table (user_id uuid, timezone text)
language sql
stable
security definer
set search_path = ''
as $$
  with known as (
    select name from pg_catalog.pg_timezone_names
  ),
  devices as (
    select distinct on (d.user_id)
           d.user_id,
           d.timezone,
           d.last_seen_at > now() - interval '30 days' as recent
      from admin_portal.devices d
     where d.user_id is not null
       and (p_user_ids is null or d.user_id = any(p_user_ids))
       and d.timezone in (select name from known)
     order by d.user_id, d.last_seen_at desc nulls last
  ),
  onesignal as (
    select tz.user_id, tz.timezone
      from public.user_timezones tz
     where (p_user_ids is null or tz.user_id = any(p_user_ids))
       and tz.timezone in (select name from known)
  )
  select coalesce(d.user_id, o.user_id),
         case
           when d.recent then d.timezone
           else coalesce(o.timezone, d.timezone)
         end
    from devices d
    full join onesignal o on o.user_id = d.user_id;
$$;

revoke all on function public.reader_timezones(uuid[]) from public, anon, authenticated;
grant execute on function public.reader_timezones(uuid[]) to service_role;

-- smart_event_digest_rows for the readers in [p_user_ids] only, each counted
-- from their own [p_since] (the same position in the arrays) up to
-- [p_window_end]: the games their smart events caught today, where they live.
-- Same filters, same tallies, same columns as smart_event_digest_rows.
create or replace function public.smart_event_digest_rows_since(
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
  top_status text,
  top_average integer,
  top_opening text,
  top_event text
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
    select distinct on (m.user_id, m.event_id)
      m.user_id, m.event_id, m.id, m.player_white, m.player_black, m.status,
      m.average, m.opening_name, m.event_name
    from matched m
    order by m.user_id, m.event_id, m.average desc nulls last,
      m.last_move_time desc nulls last, m.id
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
    top.status,
    top.average,
    top.opening_name,
    top.event_name
  from criteria c
  join tallies t on t.user_id = c.user_id and t.event_id = c.event_id
  join tops top on top.user_id = c.user_id and top.event_id = c.event_id;
$$;

revoke all on function public.smart_event_digest_rows_since(timestamptz, uuid[], timestamptz[])
  from public, anon, authenticated;
grant execute on function public.smart_event_digest_rows_since(timestamptz, uuid[], timestamptz[])
  to service_role;

-- Same four-hour job: each run reaches the readers whose evening it is
-- (19:00-22:59 where they live), once per local day, with the smart event
-- that caught the most games today.
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

  -- Whose evening it is, and when their day began.
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
         array_agg(c.timezone)
    into v_users, v_since, v_days, v_zones
  from clocks c
  where extract(hour from c.local_now) between 19 and 22;

  if v_users is null then
    return 0;
  end if;

  with readers as (
    select r.user_id, r.since, r.local_day, r.timezone
    from unnest(v_users, v_since, v_days, v_zones)
      as r(user_id, since, local_day, timezone)
  ),
  digests as (
    select d.*, rd.since, rd.local_day, rd.timezone,
      row_number() over (partition by d.user_id
        order by d.games desc, d.top_average desc nulls last, d.smart_event_id) as pick,
      count(*) over (partition by d.user_id) as caught
    from public.smart_event_digest_rows_since(run_at, v_users, v_since) d
    join readers rd on rd.user_id = d.user_id
    where d.games > 0
  )
  insert into public.notification_outbox (event_type, payload, dedupe_key)
  select
    'smart_event_digest',
    jsonb_build_object(
      'user_id', d.user_id,
      'smart_event_id', d.smart_event_id,
      'smart_event_name', d.smart_event_name,
      'label', d.label,
      'min_elo', d.min_elo,
      'max_elo', d.max_elo,
      'formats', to_jsonb(d.formats),
      'eco_code', d.eco_code,
      'games', d.games,
      'live_games', d.live_games,
      'white_wins', d.white_wins,
      'black_wins', d.black_wins,
      'draws', d.draws,
      'top_game_id', d.top_game_id,
      'top_white', d.top_white,
      'top_black', d.top_black,
      'top_status', d.top_status,
      'top_average', d.top_average,
      'top_opening', d.top_opening,
      'top_event', d.top_event,
      'other_smart_events', d.caught - 1,
      'timezone', d.timezone,
      'local_day', d.local_day,
      -- The counts run from the reader's local midnight to window_end.
      'since', d.since,
      'window_end', run_at),
    'smart_event_digest:' || d.user_id || ':' || d.local_day
  from digests d
  where d.pick = 1
  on conflict (dedupe_key) do nothing;
  get diagnostics queued = row_count;
  return queued;
end;
$$;

revoke all on function public.queue_smart_event_digests()
  from public, anon, authenticated;
grant execute on function public.queue_smart_event_digests() to service_role;

-- What each starred account's reader was already told today: the games of
-- the pushes about this player on announced_day.
alter table public.prep_profile_watches
  add column if not exists announced_day date,
  add column if not exists announced_games integer not null default 0;

create or replace function public.record_prep_watch_checks(p_checks jsonb)
returns integer
language sql
security definer
set search_path = public
as $$
  with c as (
    select *
      from jsonb_to_recordset(
        case when jsonb_typeof(p_checks) = 'array' then p_checks else '[]'::jsonb end
      ) as x(id uuid, games integer, time_controls text[])
  ), zones as (
    -- The reader's own zone (DST and travel included) when it is known;
    -- else the offset the app sent with the star.
    select z.user_id, z.timezone
      from public.reader_timezones(array(
        select distinct w.user_id
          from public.prep_profile_watches w
          join c on c.id = w.id
      )) z
  ), calc as (
    select w.id,
           c.games,
           (case when z.timezone is not null then now() at time zone z.timezone
                 else (now() at time zone 'utc')
                   + make_interval(mins => w.utc_offset_minutes::integer)
            end)::date as today,
           w.baseline_games is not null and c.games > w.baseline_games as grew,
           c.games - w.baseline_games as growth
      from public.prep_profile_watches w
      join c on c.id = w.id
      left join zones z on z.user_id = w.user_id
     where w.time_controls = coalesce(c.time_controls, '{}')
  ), updated as (
    update public.prep_profile_watches w
       set baseline_games = coalesce(calc.games, w.baseline_games),
           pending_games = case
             when calc.grew then
               (case when w.pending_day = calc.today then w.pending_games else 0 end)
                 + calc.growth
             else w.pending_games
           end,
           pending_day = case when calc.grew then calc.today else w.pending_day end,
           last_new_at = case when calc.grew then now() else w.last_new_at end,
           checked_at = now()
      from calc
     where w.id = calc.id
    returning 1
  )
  select count(*)::integer from updated;
$$;

create or replace function public.queue_prep_games_pushes()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_queued integer;
begin
  -- Readers whose zone is unknown or a day old: onesignal-dispatch looks it
  -- up (user_timezone_refresh), so the next runs follow DST and travel.
  insert into public.notification_outbox (event_type, payload, dedupe_key)
  select 'user_timezone_refresh',
         jsonb_build_object('user_ids', jsonb_agg(stale.user_id)),
         'user_timezone_refresh:prep:' ||
           extract(epoch from date_trunc('hour', now()))::bigint || ':' || stale.batch
    from (
      select s.user_id, (row_number() over (order by s.user_id) - 1) / 100 as batch
        from (select distinct w.user_id from public.prep_profile_watches w) s
        left join public.user_timezones tz on tz.user_id = s.user_id
       where tz.user_id is null or tz.checked_at < now() - interval '1 day'
    ) stale
   group by stale.batch
  on conflict (dedupe_key) do nothing;

  with zones as (
    select z.user_id, z.timezone
      from public.reader_timezones(array(
        select distinct w.user_id from public.prep_profile_watches w
         where w.pending_games > 0
      )) z
  ), timed as (
    select w.*,
           case when z.timezone is not null then now() at time zone z.timezone
                else (now() at time zone 'utc')
                  + make_interval(mins => w.utc_offset_minutes::integer)
           end as local_now
      from public.prep_profile_watches w
      left join zones z on z.user_id = w.user_id
  ), profiles as (
    select t.user_id,
           t.profile_id,
           max(t.profile_name) as profile_name,
           max(t.profile_title) as profile_title,
           sum(t.pending_games)::integer as games,
           jsonb_agg(
             jsonb_build_object('source', t.source, 'username', t.username)
             order by t.pending_games desc, t.source, lower(t.username)
           ) as accounts,
           max(t.local_now) as local_now
      from timed t
     where t.pending_games > 0
       and t.pending_day = t.local_now::date
     group by t.user_id, t.profile_id
  ), told as (
    -- Games of each player the reader was already told about today.
    select t.user_id,
           t.profile_id,
           sum(t.announced_games) filter (
             where t.announced_day = t.local_now::date
           )::integer as games
      from timed t
     group by t.user_id, t.profile_id
  ), ranked as (
    select p.*,
           coalesce(o.games, 0) as earlier_today,
           row_number() over (
             partition by p.user_id order by p.games desc, p.profile_name
           ) as pick,
           count(*) over (partition by p.user_id) as players
      from profiles p
      left join told o on o.user_id = p.user_id and o.profile_id = p.profile_id
  ), due as (
    select r.*,
           r.local_now::date as local_day,
           case when s.local_day = r.local_now::date then s.pushes else 0 end + 1
             as slot
      from ranked r
      left join public.prep_watch_pushes s on s.user_id = r.user_id
     where r.pick = 1
       and extract(hour from r.local_now) between 9 and 22
       and (s.user_id is null
            or s.local_day <> r.local_now::date
            or s.pushes < 2)
       and (s.user_id is null or s.last_push_at <= now() - interval '4 hours')
  ), queued as (
    insert into public.notification_outbox (event_type, payload, dedupe_key)
    select 'prep_games_added',
           jsonb_build_object(
             'user_id', d.user_id,
             'profile_id', d.profile_id,
             'profile_name', d.profile_name,
             'profile_title', d.profile_title,
             'accounts', d.accounts,
             'added', d.games,
             'earlier_today', d.earlier_today,
             'other_players', d.players - 1,
             'slot', d.slot,
             'local_hour', extract(hour from d.local_now)::integer,
             'local_date', d.local_day
           ),
           'prep_games_added:' || d.user_id || ':' || d.local_day || ':' || d.slot
      from due d
    on conflict (dedupe_key) do nothing
    returning (payload->>'user_id')::uuid as user_id,
              payload->>'profile_id' as profile_id,
              (payload->>'local_date')::date as local_day,
              (payload->>'slot')::smallint as slot
  ), logged as (
    insert into public.prep_watch_pushes as s (user_id, local_day, pushes, last_push_at)
    select q.user_id, q.local_day, q.slot, now() from queued q
    on conflict (user_id) do update
       set local_day = excluded.local_day,
           pushes = excluded.pushes,
           last_push_at = excluded.last_push_at
    returning s.user_id
  ), cleared as (
    -- Only the announced player: the reader's other players keep their new
    -- games for a push of their own. Every data-modifying step runs to
    -- completion, read or not.
    update public.prep_profile_watches w
       set announced_games = (
             case when w.announced_day = q.local_day then w.announced_games else 0 end
           ) + w.pending_games,
           announced_day = q.local_day,
           pending_games = 0
      from queued q
     where w.user_id = q.user_id
       and w.profile_id = q.profile_id
       and w.pending_day = q.local_day
    returning 1
  )
  select count(*)::integer into v_queued from logged;
  return v_queued;
end;
$$;

revoke execute on function public.record_prep_watch_checks(jsonb) from public, anon, authenticated;
revoke execute on function public.queue_prep_games_pushes() from public, anon, authenticated;
grant execute on function public.record_prep_watch_checks(jsonb) to service_role;
grant execute on function public.queue_prep_games_pushes() to service_role;

-- Moves every star of the collection [p_from] to its new slug [p_to]: the
-- `collection:<slug>` rows and the older rows the app still reads as the
-- star (`metadata.kind: collection`, `metadata.slug`). A reader who already
-- stars the new slug keeps that row. Called by gamebase (service key) after
-- a rename commits; returns how many stars moved.
create or replace function public.rename_collection_stars(p_from text, p_to text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from text := btrim(coalesce(p_from, ''));
  v_to text := btrim(coalesce(p_to, ''));
  v_moved integer;
begin
  if v_from = '' or v_to = '' or v_from = v_to then
    return 0;
  end if;

  delete from public.user_favorite_events f
   where (f.event_id = 'collection:' || v_from
          or (f.metadata->>'kind' = 'collection' and f.metadata->>'slug' = v_from))
     and exists (
       select 1 from public.user_favorite_events o
        where o.user_id = f.user_id and o.event_id = 'collection:' || v_to);

  update public.user_favorite_events f
     set event_id = case
           when f.event_id = 'collection:' || v_from then 'collection:' || v_to
           else f.event_id
         end,
         metadata = case
           when f.metadata->>'slug' = v_from
             then f.metadata || jsonb_build_object('slug', v_to)
           else f.metadata
         end,
         updated_at = now()
   where f.event_id = 'collection:' || v_from
      or (f.metadata->>'kind' = 'collection' and f.metadata->>'slug' = v_from);
  get diagnostics v_moved = row_count;
  return v_moved;
end;
$$;

revoke all on function public.rename_collection_stars(text, text) from public, anon, authenticated;
grant execute on function public.rename_collection_stars(text, text) to service_role;

commit;
