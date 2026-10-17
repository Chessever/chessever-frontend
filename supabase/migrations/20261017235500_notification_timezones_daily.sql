-- Timezone-aware to the day, DST and travel included.
--
-- Prep pushes worked out the reader's day and waking hours from the fixed UTC
-- offset the app sent with the star, which is an hour off after a DST change
-- (Europe 2026-10-25, the US 2026-11-01) until the app writes it again. They
-- now use the reader's IANA zone from public.user_timezones (read from
-- OneSignal, as smart event pushes do) and fall back to that offset only
-- while the zone is unknown. queue_prep_games_pushes asks for the zones of
-- Prep starrers too.
--
-- Zones are refreshed daily instead of weekly, for smart event and Prep
-- starrers alike, so a reader who travels is followed within a day.
--
-- Additive: replaces three functions with the same signatures.

begin;

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
    -- The reader's own zone (DST and travel included) when it is known and
    -- valid; else the offset the app sent with the star.
    select tz.user_id, tz.timezone
      from public.user_timezones tz
     where tz.timezone in (select name from pg_catalog.pg_timezone_names)
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
    -- The reader's own zone (DST and travel included) when it is known and
    -- valid; else the offset the app sent with the star.
    select tz.user_id, tz.timezone
      from public.user_timezones tz
     where tz.timezone in (select name from pg_catalog.pg_timezone_names)
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
  ), ranked as (
    select p.*,
           row_number() over (
             partition by p.user_id order by p.games desc, p.profile_name
           ) as pick,
           count(*) over (partition by p.user_id) as players
      from profiles p
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
             'other_players', d.players - 1,
             'slot', d.slot,
             'local_hour', extract(hour from d.local_now)::integer,
             'local_date', d.local_day
           ),
           'prep_games_added:' || d.user_id || ':' || d.local_day || ':' || d.slot
      from due d
    on conflict (dedupe_key) do nothing
    returning (payload->>'user_id')::uuid as user_id,
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
    -- Every data-modifying step runs to completion, read or not.
    update public.prep_profile_watches w
       set pending_games = 0
      from logged l
     where w.user_id = l.user_id
    returning 1
  )
  select count(*)::integer into v_queued from logged;
  return v_queued;
end;
$$;

create or replace function public.queue_smart_event_digests()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  run_at timestamptz := now();
  queued integer;
begin
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

  -- A name PostgreSQL does not know would fail the whole run: each one is
  -- checked before it is used.
  with known as (
    select tz.user_id, tz.timezone
    from public.user_timezones tz
    where tz.timezone in (select name from pg_catalog.pg_timezone_names)
  ),
  -- Readers whose app opens the push where it points (the smart event's
  -- Games tab): a device on build 3676 (37.0.4) or later, seen in the last
  -- 60 days. Older builds would open the strongest game instead.
  ready as (
    select distinct d.user_id
    from admin_portal.devices d
    where d.user_id is not null
      and case when split_part(d.app_version, '+', 2) ~ '^[0-9]{1,9}$'
        then split_part(d.app_version, '+', 2)::integer end >= 3676
      and d.last_seen_at > run_at - interval '60 days'
  ),
  evening as (
    select k.user_id, k.timezone, (run_at at time zone k.timezone)::date as local_day
    from known k
    join ready r on r.user_id = k.user_id
    where case when k.timezone in (select name from pg_catalog.pg_timezone_names)
      then extract(hour from run_at at time zone k.timezone) between 19 and 22
      else false end
  ),
  digests as (
    select d.*, e.timezone, e.local_day,
      row_number() over (partition by d.user_id
        order by d.games desc, d.top_average desc nulls last, d.smart_event_id) as pick,
      count(*) over (partition by d.user_id) as caught
    from public.smart_event_digest_rows(run_at, interval '24 hours') d
    join evening e on e.user_id = d.user_id
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

revoke execute on function public.record_prep_watch_checks(jsonb) from public, anon, authenticated;
revoke execute on function public.queue_prep_games_pushes() from public, anon, authenticated;
grant execute on function public.record_prep_watch_checks(jsonb) to service_role;
grant execute on function public.queue_prep_games_pushes() to service_role;

commit;
