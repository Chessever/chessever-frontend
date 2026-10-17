-- Starred My Prep profiles, mirrored so the server can tell their owners once
-- a day, in the owner's own evening, that the player has new online games.
--
-- My Prep keeps its profiles on the device. Starring one sends its Lichess
-- and Chess.com accounts here. Every hour `prep-games-check` looks at the
-- owners whose local time has reached the check hour, reads each player's
-- game totals (one small JSON per account, never the games) and compares
-- them with the totals it saw the day before. A higher total queues one
-- `prep_games_added` outbox row per profile; onesignal-dispatch sends it.
--
-- Additive: one new table, its functions and one cron job. Nothing existing
-- is changed.

begin;

create table public.prep_profile_watches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  -- PrepProfile.id: the profile lives on the owner's device.
  profile_id text not null,
  profile_name text not null,
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
  -- The owner's local date of the last daily check.
  checked_on date,
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
  -- UTC-14:00 to UTC+14:00.
  constraint prep_profile_watches_offset_range check (
    utc_offset_minutes between -840 and 840
  )
);

comment on table public.prep_profile_watches is
  'Online accounts of starred My Prep profiles. Written by the app through set_prep_profile_watch / clear_prep_profile_watch; checked daily by the prep-games-check Edge Function.';

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

-- Stars [p_profile_id] with its online accounts, or brings a starred one up
-- to date: a source detached since is dropped, a renamed profile renamed.
-- [p_accounts] is [{source, username, time_controls: [...]}]; entries the
-- table cannot hold are left out rather than failing the star. Every row of
-- the caller takes [p_utc_offset_minutes], so the check follows them across
-- time zones and clock changes. Returns how many accounts are watched.
create or replace function public.set_prep_profile_watch(
  p_profile_id text,
  p_profile_name text,
  p_accounts jsonb,
  p_utc_offset_minutes integer
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
    user_id, profile_id, profile_name, source, username, time_controls,
    utc_offset_minutes
  )
  select distinct on (a.source, lower(a.username))
         v_user,
         v_profile,
         v_name,
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

revoke execute on function public.set_prep_profile_watch(text, text, jsonb, integer) from public, anon;
revoke execute on function public.clear_prep_profile_watch(text) from public, anon;
grant execute on function public.set_prep_profile_watch(text, text, jsonb, integer) to authenticated;
grant execute on function public.clear_prep_profile_watch(text) to authenticated;

-- The profiles prep-games-check should look at now, every account of each.
-- `daily`: the owner's clock has reached [p_local_hour] and today's check has
-- not run, so new games are announced. An account with no total yet is due
-- at any hour, to set the total the next check compares with; one the sites
-- could not answer for waits six hours before it is asked again. A profile's
-- accounts come together, so it gets one push however many it has.
create or replace function public.due_prep_profile_watches(
  p_local_hour integer default 19,
  p_limit integer default 500
)
returns table (
  id uuid,
  user_id uuid,
  profile_id text,
  profile_name text,
  source text,
  username text,
  time_controls text[],
  baseline_games integer,
  local_date date,
  daily boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with timed as (
    select w.*,
           (now() at time zone 'utc')
             + make_interval(mins => w.utc_offset_minutes::integer) as local_now
      from public.prep_profile_watches w
  ), flagged as (
    select t.*,
           (
             extract(hour from t.local_now) >= p_local_hour
             and (t.checked_on is null or t.checked_on < t.local_now::date)
           ) as is_daily,
           (
             t.baseline_games is null
             and (t.checked_at is null or t.checked_at < now() - interval '6 hours')
           ) as needs_total
      from timed t
  ), due as (
    select f.user_id, f.profile_id
      from flagged f
     group by f.user_id, f.profile_id
    having bool_or(f.is_daily or f.needs_total)
     order by min(f.checked_at) nulls first
     limit greatest(1, least(coalesce(p_limit, 500), 5000))
  )
  select f.id, f.user_id, f.profile_id, f.profile_name, f.source, f.username,
         f.time_controls, f.baseline_games, f.local_now::date, f.is_daily
    from flagged f
    join due d on d.user_id = f.user_id and d.profile_id = f.profile_id;
$$;

-- Records what prep-games-check read: [{id, games, checked_on, time_controls}].
-- `games` null keeps the total (the account could not be read); `checked_on`
-- null keeps the date (a total taken outside the daily check). A row whose
-- clocks changed since it was read is left alone: its count is of the old
-- clocks. Returns how many rows took the result.
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
      ) as x(id uuid, games integer, checked_on date, time_controls text[])
  ), updated as (
    update public.prep_profile_watches w
       set baseline_games = coalesce(c.games, w.baseline_games),
           checked_on = coalesce(c.checked_on, w.checked_on),
           checked_at = now()
      from c
     where w.id = c.id
       and w.time_controls = coalesce(c.time_controls, '{}')
    returning 1
  )
  select count(*)::integer from updated;
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

revoke execute on function public.due_prep_profile_watches(integer, integer) from public, anon, authenticated;
revoke execute on function public.record_prep_watch_checks(jsonb) from public, anon, authenticated;
revoke execute on function public.kick_prep_games_check() from public, anon, authenticated;
grant execute on function public.due_prep_profile_watches(integer, integer) to service_role;
grant execute on function public.record_prep_watch_checks(jsonb) to service_role;
grant execute on function public.kick_prep_games_check() to service_role;

-- Hourly, so each time zone is checked in its own evening. Off the top of
-- the hour, where the other jobs bunch up.
select cron.schedule(
  'prep-games-check',
  '7 * * * *',
  $$select public.kick_prep_games_check()$$
);

commit;
