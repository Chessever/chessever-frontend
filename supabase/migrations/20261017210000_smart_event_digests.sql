-- Starred smart events: every four hours, tell each starrer how many new games
-- their smart event caught, in words made for its kind of filter.
--
-- A smart event is a filter over games (an opening, a game-average rating
-- band, time controls, live or finished), not a tournament. Its favorites row
-- is `user_favorite_events.event_id = 'smart_event:v2:<criteria>'`. Starring
-- one is the subscription: every star notifies unless its owner turned it
-- off (`metadata.notificationsMuted = true`). `notificationsEnabled` is not
-- read here: the app saves it as false on every new star, so it says nothing
-- about what the owner wants.
--
-- The filter mirrors the app's own query (`get_current_smart_event_day` and
-- `smartEventFetchScopeFor`), so the count in the push matches the games the
-- tap opens.
--
-- Additive: three new functions and one cron job. Nothing existing changes.

begin;

-- `GameEcoFilter.exactEcoCodes`: the exact ECO codes a saved smart event's
-- opening covers. A family is a decade (`B9` = B90-B99), several decades
-- (`E6+E7+E8+E9`) or an inclusive range (`B20-B99`); anything else is one
-- code. Null for "every opening".
create or replace function public.smart_event_eco_codes(p_code text)
returns text[]
language plpgsql immutable parallel safe
set search_path = ''
as $$
declare
  code text := upper(replace(btrim(coalesce(p_code, '')), '–', '-'));
  bounds text[];
  part text;
  codes text[] := '{}';
  n integer;
begin
  if code = '' then
    return null;
  end if;
  if code = '?' or code ~ '^[A-E][0-9]{2}$' then
    return array[code];
  end if;
  bounds := regexp_match(code, '^([A-E])([0-9]{2})-([A-E])([0-9]{2})$');
  if bounds is not null then
    if bounds[1] <> bounds[3] or bounds[2]::integer > bounds[4]::integer then
      return array[code];
    end if;
    for n in bounds[2]::integer .. bounds[4]::integer loop
      codes := codes || (bounds[1] || lpad(n::text, 2, '0'));
    end loop;
    return codes;
  end if;
  foreach part in array string_to_array(code, '+') loop
    if part !~ '^[A-E][0-9]$' then
      return array[code];
    end if;
    for n in 0 .. 9 loop
      codes := codes || (part || n::text);
    end loop;
  end loop;
  return codes;
end;
$$;

grant execute on function public.smart_event_eco_codes(text) to public;

-- One row per starred smart event that caught games in the window
-- (p_window_end - p_window, p_window_end]: how many, how they ended, and the
-- strongest of them. "Caught" depends on the filter's state:
--   live only      games still live (the app's live test) with a move in the window
--   finished only  games that ended in the window
--   neither/both   every game with a move in the window
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
      and coalesce(f.metadata->>'notificationsMuted', '') <> 'true'
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

-- Reads every user's stars: service only.
revoke all on function public.smart_event_digest_rows(timestamptz, interval)
  from public, anon, authenticated;
grant execute on function public.smart_event_digest_rows(timestamptz, interval)
  to service_role;

-- Queues one `smart_event_digest` outbox row per starred smart event that
-- caught games in the four hours up to the last full hour; onesignal-dispatch
-- words and sends it. Rerunning within the same window queues nothing new.
create or replace function public.queue_smart_event_digests()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  window_end timestamptz := date_trunc('hour', now());
  queued integer;
begin
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
      'window_end', window_end),
    'smart_event_digest:' || d.user_id || ':' || d.smart_event_id || ':' ||
      extract(epoch from window_end)::bigint
  from public.smart_event_digest_rows(window_end, interval '4 hours') d
  where d.games > 0
  on conflict (dedupe_key) do nothing;
  get diagnostics queued = row_count;
  return queued;
end;
$$;

revoke all on function public.queue_smart_event_digests()
  from public, anon, authenticated;
grant execute on function public.queue_smart_event_digests() to service_role;

-- 00:00, 04:00, 08:00, 12:00, 16:00 and 20:00 UTC.
select cron.schedule(
  'queue-smart-event-digests',
  '0 */4 * * *',
  $$select public.queue_smart_event_digests()$$
);

commit;
