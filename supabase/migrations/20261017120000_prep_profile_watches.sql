-- Starred My Prep profiles: tell the owner, the same day and while they are
-- awake, that the player is playing online.
--
-- My Prep keeps its profiles on the device. Starring one sends its Lichess
-- and Chess.com accounts here. Every hour `prep-games-check` reads each
-- starred player's game totals (one small JSON per account, never the games)
-- and records any growth against the owner's local day
-- (record_prep_watch_checks). Then queue_prep_games_pushes sends what was
-- recorded, but never while the owner sleeps (23:00-08:59 local), never
-- about a previous day, at most twice a day and at least four hours apart:
-- one push per owner, about the player with the most new games, naming the
-- account ("GM Vasif Durarbayli played this afternoon" / "New games from
-- durarbayli on Lichess"). onesignal-dispatch sends it.
--
-- Unstarring is the opt-out: the rows go, and so do the pushes.
--
-- Additive: two new tables, their functions and one cron job. Nothing
-- existing is changed.

begin;

create table public.prep_profile_watches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  -- PrepProfile.id: the profile lives on the owner's device.
  profile_id text not null,
  profile_name text not null,
  -- "GM", "IM", ... when the profile has one.
  profile_title text,
  source text not null,
  username text not null,
  -- The PrepTimeControl names the account downloads. Empty means every clock.
  time_controls text[] not null default '{}',
  -- The owner's offset from UTC, as the app last wrote it.
  utc_offset_minutes smallint not null default 0,
  -- The player's game total over time_controls at the last check. Null until
  -- the first check, and again when the clocks change: a total over other
  -- clocks says nothing about new games.
  baseline_games integer,
  -- New games found since the owner's last push, on pending_day (the
  -- owner's local date when they were found). A new day starts from zero.
  pending_games integer not null default 0,
  pending_day date,
  last_new_at timestamptz,
  checked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint prep_profile_watches_source_known check (
    source in ('lichess', 'chesscom')
  ),
  constraint prep_profile_watches_username_shape check (
    username ~ '^[A-Za-z0-9_-]{2,40}$'
  ),
  constraint prep_profile_watches_profile_id_length check (
    char_length(profile_id) between 1 and 120
  ),
  constraint prep_profile_watches_name_length check (
    char_length(profile_name) between 1 and 120
  ),
  constraint prep_profile_watches_title_length check (
    profile_title is null or char_length(profile_title) between 1 and 8
  ),
  -- UTC-14:00 to UTC+14:00.
  constraint prep_profile_watches_offset_range check (
    utc_offset_minutes between -840 and 840
  )
);

comment on table public.prep_profile_watches is
  'Online accounts of starred My Prep profiles. Written by the app through set_prep_profile_watch / clear_prep_profile_watch; checked hourly by the prep-games-check Edge Function.';

-- Both sites treat names without case.
create unique index prep_profile_watches_account_key
  on public.prep_profile_watches (user_id, profile_id, source, lower(username));

alter table public.prep_profile_watches enable row level security;

-- Owners may read their rows. Every write goes through the functions below,
-- so the server's counts cannot be written from the app.
create policy prep_profile_watches_owner_read
  on public.prep_profile_watches for select to authenticated
  using (auth.uid() = user_id);

revoke all on public.prep_profile_watches from public, anon, authenticated;
grant select on public.prep_profile_watches to authenticated;
grant select, insert, update, delete on public.prep_profile_watches to service_role;

-- How many Prep pushes each owner had today: two a day at most, four hours
-- apart. Service only.
create table public.prep_watch_pushes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  local_day date not null,
  pushes smallint not null default 0,
  last_push_at timestamptz not null
);

alter table public.prep_watch_pushes enable row level security;
revoke all on public.prep_watch_pushes from public, anon, authenticated;
grant select, insert, update, delete on public.prep_watch_pushes to service_role;

-- Stars [p_profile_id] with its online accounts, or brings a starred one up
-- to date: a source detached since is dropped, a renamed profile renamed.
-- [p_accounts] is [{source, username, time_controls: [...]}]; entries the
-- table cannot hold are left out rather than failing the star. Every row of
-- the caller takes [p_utc_offset_minutes], so the pushes follow them across
-- time zones and clock changes. Returns how many accounts are watched.
create or replace function public.set_prep_profile_watch(
  p_profile_id text,
  p_profile_name text,
  p_accounts jsonb,
  p_utc_offset_minutes integer,
  p_profile_title text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_profile text := btrim(coalesce(p_profile_id, ''));
  v_name text := left(btrim(coalesce(p_profile_name, '')), 120);
  v_title text := nullif(left(btrim(coalesce(p_profile_title, '')), 8), '');
  v_offset smallint := greatest(-840, least(840, coalesce(p_utc_offset_minutes, 0)));
  v_accounts jsonb := case
    when jsonb_typeof(p_accounts) = 'array' then p_accounts
    else '[]'::jsonb
  end;
  v_watched integer;
begin
  if v_user is null then
    raise exception 'Sign in to star a profile.' using errcode = '42501';
  end if;
  if char_length(v_profile) not between 1 and 120 then
    raise exception 'Unknown profile.' using errcode = '22023';
  end if;
  if v_name = '' then
    v_name := 'Your player';
  end if;

  delete from public.prep_profile_watches w
   where w.user_id = v_user
     and w.profile_id = v_profile
     and not exists (
       select 1
         from jsonb_to_recordset(v_accounts) as a(source text, username text)
        where a.source = w.source
          and lower(a.username) = lower(w.username)
     );

  insert into public.prep_profile_watches as w (
    user_id, profile_id, profile_name, profile_title, source, username,
    time_controls, utc_offset_minutes
  )
  select distinct on (a.source, lower(a.username))
         v_user,
         v_profile,
         v_name,
         v_title,
         a.source,
         a.username,
         coalesce(
           array(
             select distinct t
               from jsonb_array_elements_text(
                 case
                   when jsonb_typeof(a.time_controls) = 'array'
                     then a.time_controls
                   else '[]'::jsonb
                 end
               ) as t
              where t in (
                'ultrabullet', 'bullet', 'blitz', 'rapid', 'classical',
                'correspondence'
              )
              order by t
           ),
           '{}'
         ),
         v_offset
    from jsonb_to_recordset(v_accounts)
         as a(source text, username text, time_controls jsonb)
   where a.source in ('lichess', 'chesscom')
     and a.username ~ '^[A-Za-z0-9_-]{2,40}$'
   order by a.source, lower(a.username)
   limit 12
  on conflict (user_id, profile_id, source, lower(username)) do update
     set profile_name = excluded.profile_name,
         profile_title = excluded.profile_title,
         username = excluded.username,
         utc_offset_minutes = excluded.utc_offset_minutes,
         time_controls = excluded.time_controls,
         baseline_games = case
           when w.time_controls = excluded.time_controls then w.baseline_games
         end,
         updated_at = now();

  update public.prep_profile_watches
     set utc_offset_minutes = v_offset,
         updated_at = now()
   where user_id = v_user
     and utc_offset_minutes <> v_offset;

  if (select count(*) from public.prep_profile_watches where user_id = v_user) > 600 then
    raise exception 'Too many starred profiles.' using errcode = '54000';
  end if;

  select count(*)::integer into v_watched
    from public.prep_profile_watches
   where user_id = v_user
     and profile_id = v_profile;
  return v_watched;
end;
$$;

-- Unstars [p_profile_id]: no more checks, no more pushes.
create or replace function public.clear_prep_profile_watch(p_profile_id text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.prep_profile_watches
   where user_id = auth.uid()
     and profile_id = btrim(coalesce(p_profile_id, ''));
$$;

revoke execute on function public.set_prep_profile_watch(text, text, jsonb, integer, text) from public, anon;
revoke execute on function public.clear_prep_profile_watch(text) from public, anon;
grant execute on function public.set_prep_profile_watch(text, text, jsonb, integer, text) to authenticated;
grant execute on function public.clear_prep_profile_watch(text) to authenticated;

-- Every starred account, the longest unchecked first: prep-games-check reads
-- them all each hour, as far as its time allows.
create or replace function public.prep_watches_to_check(
  p_limit integer default 2000
)
returns table (
  id uuid,
  source text,
  username text,
  time_controls text[],
  baseline_games integer
)
language sql
stable
security definer
set search_path = public
as $$
  select w.id, w.source, w.username, w.time_controls, w.baseline_games
    from public.prep_profile_watches w
   order by w.checked_at nulls first, w.id
   limit greatest(1, least(coalesce(p_limit, 2000), 20000));
$$;

-- Records what prep-games-check read: [{id, games, time_controls}]. `games`
-- null keeps the total (the account could not be read). A first total only
-- sets what the next check compares with; growth adds to the owner's games
-- of the day (a new local day starts from zero); a total that fell (a site
-- recounting) only moves the baseline. A row whose clocks changed since it
-- was read is left alone. Returns how many rows took the result.
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
  ), calc as (
    select w.id,
           c.games,
           ((now() at time zone 'utc')
             + make_interval(mins => w.utc_offset_minutes::integer))::date as today,
           w.baseline_games is not null and c.games > w.baseline_games as grew,
           c.games - w.baseline_games as growth
      from public.prep_profile_watches w
      join c on c.id = w.id
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

-- Sends what record_prep_watch_checks found: one push per owner who
--   * has new games found today (their local date) on a starred profile,
--   * is awake (09:00-22:59 local),
--   * had fewer than two Prep pushes today and none in the last four hours.
-- The push is about the profile with the most new games today, naming the
-- accounts they came from, and says how many other starred players played.
-- What it announces is cleared, so the next push is about newer games.
-- Returns how many pushes were queued.
create or replace function public.queue_prep_games_pushes()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_queued integer;
begin
  with timed as (
    select w.*,
           (now() at time zone 'utc')
             + make_interval(mins => w.utc_offset_minutes::integer) as local_now
      from public.prep_profile_watches w
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

-- Starts prep-games-check, which authenticates with the dispatcher's stream
-- token. Quiet when nothing is starred.
create or replace function public.kick_prep_games_check()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_token text;
  v_headers jsonb := jsonb_build_object('Content-Type', 'application/json');
begin
  if not exists (select 1 from public.prep_profile_watches) then
    return;
  end if;

  v_url := public.get_vault_secret('prep_games_check_url');
  if v_url is null or v_url = '' then
    v_url := 'https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/prep-games-check';
  end if;

  v_token := public.get_vault_secret('live_dispatch_token');
  if v_token is not null and v_token <> '' then
    v_headers := v_headers || jsonb_build_object('x-stream-token', v_token);
  end if;

  begin
    perform net.http_post(
      url := v_url,
      body := '{}'::jsonb,
      headers := v_headers
    );
  exception when others then
    null;
  end;
end;
$$;

revoke execute on function public.prep_watches_to_check(integer) from public, anon, authenticated;
revoke execute on function public.record_prep_watch_checks(jsonb) from public, anon, authenticated;
revoke execute on function public.queue_prep_games_pushes() from public, anon, authenticated;
revoke execute on function public.kick_prep_games_check() from public, anon, authenticated;
grant execute on function public.prep_watches_to_check(integer) to service_role;
grant execute on function public.record_prep_watch_checks(jsonb) to service_role;
grant execute on function public.queue_prep_games_pushes() to service_role;
grant execute on function public.kick_prep_games_check() to service_role;

-- Hourly, off the top of the hour where the other jobs bunch up.
select cron.schedule(
  'prep-games-check',
  '7 * * * *',
  $$select public.kick_prep_games_check()$$
);

commit;
