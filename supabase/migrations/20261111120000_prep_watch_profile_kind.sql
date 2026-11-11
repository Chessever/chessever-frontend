-- Prep stars know whose profile they are.
--
-- The reader's own profile (My Prep > Games) can be starred like any other,
-- but its push read as if about a stranger: "Berkay played 7 games today!".
-- Each starred account now carries the profile's kind, and the push payload
-- passes it on, so onesignal-dispatch words the reader's own games as theirs.
--
-- Additive: one nullable column; set_prep_profile_watch gains a trailing
-- optional p_profile_kind (old apps call it without, and their rows keep a
-- null kind, worded as before); queue_prep_games_pushes adds one payload key.
-- Nothing is deleted. Cron jobs unchanged.

begin;

alter table public.prep_profile_watches
  add column if not exists profile_kind text;

alter table public.prep_profile_watches
  drop constraint if exists prep_profile_watches_kind_known;
alter table public.prep_profile_watches
  add constraint prep_profile_watches_kind_known check (
    profile_kind is null or profile_kind in ('mine', 'opponent', 'favorite')
  );

-- A new trailing parameter makes a new signature: drop the old one so
-- PostgREST resolves both old (five named arguments) and new calls here.
drop function if exists public.set_prep_profile_watch(text, text, jsonb, integer, text);

create or replace function public.set_prep_profile_watch(
  p_profile_id text,
  p_profile_name text,
  p_accounts jsonb,
  p_utc_offset_minutes integer,
  p_profile_title text default null,
  p_profile_kind text default null
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
  v_kind text := case
    when p_profile_kind in ('mine', 'opponent', 'favorite') then p_profile_kind
  end;
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
    user_id, profile_id, profile_name, profile_title, profile_kind, source,
    username, time_controls, utc_offset_minutes
  )
  select distinct on (a.source, lower(a.username))
         v_user,
         v_profile,
         v_name,
         v_title,
         v_kind,
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
         profile_kind = excluded.profile_kind,
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
           max(t.profile_kind) as profile_kind,
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
             'profile_kind', d.profile_kind,
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

revoke execute on function public.set_prep_profile_watch(text, text, jsonb, integer, text, text) from public, anon;
grant execute on function public.set_prep_profile_watch(text, text, jsonb, integer, text, text) to authenticated;
revoke execute on function public.queue_prep_games_pushes() from public, anon, authenticated;
grant execute on function public.queue_prep_games_pushes() to service_role;

notify pgrst, 'reload schema';

commit;
