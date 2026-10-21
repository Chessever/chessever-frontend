-- Starred smart events: push only to readers whose app opens the push on the
-- smart event's Games tab (build 3676, 37.0.4, or later; the version each
-- device last reported to the notification service). Older builds would
-- route the tap to the strongest game. With this gate the four-hour job can
-- run before the release: pushes start for each reader as they update.
--
-- Additive: replaces queue_smart_event_digests() with the same signature.

begin;

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

commit;
