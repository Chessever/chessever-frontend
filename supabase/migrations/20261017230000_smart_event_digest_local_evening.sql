-- Starred smart events: one push per reader, in their own evening.
--
-- 20261017210000 queued a push for every starred smart event on every
-- four-hour run, whatever the hour where the reader lives. The four-hour job
-- stays (one run in every reader's 19:00-22:59, whatever their offset), but
-- each run now reaches only the readers whose evening it is, once per local
-- day, with the smart event that caught the most games in the last 24 hours.
--
-- Timezones: nothing in this database knows them (`user_notification_
-- preferences.timezone` is 'UTC' for everyone, `admin_portal.devices.
-- timezone` is empty). OneSignal does: the app logs every device in with
-- `OneSignal.login(<user id>)` and the SDK reports the phone's timezone.
-- Each run queues `user_timezone_refresh` rows for starrers not checked in a
-- week; onesignal-dispatch reads OneSignal and writes `user_timezones`. A
-- reader whose timezone is still unknown gets no push.
--
-- Starring is the subscription and unstarring the opt-out: no mute flag.
--
-- Additive: one new table; the two functions of 20261017210000 are
-- replaced with the same signatures. The cron job is unchanged.

begin;

create table if not exists public.user_timezones (
  user_id uuid primary key references auth.users(id) on delete cascade,
  -- IANA name ("Asia/Baku"); null when the source had none.
  timezone text,
  source text not null default 'onesignal',
  checked_at timestamptz not null default now()
);

comment on table public.user_timezones is
  'Each reader''s IANA timezone, read from OneSignal by onesignal-dispatch (user_timezone_refresh rows). Used to send smart event pushes in the reader''s evening. Service only.';

alter table public.user_timezones enable row level security;
revoke all on table public.user_timezones from anon, authenticated;
grant all on table public.user_timezones to service_role;

-- Same as 20261017210000 except that every star counts: no mute flag.
create or replace function public.smart_event_digest_rows(
  p_window_end timestamptz default date_trunc('hour', now()),
  p_window interval default interval '4 hours'
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
  with stars as (
    select
      f.user_id,
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
    where f.event_id like 'smart\_event:%'
      and f.user_id is not null
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
    where g.last_move_time > p_window_end - p_window
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
      on (c.min_bound is null
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

revoke all on function public.smart_event_digest_rows(timestamptz, interval)
  from public, anon, authenticated;
grant execute on function public.smart_event_digest_rows(timestamptz, interval)
  to service_role;

-- Each four-hour run:
--   1. asks onesignal-dispatch to look up the timezone of every smart
--      starrer not checked in the last week, 100 readers per outbox row;
--   2. queues one push for each starrer whose local time is 19:00-22:59:
--      the smart event that caught the most games in the last 24 hours,
--      with how many of their other smart events caught games too. The
--      dedupe key is per reader and local date, so a rerun sends nothing.
-- Returns the number of pushes queued.
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
    where tz.user_id is null or tz.checked_at < run_at - interval '7 days'
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
  evening as (
    select k.user_id, k.timezone, (run_at at time zone k.timezone)::date as local_day
    from known k
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

commit;
