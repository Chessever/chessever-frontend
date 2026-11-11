-- Mirror (Combined) sections stay on their own pages and out of every
-- cross-event list.
--
-- Some organizers publish real sections ("Group Stage | A".."D") plus a
-- "Combined" section that repeats every board as a separate game with its own
-- games.id and lichess_id. The Combined tour keeps its tour and round pages,
-- but its boards must never show up twice in favorites, countrymen, player
-- profiles, search, For You, smart events, date pickers, reports, likes,
-- streaks, notifications or the admin automation.
--
-- Contract shared with the apps, the web and the broadcasting API:
--   * tours.is_mirror  boolean not null default false, kept by a trigger.
--   * games.is_mirror  boolean not null default false, copied from its tour.
--   * Cross-event reads filter is_mirror = false. Tour, round and id reads
--     keep mirrors.
--
-- A tour is a mirror when tours.info.mirror says so (set it through
-- broadcasting_private.tour_info_overrides, which every hub rewrite keeps),
-- otherwise when its name or slug holds the whole word "combined" (the
-- onesignal-dispatch isCombinedSection rule) and its event also has a section
-- that is not combined.
--
-- Builds on 20261111193000_mirror_games_old_app_compat and
-- 20261111194500_mirror_tours_drop_team_tags, which keep released builds
-- clean: a mirror board carries "mirror": true (and no "team") on every players
-- element, the generated-column functions (player_fide_ids, player_feds,
-- player_max_rating, smart_event_average_rating) skip marked elements, its
-- search array is blanked, and a mirror tour's own players lose "team". Those
-- migrations decided "mirror" from info.mirror alone. Here games_mark_mirror
-- and tours_mirror_players read tours.is_mirror instead, so the name rule
-- covers every Combined section; games_mark_mirror also stamps
-- games.is_mirror, and tours_zzz_propagate_mirror replaces
-- tours_remark_mirror_games. The marker, the generated-column functions, the
-- team stripping and the search blanking are otherwise unchanged.
--
-- Both ADD COLUMNs are metadata-only (constant default, PostgreSQL 11+): no
-- table rewrite. They still take a brief ACCESS EXCLUSIVE lock on tours and
-- games, so the lock wait is bounded below.

set lock_timeout = '5s';

-- Take both table locks up front, games first: a reader holding games while it
-- waits for tours is the deadlock the two ALTERs would otherwise invite. If the
-- lock is not granted within lock_timeout the migration fails cleanly; retry.
lock table public.games, public.tours in access exclusive mode;

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------

alter table public.tours add column if not exists is_mirror boolean not null default false;
alter table public.games add column if not exists is_mirror boolean not null default false;

comment on column public.tours.is_mirror is
  'Combined/mirror section that repeats boards of real sections. Kept by tours_zzz_mirror_flag; override with tours.info.mirror.';
comment on column public.games.is_mirror is
  'Copied from tours.is_mirror by games_mark_mirror. Cross-event reads filter is_mirror = false.';

-- ---------------------------------------------------------------------------
-- Tour flag
-- ---------------------------------------------------------------------------

-- Same rule as supabase/functions/onesignal-dispatch/combined_section.ts
-- isCombinedSection: the whole word "combined" in "<name> <slug>".
create or replace function public.tour_label_is_combined(p_name text, p_slug text)
returns boolean
language sql
immutable
parallel safe
set search_path to ''
as $$
  select lower(coalesce(p_name, '') || ' ' || coalesce(p_slug, ''))
    ~ '(^|[^a-z0-9])combined([^a-z0-9]|$)';
$$;

revoke execute on function public.tour_label_is_combined(text, text) from public, anon, authenticated;

-- BEFORE INSERT OR UPDATE. Named to fire after tours_zz_apply_info_override
-- (BEFORE triggers fire in name order), so a manual info.mirror and any other
-- override are already merged in.
create or replace function public.tours_set_mirror_flag()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_override text;
  v_mirror boolean;
begin
  if jsonb_typeof(new.info) = 'object' and new.info ? 'mirror' then
    v_override := lower(btrim(new.info->>'mirror'));
    v_mirror := case
      when v_override in ('true', 't', 'yes', 'y', 'on', '1') then true
      when v_override in ('false', 'f', 'no', 'n', 'off', '0') then false
    end;
  end if;

  if v_mirror is null then
    v_mirror := public.tour_label_is_combined(new.name, new.slug)
      and new.group_broadcast_id is not null
      and exists (
        select 1 from public.tours s
        where s.group_broadcast_id = new.group_broadcast_id
          and s.id <> new.id
          and not public.tour_label_is_combined(s.name, s.slug));
  end if;

  new.is_mirror := v_mirror;

  -- Lichess marks a Combined section as a team table, with each real section
  -- as a "team", and the data hub appends " (team)" to the format. A mirror
  -- is a team event only when one of its real sections is.
  if v_mirror
     and jsonb_typeof(new.info) = 'object'
     and new.info->>'teamTable' = 'true'
     and not exists (
       select 1 from public.tours s
       where s.group_broadcast_id = new.group_broadcast_id
         and s.id <> new.id
         and not public.tour_label_is_combined(s.name, s.slug)
         and s.info->>'teamTable' = 'true') then
    new.info := jsonb_set(new.info, '{teamTable}', 'false'::jsonb);
    if jsonb_typeof(new.info->'format') = 'string' then
      new.info := jsonb_set(new.info, '{format}',
        to_jsonb(regexp_replace(new.info->>'format', '\s*\(team\)\s*$', '', 'i')));
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.tours_set_mirror_flag() from public, anon, authenticated;

drop trigger if exists tours_zzz_mirror_flag on public.tours;
create trigger tours_zzz_mirror_flag
before insert or update on public.tours
for each row execute function public.tours_set_mirror_flag();

-- tours_zzz_mirror_players (20261111194500) fires right after
-- tours_zzz_mirror_flag ("..._flag" < "..._players"), so it can read the
-- computed flag. A mirror tour's players lose their "team" tags.
create or replace function public.tours_mirror_players()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.is_mirror
     and jsonb_typeof(new.players) = 'array'
     and new.players::text like '%"team"%' then
    new.players := (
      select coalesce(jsonb_agg(
        case when jsonb_typeof(e) = 'object' then e - 'team' else e end
        order by ord), '[]'::jsonb)
      from jsonb_array_elements(new.players) with ordinality as x(e, ord)
    );
  end if;
  return new;
end;
$$;

-- A real section joining, leaving or being renamed changes whether its
-- event's Combined sections are mirrors: touch them so the BEFORE trigger
-- recomputes. The touch sets only info, which this trigger does not watch,
-- so it cannot recurse.
create or replace function public.tours_refresh_combined_siblings()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'UPDATE'
     and new.group_broadcast_id is not distinct from old.group_broadcast_id
     and new.name is not distinct from old.name
     and new.slug is not distinct from old.slug then
    return null;
  end if;

  if public.tour_label_is_combined(new.name, new.slug)
     and (tg_op = 'INSERT' or public.tour_label_is_combined(old.name, old.slug)) then
    return null;
  end if;

  update public.tours c
     set info = c.info
   where c.id <> new.id
     and (c.group_broadcast_id = new.group_broadcast_id
          or (tg_op = 'UPDATE' and c.group_broadcast_id = old.group_broadcast_id))
     and public.tour_label_is_combined(c.name, c.slug);

  return null;
end;
$$;

revoke execute on function public.tours_refresh_combined_siblings() from public, anon, authenticated;

drop trigger if exists tours_zzz_refresh_combined_siblings on public.tours;
create trigger tours_zzz_refresh_combined_siblings
after insert or update of group_broadcast_id, name, slug on public.tours
for each row execute function public.tours_refresh_combined_siblings();

-- ---------------------------------------------------------------------------
-- Game flag
-- ---------------------------------------------------------------------------

-- The BEFORE INSERT OR UPDATE trigger games_mark_mirror (from
-- 20261111193000) keeps its name, so it still fires after
-- game_override_trigger and game_round_slug_override_trigger, which may
-- rewrite players or tour_id. Stored generated columns are computed after
-- every BEFORE trigger, so player_fide_ids / player_feds see the marker.
-- A mirror board's players lose "team" (20261111194500). Already-marked rows
-- are left as they are, so live clock writes to a mirror board do not rebuild
-- players each time.
create or replace function public.games_mark_mirror()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  new.is_mirror := coalesce(
    (select t.is_mirror from public.tours t where t.id = new.tour_id), false);

  if jsonb_typeof(new.players) = 'array' then
    if new.is_mirror then
      if exists (
        select 1 from jsonb_array_elements(new.players) e
        where jsonb_typeof(e) = 'object'
          and (e->'mirror' is distinct from 'true'::jsonb or e ? 'team')) then
        new.players := (
          select coalesce(jsonb_agg(case when jsonb_typeof(x.e) = 'object'
            then (x.e - 'team') || '{"mirror": true}'::jsonb else x.e end order by x.ord), '[]'::jsonb)
          from jsonb_array_elements(new.players) with ordinality x(e, ord));
      end if;
    elsif new.players::text like '%"mirror"%' then
      new.players := (
        select coalesce(jsonb_agg(case when jsonb_typeof(x.e) = 'object'
          then x.e - 'mirror' else x.e end order by x.ord), '[]'::jsonb)
        from jsonb_array_elements(new.players) with ordinality x(e, ord));
    end if;
  end if;

  if new.is_mirror then
    new.search := array[]::text[];
  end if;
  return new;
end;
$$;

drop trigger if exists games_mark_mirror on public.games;
create trigger games_mark_mirror
before insert or update on public.games
for each row execute function public.games_mark_mirror();

-- A tour turning into (or out of) a mirror restamps its games, which re-runs
-- games_mark_mirror on each. Only rows that differ are written. A column list
-- would miss this: is_mirror is set by a BEFORE trigger, not by the UPDATE's
-- SET list. Replaces tours_remark_mirror_games, which watched info.mirror only.
create or replace function public.tours_propagate_mirror()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  update public.games g
     set is_mirror = new.is_mirror
   where g.tour_id = new.id
     and g.is_mirror is distinct from new.is_mirror;
  return null;
end;
$$;

revoke execute on function public.tours_propagate_mirror() from public, anon, authenticated;

drop trigger if exists tours_zzz_propagate_mirror on public.tours;
create trigger tours_zzz_propagate_mirror
after update on public.tours
for each row
when (old.is_mirror is distinct from new.is_mirror)
execute function public.tours_propagate_mirror();

drop trigger if exists tours_remark_mirror_games on public.tours;
drop function if exists public.tours_remark_mirror_games();

-- ---------------------------------------------------------------------------
-- Blacklist purge: still reaches mirror boards
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.purge_blacklisted_player_games(p_max_rows integer DEFAULT 500)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_ids        bigint[];
  v_name       text;
  v_candidate  text;
  v_candidates text[] := '{}';
  v_batch      text[];
  v_deleted    integer := 0;
  v_rows       integer := 0;
begin
  select array_agg(fide_id) into v_ids from public.blacklisted_players;
  if v_ids is null then
    return 0;
  end if;

  -- Candidate boards by FIDE id (GIN on player_fide_ids).
  select coalesce(array_agg(s.id), '{}') into v_batch
  from (
    select g.id
    from public.games g
    where g.player_fide_ids && v_ids
    limit p_max_rows
  ) s;
  v_candidates := v_candidates || v_batch;

  -- Mirror boards (a Combined section) carry "mirror": true on every
  -- player, so player_fide_ids is empty for them. Reach them through the
  -- few mirror tours instead.
  select coalesce(array_agg(s.id), '{}') into v_batch
  from (
    select g.id
    from public.games g
    where g.tour_id = any(array(select t.id from public.tours t where t.is_mirror))
      and exists (
        select 1
        from jsonb_array_elements(case when jsonb_typeof(g.players) = 'array'
          then g.players else '[]'::jsonb end) p
        where (p->>'fideId') ~ '^[0-9]+$'
          and (p->>'fideId')::bigint = any(v_ids)
      )
    limit p_max_rows
  ) s;
  v_candidates := v_candidates || v_batch;

  -- Candidate boards by exact listed name where the player entry carries NO
  -- FIDE id (youth events, older imports). GIN on players serves `@>`. An
  -- entry with a different id is never matched by name (namesake).
  for v_name in
    select distinct btrim(player_name)
    from public.blacklisted_players
    where player_name is not null and btrim(player_name) <> ''
  loop
    select coalesce(array_agg(s.id), '{}') into v_batch
    from (
      select g.id
      from public.games g
      where g.players @> jsonb_build_array(jsonb_build_object('name', v_name))
        and exists (
          select 1
          from jsonb_array_elements(g.players) p
          where p->>'name' = v_name
            and not (coalesce(p->>'fideId', '') ~ '^[0-9]+$')
        )
      limit p_max_rows
    ) s;
    v_candidates := v_candidates || v_batch;
  end loop;

  -- One primary-key delete per candidate; only boards that have ended
  -- (terminal status, or silent for 36 hours), never a super-admin pinned
  -- board (its trigger raises on delete).
  foreach v_candidate in array v_candidates loop
    exit when v_deleted >= p_max_rows;

    with deleted as (
      delete from public.games g
      where g.id = v_candidate
        and (
          (g.status is not null and g.status <> '*')
          or coalesce(
               g.last_move_time,
               g.live_observed_at,
               (select r.starts_at from public.rounds r where r.id = g.round_id),
               g.date_start::timestamptz
             ) < now() - interval '36 hours'
        )
        and not exists (
          select 1 from broadcasting_private.game_overrides o where o.game_id = g.id
        )
      returning g.id, g.round_id, g.tour_id, g.status, g.player_fide_ids
    )
    insert into public.blacklisted_player_game_purges (game_id, round_id, tour_id, fide_ids, game_status)
    select id, round_id, tour_id, player_fide_ids, status from deleted;
    get diagnostics v_rows = row_count;
    v_deleted := v_deleted + v_rows;
  end loop;

  -- The player's own streak rows are derived from these games.
  delete from public.player_streak_game  where fide_id = any(v_ids);
  delete from public.player_streak_event where fide_id = any(v_ids);
  delete from public.player_streak       where fide_id = any(v_ids);

  return v_deleted;
end
$function$;

-- ---------------------------------------------------------------------------
-- For You top boards and the sign-in preview
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_for_you_top_games(p_event_ids text[], p_boards_per_event integer DEFAULT 4)
 RETURNS TABLE(event_id text, id text, round_id text, round_slug text, tour_id text, tour_slug text, name text, fen text, pgn text, players jsonb, last_move text, think_time integer, status text, search text[], lichess_id text, player_white text, player_black text, date_start date, time_start time without time zone, board_nr smallint, last_move_time timestamp with time zone, game_day date, last_clock_white real, last_clock_black real, eco text, opening_name text, time_control text, avg_elo smallint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with params as (
    select greatest(1, least(coalesce(p_boards_per_event, 4), 12)) as board_count
  ),
  requested_events as (
    select distinct event_id
    from unnest(coalesce(p_event_ids, '{}'::text[])) as event_id
    where event_id is not null and event_id <> ''
  ),
  eligible_rounds as (
    select
      re.event_id,
      t.id as selected_tour_id,
      t.avg_elo as category_avg_elo,
      r.id as source_round_id,
      coalesce(r.starts_at, r.created_at) as source_round_time,
      rg.has_today
    from requested_events re
    join public.tours t on t.group_broadcast_id = re.event_id
    join public.rounds r on r.tour_id = t.id
    join lateral (
      select
        count(*) as real_game_count,
        bool_or(
          coalesce(g.game_day, g.last_move_time::date, g.date_start) = current_date
        ) as has_today
      from public.games g
      where g.round_id = r.id
        and g.tour_id = t.id
        and not g.is_mirror
        and (
          g.fen is distinct from 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
          or nullif(g.last_move, '') is not null
          or g.last_move_time is not null
          or coalesce(g.pgn, '') ~ '(?m)^1[.]'
        )
        and jsonb_array_length(coalesce(g.players, '[]'::jsonb)) >= 2
        and lower(btrim(coalesce(g.players->0->>'name', ''))) not in ('', '?', '??', 'tbd', 'tba', 'unknown')
        and lower(btrim(coalesce(g.players->1->>'name', ''))) not in ('', '?', '??', 'tbd', 'tba', 'unknown')
    ) rg on true
    where rg.real_game_count > 0
  ),
  today_round_sources as (
    select distinct on (er.event_id)
      er.event_id,
      0 as source_priority,
      er.selected_tour_id,
      er.category_avg_elo,
      er.source_round_id,
      er.source_round_time
    from eligible_rounds er
    where er.has_today
    order by
      er.event_id,
      er.category_avg_elo desc nulls last,
      er.source_round_time desc nulls last,
      er.selected_tour_id,
      er.source_round_id
  ),
  fallback_round_sources as (
    select distinct on (er.event_id)
      er.event_id,
      1 as source_priority,
      er.selected_tour_id,
      er.category_avg_elo,
      er.source_round_id,
      er.source_round_time
    from eligible_rounds er
    where not exists (
      select 1
      from today_round_sources trs
      where trs.event_id = er.event_id
    )
    order by
      er.event_id,
      er.category_avg_elo desc nulls last,
      er.source_round_time desc nulls last,
      er.selected_tour_id,
      er.source_round_id
  ),
  selected_round_sources as (
    select * from today_round_sources
    union all
    select * from fallback_round_sources
  ),
  candidate_games as (
    select
      srs.event_id,
      srs.category_avg_elo,
      g.id,
      g.round_id,
      g.round_slug,
      g.tour_id,
      g.tour_slug,
      g.name,
      g.fen,
      g.pgn,
      g.players,
      g.last_move,
      g.think_time,
      g.status,
      g.search,
      g.lichess_id,
      g.player_white,
      g.player_black,
      g.date_start,
      g.time_start,
      g.board_nr,
      g.last_move_time,
      g.game_day,
      g.last_clock_white,
      g.last_clock_black,
      g.eco,
      g.opening_name,
      gb.time_control,
      t.avg_elo,
      g.player_max_rating,
      row_number() over (
        partition by srs.event_id
        order by
          g.board_nr asc nulls last,
          g.player_max_rating desc nulls last,
          g.date_start desc nulls last,
          g.last_move_time desc nulls last,
          g.id asc
      ) as board_rank
    from selected_round_sources srs
    join public.tours t on t.id = srs.selected_tour_id
    join public.rounds r on r.id = srs.source_round_id
      and r.tour_id = t.id
    join public.games g on g.round_id = r.id and g.tour_id = t.id
    join public.group_broadcasts gb on gb.id = t.group_broadcast_id
    where not g.is_mirror
      and (
        g.fen is distinct from 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
        or nullif(g.last_move, '') is not null
        or g.last_move_time is not null
        or coalesce(g.pgn, '') ~ '(?m)^1[.]'
      )
      and jsonb_array_length(coalesce(g.players, '[]'::jsonb)) >= 2
      and lower(btrim(coalesce(g.players->0->>'name', ''))) not in ('', '?', '??', 'tbd', 'tba', 'unknown')
      and lower(btrim(coalesce(g.players->1->>'name', ''))) not in ('', '?', '??', 'tbd', 'tba', 'unknown')
  )
  select
    top_games.event_id,
    top_games.id,
    top_games.round_id,
    top_games.round_slug,
    top_games.tour_id,
    top_games.tour_slug,
    top_games.name,
    top_games.fen,
    top_games.pgn,
    top_games.players,
    top_games.last_move,
    top_games.think_time,
    top_games.status,
    top_games.search,
    top_games.lichess_id,
    top_games.player_white,
    top_games.player_black,
    top_games.date_start,
    top_games.time_start,
    top_games.board_nr,
    top_games.last_move_time,
    top_games.game_day,
    top_games.last_clock_white,
    top_games.last_clock_black,
    top_games.eco,
    top_games.opening_name,
    top_games.time_control,
    top_games.avg_elo
  from candidate_games top_games
  cross join params p
  where top_games.board_rank <= p.board_count
  order by
    top_games.event_id,
    top_games.board_rank;
$function$;

CREATE OR REPLACE FUNCTION public.signin_preview_events()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with events as materialized (
    select f.ordinality as ordinal, f.*
    from public.get_for_you_group_broadcasts(20,0,null::text[],null::integer,null::integer,null::text[]) with ordinality f
    limit 20
  ), top_games as materialized (
    select g.ordinality as ordinal,
      rewarded_private.signin_preview_public_game(to_jsonb(g) || jsonb_build_object(
        'round_starts_at', r.starts_at, 'round_name', r.name,
        'tour_name', t.name, 'event_name', gb.name, 'time_control_text', t.info->>'tc'
      )) as game,
      g.event_id, g.id
    from public.get_for_you_top_games((select coalesce(array_agg(e.id order by e.ordinal),'{}'::text[]) from events e),12) with ordinality g
    left join public.rounds r on r.id = g.round_id
    left join public.tours t on t.id = g.tour_id
    left join public.group_broadcasts gb on gb.id = g.event_id
  ), bounded_games as materialized (
    select * from (select t.*, row_number() over(partition by t.event_id order by t.ordinal) as board_index
      from top_games t where t.event_id in (select e.id from events e)) b
    where b.board_index <= 12
  ), source_tours as materialized (
    -- TourRepository.getTourByGroupId: group first, raw-tour fallback with
    -- siblings, ordered avg_elo DESC NULLS LAST (PostgREST's default).
    -- The canonical repository specifies no tie-break for equal strengths;
    -- deliberately do not invent a latest-tour/ID preference here.
    select e.id as event_id, t.*
    from events e join public.tours t on t.group_broadcast_id = e.id
    where not t.is_mirror
    union all
    select e.id as event_id, t.*
    from events e join public.tours raw on raw.id = e.id
    join public.tours t on (
      (nullif(btrim(raw.group_broadcast_id),'') is not null
        and t.group_broadcast_id = btrim(raw.group_broadcast_id))
      or (t.id = raw.id and not exists(select 1 from public.tours sibling
        where sibling.group_broadcast_id = nullif(btrim(raw.group_broadcast_id),''))))
    where not exists(select 1 from public.tours direct where direct.group_broadcast_id = e.id)
      and not t.is_mirror
  ), event_tours as materialized (
    select t.*, row_number() over(partition by t.event_id order by t.avg_elo desc nulls last) as tour_ordinal
    from source_tours t
  ), tour_metadata as materialized (
    select t.*,
      nullif(btrim(t.image, U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'), '') as image_url,
      nullif(btrim(t.info->>'location', U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'), '') as event_location
    from event_tours t
  ), roster as materialized (
    -- Rosters stay internal. Only a count and the first tour's majority
    -- federation cross the server-only RPC boundary, never player records.
    select t.event_id, t.tour_ordinal, p.player,
      case
        when jsonb_typeof(p.player->'fideId') = 'number'
          then 'fide:' || trunc((p.player->>'fideId')::numeric)::text
        when jsonb_typeof(p.player->'fideId') = 'string'
          and btrim(p.player->>'fideId') ~ '^[+-]?[0-9]+$'
          then 'fide:' || ((btrim(p.player->>'fideId'))::numeric)::text
        else 'name:' || lower(btrim(coalesce(p.player->>'name',''), U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'))
      end as player_key
    from event_tours t
    cross join lateral jsonb_array_elements(case when jsonb_typeof(t.players) = 'array'
      then t.players else '[]'::jsonb end) p(player)
  ), player_counts as (
    select event_id, count(distinct player_key) filter(where player_key <> 'name:')
      + count(*) filter(where player_key = 'name:') as player_count
    from roster group by event_id
  ), federation_counts as (
    select event_id, player->>'fed' as federation, count(*) as fed_count,
      sum(count(*)) over(partition by event_id) as total_with_fed
    from roster where tour_ordinal = 1 and jsonb_typeof(player->'fed') = 'string'
      and player->>'fed' <> ''
    group by event_id, player->>'fed'
  ), artwork as (
    select e.id, jsonb_build_object(
      'imageUrl', (array_agg(t.image_url order by t.tour_ordinal) filter(where t.image_url is not null))[1],
      'location', regexp_replace((array_agg(t.event_location order by t.tour_ordinal)
        filter(where t.event_location is not null))[1], '\.$', ''),
      'playerCount', coalesce(pc.player_count,0),
      'dominantFederation', (select f.federation from federation_counts f
        where f.event_id = e.id and f.fed_count * 2 > f.total_with_fed)
    ) as data
    from events e left join tour_metadata t on t.event_id = e.id
    left join player_counts pc on pc.event_id = e.id
    group by e.id, pc.player_count
  ), next_rounds as (
    select distinct on(t.event_id) t.event_id,
      jsonb_build_object('name',left(coalesce(r.name,''),256),'startsAt',r.starts_at) as data
    from event_tours t join public.rounds r on r.tour_id = t.id
    where r.starts_at > now() and isfinite(r.starts_at)
      and left(t.event_id,10) <> 'cal_event_'
    order by t.event_id, r.starts_at, t.tour_ordinal, r.created_at
  )
  select jsonb_build_object(
    'schemaVersion', 1, 'dataset', 'for-you', 'generatedAt', now(),
    'artwork', coalesce((select jsonb_object_agg(a.id,a.data) from artwork a),'{}'::jsonb),
    'nextRounds', coalesce((select jsonb_object_agg(n.event_id,n.data) from next_rounds n),'{}'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'created_at',e.created_at,'name',left(e.name,256),
      'max_avg_elo',e.max_avg_elo,'date_start',e.date_start,'date_end',e.date_end,
      'time_control',e.time_control,'date_closest_round',e.date_closest_round
    ) order by e.ordinal) from events e),'[]'::jsonb),
    'games', coalesce((select jsonb_agg(b.game order by b.ordinal) from bounded_games b),'[]'::jsonb),
    'strictLiveEventIds', coalesce((select jsonb_agg(l.group_broadcast_id order by l.group_broadcast_id)
      from public.get_strict_live_group_broadcast_ids(
        (select coalesce(s.live_round_ids,'{}'::text[]) from public.settings s where s.id = 1),7200) l
      where l.group_broadcast_id in (select e.id from events e)), '[]'::jsonb),
    'missingPositionGameIds', coalesce((select jsonb_agg(b.id order by b.ordinal) from bounded_games b
      where nullif(btrim(b.game->>'fen'),'') is null),'[]'::jsonb)
  );
$function$;

-- ---------------------------------------------------------------------------
-- Favorites and countrymen date pickers and per-day lists
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_distinct_dates_for_favorites(fide_ids bigint[], limit_count integer DEFAULT 30, offset_count integer DEFAULT 0, p_status text DEFAULT NULL::text, p_result text DEFAULT NULL::text, p_time_control text DEFAULT NULL::text, p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_min_rating integer DEFAULT NULL::integer, p_max_rating integer DEFAULT NULL::integer, p_eco text DEFAULT NULL::text, p_color text DEFAULT NULL::text)
 RETURNS TABLE(date_start date)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT DISTINCT COALESCE(g.game_day, g.last_move_time::date, g.date_start) AS date_start
  FROM public.games g
  WHERE NOT g.is_mirror
    AND g.player_fide_ids && fide_ids
    AND COALESCE(g.game_day, g.last_move_time::date, g.date_start) IS NOT NULL
    AND COALESCE(g.game_day, g.last_move_time::date, g.date_start) <= CURRENT_DATE
    AND (p_status IS NULL
         OR (p_status = 'live'      AND (g.status IS NULL OR g.status = '*'))
         OR (p_status = 'completed' AND g.status IS NOT NULL AND g.status <> '*'))
    AND (p_result IS NULL
         OR (p_result = '1-0' AND g.status = '1-0')
         OR (p_result = '0-1' AND g.status = '0-1')
         OR (p_result IN ('1/2','1/2-1/2','draw')
             AND g.status IN ('1/2','1/2-1/2','½-½')))
    AND (p_time_control IS NULL
         OR g.tour_slug IN (
              SELECT t.slug
              FROM public.tours t
              JOIN public.group_broadcasts gb ON gb.id = t.group_broadcast_id
              WHERE gb.time_control = p_time_control))
    AND (p_min_year   IS NULL OR EXTRACT(year FROM COALESCE(g.game_day, g.last_move_time::date, g.date_start)) >= p_min_year)
    AND (p_max_year   IS NULL OR EXTRACT(year FROM COALESCE(g.game_day, g.last_move_time::date, g.date_start)) <= p_max_year)
    AND (p_min_rating IS NULL OR g.player_max_rating >= p_min_rating)
    AND (p_max_rating IS NULL OR g.player_max_rating <= p_max_rating)
    AND (p_eco IS NULL OR g.eco ILIKE (p_eco || '%'))
    AND (p_color IS NULL
         OR (p_color = 'white'
             AND (NULLIF(g.players->0->>'fideId',''))::bigint = ANY(fide_ids))
         OR (p_color = 'black'
             AND (NULLIF(g.players->1->>'fideId',''))::bigint = ANY(fide_ids)))
  ORDER BY date_start DESC
  OFFSET offset_count
  LIMIT limit_count;
$function$;

CREATE OR REPLACE FUNCTION public.filter_games_for_favorites_on_date(fide_ids bigint[], target_date date, p_status text DEFAULT NULL::text, p_result text DEFAULT NULL::text, p_time_control text DEFAULT NULL::text, p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_min_rating integer DEFAULT NULL::integer, p_max_rating integer DEFAULT NULL::integer, p_eco text DEFAULT NULL::text, p_color text DEFAULT NULL::text)
 RETURNS SETOF games
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT g.*
  FROM public.games g
  WHERE NOT g.is_mirror
    AND g.player_fide_ids && fide_ids
    AND (g.game_day = target_date
         OR (g.game_day IS NULL
             AND g.last_move_time >= target_date::timestamptz
             AND g.last_move_time <  (target_date + 1)::timestamptz)
         OR (g.game_day IS NULL
             AND g.last_move_time IS NULL
             AND g.date_start = target_date))
    AND (p_status IS NULL
         OR (p_status = 'live'      AND (g.status IS NULL OR g.status = '*'))
         OR (p_status = 'completed' AND g.status IS NOT NULL AND g.status <> '*'))
    AND (p_result IS NULL
         OR (p_result = '1-0' AND g.status = '1-0')
         OR (p_result = '0-1' AND g.status = '0-1')
         OR (p_result IN ('1/2','1/2-1/2','draw')
             AND g.status IN ('1/2','1/2-1/2','½-½')))
    AND (p_time_control IS NULL
         OR g.tour_slug IN (
              SELECT t.slug
              FROM public.tours t
              JOIN public.group_broadcasts gb ON gb.id = t.group_broadcast_id
              WHERE gb.time_control = p_time_control))
    AND (p_min_year   IS NULL OR EXTRACT(year FROM COALESCE(g.game_day, g.last_move_time::date, g.date_start)) >= p_min_year)
    AND (p_max_year   IS NULL OR EXTRACT(year FROM COALESCE(g.game_day, g.last_move_time::date, g.date_start)) <= p_max_year)
    AND (p_min_rating IS NULL OR g.player_max_rating >= p_min_rating)
    AND (p_max_rating IS NULL OR g.player_max_rating <= p_max_rating)
    AND (p_eco IS NULL OR g.eco ILIKE (p_eco || '%'))
    AND (p_color IS NULL
         OR (p_color = 'white'
             AND (NULLIF(g.players->0->>'fideId',''))::bigint = ANY(fide_ids))
         OR (p_color = 'black'
             AND (NULLIF(g.players->1->>'fideId',''))::bigint = ANY(fide_ids)))
  ORDER BY g.last_move_time DESC NULLS LAST;
$function$;

CREATE OR REPLACE FUNCTION public.get_distinct_dates_for_country(country_code text, min_elo integer DEFAULT 0, limit_count integer DEFAULT 30, offset_count integer DEFAULT 0, p_status text DEFAULT NULL::text, p_result text DEFAULT NULL::text, p_time_control text DEFAULT NULL::text, p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_max_rating integer DEFAULT NULL::integer, p_eco text DEFAULT NULL::text, p_color text DEFAULT NULL::text)
 RETURNS TABLE(date_start date)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT DISTINCT COALESCE(g.game_day, g.last_move_time::date, g.date_start) AS date_start
  FROM public.games g
  WHERE NOT g.is_mirror
    AND g.player_feds @> ARRAY[upper(country_code)]
    AND g.player_max_rating >= min_elo
    AND COALESCE(g.game_day, g.last_move_time::date, g.date_start) IS NOT NULL
    AND COALESCE(g.game_day, g.last_move_time::date, g.date_start) <= CURRENT_DATE
    AND (p_status IS NULL
         OR (p_status = 'live'      AND (g.status IS NULL OR g.status = '*'))
         OR (p_status = 'completed' AND g.status IS NOT NULL AND g.status <> '*'))
    AND (p_result IS NULL
         OR (p_result = '1-0' AND g.status = '1-0')
         OR (p_result = '0-1' AND g.status = '0-1')
         OR (p_result IN ('1/2','1/2-1/2','draw')
             AND g.status IN ('1/2','1/2-1/2','½-½')))
    AND (p_time_control IS NULL
         OR g.tour_slug IN (
              SELECT t.slug
              FROM public.tours t
              JOIN public.group_broadcasts gb ON gb.id = t.group_broadcast_id
              WHERE gb.time_control = p_time_control))
    AND (p_min_year   IS NULL OR EXTRACT(year FROM COALESCE(g.game_day, g.last_move_time::date, g.date_start)) >= p_min_year)
    AND (p_max_year   IS NULL OR EXTRACT(year FROM COALESCE(g.game_day, g.last_move_time::date, g.date_start)) <= p_max_year)
    AND (p_max_rating IS NULL OR g.player_max_rating <= p_max_rating)
    AND (p_eco IS NULL OR g.eco ILIKE (p_eco || '%'))
    AND (p_color IS NULL
         OR (p_color = 'white' AND upper(g.players->0->>'fed') = upper(country_code))
         OR (p_color = 'black' AND upper(g.players->1->>'fed') = upper(country_code)))
  ORDER BY date_start DESC
  OFFSET offset_count
  LIMIT limit_count;
$function$;

CREATE OR REPLACE FUNCTION public.filter_games_for_country_on_date(country_code text, target_date date, min_elo integer DEFAULT 0, p_status text DEFAULT NULL::text, p_result text DEFAULT NULL::text, p_time_control text DEFAULT NULL::text, p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_max_rating integer DEFAULT NULL::integer, p_eco text DEFAULT NULL::text, p_color text DEFAULT NULL::text)
 RETURNS SETOF games
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT g.*
  FROM public.games g
  WHERE NOT g.is_mirror
    AND g.player_feds @> ARRAY[upper(country_code)]
    AND g.player_max_rating >= min_elo
    AND (g.game_day = target_date
         OR (g.game_day IS NULL
             AND g.last_move_time >= target_date::timestamptz
             AND g.last_move_time <  (target_date + 1)::timestamptz)
         OR (g.game_day IS NULL
             AND g.last_move_time IS NULL
             AND g.date_start = target_date))
    AND (p_status IS NULL
         OR (p_status = 'live'      AND (g.status IS NULL OR g.status = '*'))
         OR (p_status = 'completed' AND g.status IS NOT NULL AND g.status <> '*'))
    AND (p_result IS NULL
         OR (p_result = '1-0' AND g.status = '1-0')
         OR (p_result = '0-1' AND g.status = '0-1')
         OR (p_result IN ('1/2','1/2-1/2','draw')
             AND g.status IN ('1/2','1/2-1/2','½-½')))
    AND (p_time_control IS NULL
         OR g.tour_slug IN (
              SELECT t.slug
              FROM public.tours t
              JOIN public.group_broadcasts gb ON gb.id = t.group_broadcast_id
              WHERE gb.time_control = p_time_control))
    AND (p_min_year   IS NULL OR EXTRACT(year FROM COALESCE(g.game_day, g.last_move_time::date, g.date_start)) >= p_min_year)
    AND (p_max_year   IS NULL OR EXTRACT(year FROM COALESCE(g.game_day, g.last_move_time::date, g.date_start)) <= p_max_year)
    AND (p_max_rating IS NULL OR g.player_max_rating <= p_max_rating)
    AND (p_eco IS NULL OR g.eco ILIKE (p_eco || '%'))
    AND (p_color IS NULL
         OR (p_color = 'white' AND upper(g.players->0->>'fed') = upper(country_code))
         OR (p_color = 'black' AND upper(g.players->1->>'fed') = upper(country_code)))
  ORDER BY g.last_move_time DESC NULLS LAST;
$function$;

-- ---------------------------------------------------------------------------
-- Smart events: day cursor and digests
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_current_smart_event_day(p_before date DEFAULT NULL::date, p_min_rating integer DEFAULT NULL::integer, p_max_rating integer DEFAULT NULL::integer, p_eco_codes text[] DEFAULT NULL::text[], p_time_controls text[] DEFAULT NULL::text[], p_live_only boolean DEFAULT false, p_completed_only boolean DEFAULT false, p_search text DEFAULT NULL::text, p_results text[] DEFAULT NULL::text[], p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_online boolean DEFAULT NULL::boolean)
 RETURNS date
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  predicates text := 'g.game_day is not null
    and g.game_day <= (now() at time zone ''UTC'')::date
    and exists (select 1 from public.rounds r where r.id = g.round_id
      and (r.starts_at is null or r.starts_at <= now()))
    and not g.is_mirror';
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
$function$;

CREATE OR REPLACE FUNCTION public.smart_event_digest_rows(p_window_end timestamp with time zone DEFAULT date_trunc('hour'::text, now()), p_window interval DEFAULT '04:00:00'::interval)
 RETURNS TABLE(user_id uuid, smart_event_id text, smart_event_name text, label text, min_elo integer, max_elo integer, formats text[], eco_code text, games integer, live_games integer, white_wins integer, black_wins integer, draws integer, top_game_id text, top_white text, top_black text, top_status text, top_average integer, top_opening text, top_event text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.smart_event_digest_rows_since(p_window_end timestamp with time zone, p_user_ids uuid[], p_since timestamp with time zone[])
 RETURNS TABLE(user_id uuid, smart_event_id text, smart_event_name text, label text, min_elo integer, max_elo integer, formats text[], eco_code text, games integer, live_games integer, white_wins integer, black_wins integer, draws integer, top_game_id text, top_white text, top_black text, top_status text, top_average integer, top_opening text, top_event text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;

-- ---------------------------------------------------------------------------
-- Reports and report queues
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.report_games_by_type(p_type text)
 RETURNS SETOF games
 LANGUAGE sql
 STABLE
AS $function$
  select g.* from public.games g
  where not g.is_mirror
    and g.status in ('1-0', '0-1', '1/2-1/2')
    and g.report_game_classification is not null
    and g.report_game_classification @>
      pg_catalog.jsonb_build_object('tags', pg_catalog.jsonb_build_array(p_type))
    -- Result edits can invalidate a story even when the moves/PGN are intact.
    and g.report_game_classification->>'result' = g.status
    and g.report_game_classification->>'pgnHash' = pg_catalog.md5(g.pgn);
$function$;

CREATE OR REPLACE FUNCTION public.report_games_needing_classification(p_version integer)
 RETURNS SETOF games
 LANGUAGE sql
 STABLE
AS $function$
  select g.* from public.games g
  where not g.is_mirror
    and g.status in ('1-0', '0-1', '1/2-1/2')
    and g.pgn like '%[\%eval %'
    and (g.pgn like '%$24%' or g.pgn ilike '%chessever_annotation%')
    and (
      g.report_game_classification->>'version' is distinct from p_version::text
      or g.report_game_classification->>'result' is distinct from g.status
      or g.report_game_classification->>'pgnHash' is distinct from pg_catalog.md5(g.pgn)
    );
$function$;

CREATE OR REPLACE FUNCTION public.report_games_with_current_classification(p_version integer)
 RETURNS SETOF games
 LANGUAGE sql
 STABLE
AS $function$
  select g.* from public.games g
  where not g.is_mirror
    and g.status in ('1-0', '0-1', '1/2-1/2')
    and g.report_game_classification is not null
    and g.report_game_classification->>'version' = p_version::text
    and g.report_game_classification->>'result' = g.status
    and g.report_game_classification->>'pgnHash' = pg_catalog.md5(g.pgn);
$function$;

CREATE OR REPLACE FUNCTION public.report_game_classification_page(p_version integer, p_after text DEFAULT ''::text, p_limit integer DEFAULT 100)
 RETURNS TABLE(id text, pgn text, status text, report_game_classification jsonb, current boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select c.id, c.pgn, c.status, c.report_game_classification,
    coalesce(c.report_game_classification->>'version' = p_version::text
      and c.report_game_classification->>'result' = c.status
      and c.report_game_classification->>'pgnHash' = pg_catalog.md5(c.pgn), false)
  from (
    -- The LIMIT keeps this subquery apart, so the hash runs on one page only.
    select g.id, g.pgn, g.status, g.report_game_classification
    from public.games g
    where g.id > coalesce(p_after, '')
      and not g.is_mirror
      and g.report_game_classification is not null
      and g.status in ('1-0', '0-1', '1/2-1/2')
    order by g.id
    limit least(greatest(coalesce(p_limit, 100), 1), 500)
  ) c
  order by c.id;
$function$;

CREATE OR REPLACE FUNCTION public.get_report_prewarm_candidates(p_since timestamp with time zone DEFAULT (now() - '24:00:00'::interval), p_limit integer DEFAULT 10)
 RETURNS TABLE(game_id text, pgn text, white_rating integer, black_rating integer, average_rating numeric, finished_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with rated_finished_games as (
    select
      g.id as game_id,
      g.pgn,
      (g.players->0->>'rating')::integer as white_rating,
      (g.players->1->>'rating')::integer as black_rating,
      (
        (g.players->0->>'rating')::numeric
        + (g.players->1->>'rating')::numeric
      ) / 2 as average_rating,
      g.last_move_time as finished_at
    from public.games g
    where not g.is_mirror
      and public.is_game_finished(g.status)
      and g.last_move_time >= coalesce(p_since, now() - interval '24 hours')
      and coalesce(g.pgn, '') ~ '(?m)^1[.]'
      -- Already reported: the writeback left our class NAGs in the moves.
      and g.pgn !~ '\$24[0-7]([^0-9]|$)'
      and jsonb_typeof(g.players) = 'array'
      and jsonb_array_length(g.players) >= 2
      and g.players->0->>'rating' ~ '^[0-9]+$'
      and g.players->1->>'rating' ~ '^[0-9]+$'
      and (g.players->0->>'rating')::integer between 1 and 4000
      and (g.players->1->>'rating')::integer between 1 and 4000
  )
  select
    candidate.game_id,
    candidate.pgn,
    candidate.white_rating,
    candidate.black_rating,
    candidate.average_rating,
    candidate.finished_at
  from rated_finished_games candidate
  order by
    candidate.average_rating desc,
    candidate.finished_at desc,
    candidate.game_id
  limit greatest(1, least(coalesce(p_limit, 10), 500));
$function$;

-- ---------------------------------------------------------------------------
-- Player streaks
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.player_streak_candidate_games(p_fide_id bigint, p_since date DEFAULT NULL::date)
 RETURNS TABLE(game_id text, fingerprint text, game_day date, sort_at timestamp with time zone, color text, result text, status text, player_name text, player_rating integer, opponent_fide_id bigint, opponent_name text, opponent_title text, opponent_fed text, opponent_rating integer, tour_id text, tour_name text, round_id text, round_name text, round_starts_at timestamp with time zone, group_broadcast_id text, group_broadcast_name text, time_control text, time_start time without time zone, last_move_time timestamp with time zone, live_ply_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH raw AS (
    SELECT
      g.id,
      g.game_day,
      g.status,
      g.time_start,
      g.last_move_time,
      g.live_ply_count,
      g.tour_id,
      g.round_id,
      player_streak_fide(g.players -> 0 -> 'fideId') AS white_fide,
      player_streak_fide(g.players -> 1 -> 'fideId') AS black_fide,
      g.players -> 0 AS white_p,
      g.players -> 1 AS black_p
    FROM games g
    WHERE NOT g.is_mirror
      AND g.player_fide_ids @> ARRAY[p_fide_id]
      AND g.status IN ('1-0', '0-1')
      AND g.game_day IS NOT NULL
      AND g.game_day <= current_date
      AND (p_since IS NULL OR g.game_day >= p_since)
      AND (g.last_move_time IS NULL OR g.last_move_time < now() - interval '15 minutes')
      AND jsonb_typeof(g.players) = 'array'
      AND jsonb_array_length(g.players) >= 2
  ), sided AS (
    SELECT r.*,
      CASE WHEN r.white_fide = p_fide_id THEN 'white'
           WHEN r.black_fide = p_fide_id THEN 'black' END AS color
    FROM raw r
    WHERE r.white_fide IS DISTINCT FROM r.black_fide
  ), scored AS (
    SELECT s.*,
      CASE WHEN (s.color = 'white' AND s.status = '1-0') OR (s.color = 'black' AND s.status = '0-1')
           THEN 'win' ELSE 'loss' END AS result,
      CASE WHEN s.color = 'white' THEN s.white_p ELSE s.black_p END AS me_p,
      CASE WHEN s.color = 'white' THEN s.black_p ELSE s.white_p END AS opp_p,
      CASE WHEN s.color = 'white' THEN s.black_fide ELSE s.white_fide END AS opp_fide
    FROM sided s
    WHERE s.color IS NOT NULL
  ), joined AS (
    SELECT sc.*,
      r.name AS round_name,
      r.starts_at AS round_starts_at,
      t.name AS tour_name,
      t.group_broadcast_id,
      gb.name AS group_broadcast_name,
      gb.time_control
    FROM scored sc
    LEFT JOIN rounds r ON r.id = sc.round_id
    LEFT JOIN tours t ON t.id = sc.tour_id
    LEFT JOIN group_broadcasts gb ON gb.id = t.group_broadcast_id
    WHERE NOT player_streak_is_online(t.name, gb.name, t.info ->> 'location', t.info ->> 'website')
  ), fingerprinted AS (
    SELECT j.*,
      concat_ws('|',
        COALESCE(j.white_fide::text, lower(COALESCE(j.white_p ->> 'name', ''))),
        COALESCE(j.black_fide::text, lower(COALESCE(j.black_p ->> 'name', ''))),
        j.game_day::text,
        j.status,
        COALESCE(j.live_ply_count::text, '')
      ) AS fingerprint,
      player_streak_sort_at(j.game_day, j.time_start, j.round_starts_at, j.last_move_time) AS sort_at
    FROM joined j
  ), deduped AS (
    SELECT DISTINCT ON (f.fingerprint) f.*
    FROM fingerprinted f
    ORDER BY f.fingerprint, f.last_move_time NULLS LAST, f.id
  )
  SELECT
    d.id AS game_id,
    d.fingerprint,
    d.game_day,
    d.sort_at,
    d.color,
    d.result,
    d.status,
    d.me_p ->> 'name' AS player_name,
    NULLIF(d.me_p ->> 'rating', '')::integer AS player_rating,
    d.opp_fide AS opponent_fide_id,
    d.opp_p ->> 'name' AS opponent_name,
    d.opp_p ->> 'title' AS opponent_title,
    d.opp_p ->> 'fed' AS opponent_fed,
    NULLIF(d.opp_p ->> 'rating', '')::integer AS opponent_rating,
    d.tour_id,
    d.tour_name,
    d.round_id,
    d.round_name,
    d.round_starts_at,
    d.group_broadcast_id,
    d.group_broadcast_name,
    d.time_control,
    d.time_start,
    d.last_move_time,
    d.live_ply_count
  FROM deduped d
$function$;

CREATE OR REPLACE FUNCTION public.streaks_apply_recent(p_days integer DEFAULT 2, p_max_rows integer DEFAULT 300)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_started     timestamptz := clock_timestamp();
  v_since       date := current_date - GREATEST(1, LEAST(COALESCE(p_days, 2), 30));
  v_max         integer := GREATEST(1, LEAST(COALESCE(p_max_rows, 300), 2000));
  v_candidates  integer := 0;
  v_inserted    integer := 0;
  v_remaining   integer := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('player_streak_apply')) THEN
    RETURN jsonb_build_object('skipped', 'locked');
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS _streak_apply_candidates (
    fide_id bigint, game_id text, fingerprint text, game_day date, sort_at timestamptz,
    color text, result text, status text, player_name text, player_rating integer,
    opponent_fide_id bigint, opponent_name text, opponent_title text, opponent_fed text,
    opponent_rating integer, tour_id text, tour_name text, round_id text, round_name text,
    round_starts_at timestamptz, group_broadcast_id text, group_broadcast_name text,
    time_control text, time_start time, last_move_time timestamptz, live_ply_count integer
  ) ON COMMIT DROP;
  TRUNCATE _streak_apply_candidates;

  INSERT INTO _streak_apply_candidates
  WITH win AS (
    SELECT g.id, g.game_day, g.status, g.time_start, g.last_move_time, g.live_ply_count,
           g.tour_id, g.round_id,
           player_streak_fide(g.players -> 0 -> 'fideId') AS white_fide,
           player_streak_fide(g.players -> 1 -> 'fideId') AS black_fide,
           g.players -> 0 AS white_p,
           g.players -> 1 AS black_p
    FROM games g
    WHERE NOT g.is_mirror
      AND g.game_day >= v_since
      AND g.game_day <= current_date
      AND g.status IN ('1-0', '0-1')
      AND (g.last_move_time IS NULL OR g.last_move_time < now() - interval '15 minutes')
      AND jsonb_typeof(g.players) = 'array'
      AND jsonb_array_length(g.players) >= 2
  ), sided AS (
    SELECT w.*, side.color, side.fide_id
    FROM win w
    CROSS JOIN LATERAL (VALUES ('white', w.white_fide), ('black', w.black_fide)) AS side(color, fide_id)
    JOIN player_streak ps ON ps.fide_id = side.fide_id
    WHERE w.white_fide IS DISTINCT FROM w.black_fide
      AND side.fide_id IS NOT NULL
      AND ps.seeded_at IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM player_streak_game l WHERE l.fide_id = side.fide_id AND l.game_id = w.id
      )
  ), scored AS (
    SELECT s.*,
      CASE WHEN (s.color = 'white' AND s.status = '1-0') OR (s.color = 'black' AND s.status = '0-1')
           THEN 'win' ELSE 'loss' END AS result,
      CASE WHEN s.color = 'white' THEN s.white_p ELSE s.black_p END AS me_p,
      CASE WHEN s.color = 'white' THEN s.black_p ELSE s.white_p END AS opp_p,
      CASE WHEN s.color = 'white' THEN s.black_fide ELSE s.white_fide END AS opp_fide
    FROM sided s
  ), joined AS (
    SELECT sc.*,
      r.name AS round_name,
      r.starts_at AS round_starts_at,
      t.name AS tour_name,
      t.group_broadcast_id,
      gb.name AS group_broadcast_name,
      gb.time_control
    FROM scored sc
    LEFT JOIN rounds r ON r.id = sc.round_id
    LEFT JOIN tours t ON t.id = sc.tour_id
    LEFT JOIN group_broadcasts gb ON gb.id = t.group_broadcast_id
    WHERE NOT player_streak_is_online(t.name, gb.name, t.info ->> 'location', t.info ->> 'website')
  ), fingerprinted AS (
    SELECT j.*,
      concat_ws('|',
        COALESCE(j.white_fide::text, lower(COALESCE(j.white_p ->> 'name', ''))),
        COALESCE(j.black_fide::text, lower(COALESCE(j.black_p ->> 'name', ''))),
        j.game_day::text,
        j.status,
        COALESCE(j.live_ply_count::text, '')
      ) AS fingerprint,
      player_streak_sort_at(j.game_day, j.time_start, j.round_starts_at, j.last_move_time) AS sort_at
    FROM joined j
  ), deduped AS (
    SELECT DISTINCT ON (f.fide_id, f.fingerprint) f.*
    FROM fingerprinted f
    ORDER BY f.fide_id, f.fingerprint, f.last_move_time NULLS LAST, f.id
  )
  SELECT
    d.fide_id, d.id, d.fingerprint, d.game_day, d.sort_at, d.color, d.result, d.status,
    d.me_p ->> 'name', NULLIF(d.me_p ->> 'rating', '')::integer,
    d.opp_fide, d.opp_p ->> 'name', d.opp_p ->> 'title', d.opp_p ->> 'fed',
    NULLIF(d.opp_p ->> 'rating', '')::integer,
    d.tour_id, d.tour_name, d.round_id, d.round_name, d.round_starts_at,
    d.group_broadcast_id, d.group_broadcast_name, d.time_control,
    d.time_start, d.last_move_time, d.live_ply_count
  FROM deduped d
  JOIN player_streak ps ON ps.fide_id = d.fide_id
  -- A game older than the anchor loss can never change the streak. A player
  -- with no anchor yet takes everything, so their first loss anchors.
  WHERE ps.anchor_loss_game_id IS NULL
     OR (d.game_day, d.sort_at, d.id) >= (ps.anchor_loss_game_day, ps.anchor_loss_sort_at, ps.anchor_loss_game_id);
  GET DIAGNOSTICS v_candidates = ROW_COUNT;

  INSERT INTO player_streak_game (
    fide_id, game_id, fingerprint, game_day, sort_at, color, result, status,
    player_name, player_rating, opponent_fide_id, opponent_name, opponent_title,
    opponent_fed, opponent_rating, tour_id, tour_name, round_id, round_name,
    round_starts_at, group_broadcast_id, group_broadcast_name, time_control,
    time_start, last_move_time, live_ply_count, seeded
  )
  SELECT
    c.fide_id, c.game_id, c.fingerprint, c.game_day, c.sort_at, c.color, c.result, c.status,
    c.player_name, c.player_rating, c.opponent_fide_id, c.opponent_name, c.opponent_title,
    c.opponent_fed, c.opponent_rating, c.tour_id, c.tour_name, c.round_id, c.round_name,
    c.round_starts_at, c.group_broadcast_id, c.group_broadcast_name, c.time_control,
    c.time_start, c.last_move_time, c.live_ply_count, false
  FROM _streak_apply_candidates c
  -- A rebroadcast copy of a game already recorded under another id is not new.
  WHERE NOT EXISTS (
    SELECT 1 FROM player_streak_game l WHERE l.fide_id = c.fide_id AND l.fingerprint = c.fingerprint
  )
  ORDER BY c.fide_id, c.game_day, c.sort_at, c.game_id
  LIMIT v_max
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  SELECT count(*) INTO v_remaining
  FROM _streak_apply_candidates c
  WHERE NOT EXISTS (
    SELECT 1 FROM player_streak_game l
    WHERE l.fide_id = c.fide_id AND (l.game_id = c.game_id OR l.fingerprint = c.fingerprint)
  );

  INSERT INTO player_streak_run (scope, step, started_at, finished_at, summary)
  VALUES ('apply', 'apply_recent', v_started, clock_timestamp(),
          jsonb_build_object('since', v_since, 'candidates', v_candidates, 'inserted', v_inserted, 'remaining', v_remaining));

  RETURN jsonb_build_object(
    'since', v_since,
    'candidates', v_candidates,
    'inserted', v_inserted,
    'remaining', v_remaining,
    'ms', round(extract(epoch FROM clock_timestamp() - v_started) * 1000)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.streaks_reconcile_recent(p_days integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_started   timestamptz := clock_timestamp();
  v_since     date := current_date - GREATEST(1, LEAST(COALESCE(p_days, 3), 30));
  v_flipped   integer := 0;
  v_repointed integer := 0;
  v_removed   integer := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('player_streak_reconcile')) THEN
    RETURN jsonb_build_object('skipped', 'locked');
  END IF;

  -- Reconcile the retained ledger, including corrections to old game dates.
  -- The ledger is small and indexed; game-day windows miss late corrections.
  DROP TABLE IF EXISTS pg_temp._streak_sources;
  CREATE TEMP TABLE _streak_sources ON COMMIT DROP AS
  SELECT l.id, l.fide_id, g.id AS game_id, g.status, g.game_day,
         g.time_start, g.last_move_time, g.live_ply_count,
         player_streak_sort_at(g.game_day, g.time_start, r.starts_at, g.last_move_time) AS sort_at,
         player_streak_fide(g.players -> 0 -> 'fideId') AS white_fide,
         player_streak_fide(g.players -> 1 -> 'fideId') AS black_fide,
         g.players -> 0 AS white_p, g.players -> 1 AS black_p,
         player_streak_is_online(t.name, gb.name, t.info ->> 'location', t.info ->> 'website') AS online
  FROM player_streak_game l
  LEFT JOIN games g ON g.id = l.game_id AND NOT g.is_mirror
  LEFT JOIN rounds r ON r.id = g.round_id
  LEFT JOIN tours t ON t.id = g.tour_id
  LEFT JOIN group_broadcasts gb ON gb.id = t.group_broadcast_id
  WHERE g.last_move_time IS NULL OR g.last_move_time < now() - interval '15 minutes';

  -- Identity corrections must also revisit the actual participant's coverage.
  UPDATE player_streak SET coverage_checked_at = NULL
  WHERE fide_id IN (
    SELECT unnest(ARRAY[s.fide_id,s.white_fide,s.black_fide])
    FROM _streak_sources s
    WHERE NOT COALESCE(s.fide_id IN (s.white_fide,s.black_fide), false)
  );

  DROP TABLE IF EXISTS pg_temp._streak_corrections;
  CREATE TEMP TABLE _streak_corrections ON COMMIT DROP AS
  SELECT s.id, s.fide_id, s.game_id, s.status, s.game_day, s.sort_at, s.live_ply_count,
         CASE WHEN s.white_fide = s.fide_id THEN 'white' ELSE 'black' END AS color,
         CASE WHEN (s.white_fide = s.fide_id AND s.status = '1-0')
                OR (s.black_fide = s.fide_id AND s.status = '0-1') THEN 'win' ELSE 'loss' END AS result,
         CASE WHEN s.white_fide = s.fide_id THEN s.white_p ELSE s.black_p END AS me_p,
         CASE WHEN s.white_fide = s.fide_id THEN s.black_p ELSE s.white_p END AS opp_p,
         CASE WHEN s.white_fide = s.fide_id THEN s.black_fide ELSE s.white_fide END AS opponent_fide_id,
         concat_ws('|', COALESCE(s.white_fide::text, lower(COALESCE(s.white_p ->> 'name', ''))),
           COALESCE(s.black_fide::text, lower(COALESCE(s.black_p ->> 'name', ''))),
           s.game_day::text, s.status, COALESCE(s.live_ply_count::text, '')) AS fingerprint
  FROM _streak_sources s
  WHERE s.status IN ('1-0', '0-1') AND s.game_day IS NOT NULL AND s.game_day <= current_date
    AND s.fide_id IN (s.white_fide,s.black_fide)
    AND s.white_fide IS DISTINCT FROM s.black_fide AND NOT s.online;

  -- Two corrected copies may converge on the same fingerprint.
  DELETE FROM player_streak_game l USING _streak_corrections c
  WHERE l.id = c.id AND EXISTS (
    SELECT 1 FROM _streak_corrections other
    WHERE other.fide_id = c.fide_id AND other.fingerprint = c.fingerprint AND other.id < c.id
  );

  -- A corrected copy may now match a game already retained. Keep one row.
  DELETE FROM player_streak_game l USING _streak_corrections c
  WHERE l.id = c.id AND EXISTS (
    SELECT 1 FROM player_streak_game other
    WHERE other.fide_id = l.fide_id AND other.fingerprint = c.fingerprint AND other.id <> l.id
  );

  WITH upd AS (
    UPDATE player_streak_game l
    SET status = c.status, color = c.color,
        result = c.result,
        game_day = c.game_day, sort_at = c.sort_at, fingerprint = c.fingerprint,
        live_ply_count = c.live_ply_count,
        player_name = c.me_p ->> 'name', player_rating = NULLIF(c.me_p ->> 'rating', '')::integer,
        opponent_rating = NULLIF(c.opp_p ->> 'rating', '')::integer, opponent_fide_id = c.opponent_fide_id,
        opponent_name = c.opp_p ->> 'name', opponent_title = c.opp_p ->> 'title',
        opponent_fed = c.opp_p ->> 'fed', updated_at = now()
    FROM _streak_corrections c
    WHERE l.id = c.id AND (l.status,l.color,l.result,l.game_day,l.sort_at,l.fingerprint,l.live_ply_count,l.player_name,l.opponent_fide_id,l.opponent_name,l.opponent_title,l.opponent_fed,l.player_rating,l.opponent_rating)
      IS DISTINCT FROM (c.status,c.color,c.result,c.game_day,c.sort_at,c.fingerprint,c.live_ply_count,c.me_p ->> 'name',c.opponent_fide_id,c.opp_p ->> 'name',c.opp_p ->> 'title',c.opp_p ->> 'fed',NULLIF(c.me_p ->> 'rating', '')::integer,NULLIF(c.opp_p ->> 'rating', '')::integer)
    RETURNING l.fide_id
  ), dirty AS (
    UPDATE player_streak SET coverage_checked_at = NULL
    WHERE fide_id IN (SELECT fide_id FROM upd)
  ) SELECT count(*) INTO v_flipped FROM upd;

  -- Vanished games: prefer re-pointing the row at an equivalent copy (the
  -- same OTB game carried by another tour) so a deleted duplicate broadcast
  -- is a no-op instead of a removal followed by a re-add.
  WITH gone AS (
    SELECT l.id, l.fide_id, l.game_day, l.fingerprint
    FROM player_streak_game l
    LEFT JOIN games g ON g.id = l.game_id AND NOT g.is_mirror
    WHERE g.id IS NULL
  ), repl AS (
    SELECT gone.id, c.game_id, c.tour_id, c.tour_name, c.round_id, c.round_name,
           c.round_starts_at, c.group_broadcast_id, c.group_broadcast_name, c.time_control
    FROM gone
    CROSS JOIN LATERAL player_streak_candidate_games(gone.fide_id, gone.game_day) c
    WHERE c.fingerprint = gone.fingerprint
  ), upd AS (
    UPDATE player_streak_game l
    SET game_id = repl.game_id, tour_id = repl.tour_id, tour_name = repl.tour_name,
        round_id = repl.round_id, round_name = repl.round_name,
        round_starts_at = repl.round_starts_at, group_broadcast_id = repl.group_broadcast_id,
        group_broadcast_name = repl.group_broadcast_name, time_control = repl.time_control,
        updated_at = now()
    FROM repl
    WHERE l.id = repl.id
      AND NOT EXISTS (SELECT 1 FROM player_streak_game x WHERE x.fide_id = l.fide_id AND x.game_id = repl.game_id)
    RETURNING 1
  )
  SELECT count(*) INTO v_repointed FROM upd;

  -- A corrected FIDE ID must not leave a win/loss on the former player.
  -- Eligibility changes (online event, invalid date, non-decisive result) also
  -- withdraw the row, after the same finality delay used for new games.
  WITH gone AS (
    SELECT s.id
    FROM _streak_sources s
    WHERE s.game_id IS NULL OR s.status IS NULL OR s.status NOT IN ('1-0', '0-1')
      OR s.game_day IS NULL OR s.game_day > current_date
      OR NOT COALESCE(s.fide_id IN (s.white_fide,s.black_fide), false)
      OR s.white_fide IS NOT DISTINCT FROM s.black_fide OR s.online
  ), del AS (
    DELETE FROM player_streak_game l
    USING gone
    WHERE l.id = gone.id
      AND NOT EXISTS (SELECT 1 FROM _streak_sources s WHERE s.id = l.id AND s.game_id IS NULL
        AND EXISTS (SELECT 1 FROM games g WHERE g.id = l.game_id))
    RETURNING l.fide_id
  ), dirty AS (
    UPDATE player_streak SET coverage_checked_at = NULL
    WHERE fide_id IN (SELECT fide_id FROM del)
  )
  SELECT count(*) INTO v_removed FROM del;

  INSERT INTO player_streak_run (scope, step, started_at, finished_at, summary)
  VALUES ('reconcile', 'reconcile_recent', v_started, clock_timestamp(),
          jsonb_build_object('since', v_since, 'flipped', v_flipped, 'repointed', v_repointed, 'removed', v_removed));

  RETURN jsonb_build_object(
    'since', v_since,
    'flipped', v_flipped,
    'repointed', v_repointed,
    'removed', v_removed,
    'ms', round(extract(epoch FROM clock_timestamp() - v_started) * 1000)
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Chat cross-event tools
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.chat_list_live_games(p_time_controls text[] DEFAULT '{}'::text[], p_min_elo integer DEFAULT NULL::integer, p_max_elo integer DEFAULT NULL::integer, p_limit integer DEFAULT 30)
 RETURNS TABLE(event_type text, id text, name text, white_name text, black_name text, status text, board_nr smallint, last_move text, last_move_time timestamp with time zone, round_id text, tour_id text, event_id text, event_name text, time_control text, max_avg_elo smallint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 30), 1), 60);
begin
  if not public.chat_is_signed_in_user() then
    raise exception 'signed-in user required' using errcode = '42501';
  end if;
  if p_min_elo is not null and p_max_elo is not null and p_min_elo > p_max_elo then
    raise exception 'invalid Elo range' using errcode = '22023';
  end if;

  return query
  with requested_time_controls as materialized (
    select distinct case
      when lower(btrim(value)) in ('standard', 'classical') then 'classical'
      when lower(btrim(value)) = 'rapid' then 'rapid'
      when lower(btrim(value)) in ('blitz', 'bullet') then 'blitz'
    end as bucket
    from unnest(coalesce(p_time_controls, '{}'::text[])) value
  ),
  selected_time_controls as materialized (
    select rtc.bucket from requested_time_controls rtc where rtc.bucket is not null
  ),
  configured_live_rounds as materialized (
    select r.id, r.tour_id, r.starts_at
    from public.settings s
    cross join lateral unnest(coalesce(s.live_round_ids, '{}'::text[])) configured(round_id)
    join public.rounds r on r.id = configured.round_id
    where s.id = 1
  ),
  latest_round_activity as materialized (
    select g.round_id, max(g.last_move_time) as last_move_time
    from public.games g
    join configured_live_rounds configured on configured.id = g.round_id
    where g.last_move_time is not null
    group by g.round_id
  ),
  strict_live_rounds as materialized (
    select configured.id, configured.tour_id
    from configured_live_rounds configured
    left join latest_round_activity activity on activity.round_id = configured.id
    where now() <= coalesce(activity.last_move_time, configured.starts_at)
      + pg_catalog.make_interval(secs => 7200)
  ),
  candidates as (
    select
      g.*,
      gb.id as current_event_id,
      gb.name as current_event_name,
      gb.time_control as event_time_control,
      gb.max_avg_elo as event_max_avg_elo,
      case
        when lower(btrim(gb.time_control)) in ('standard', 'classical') then 'classical'
        when lower(btrim(gb.time_control)) = 'rapid' then 'rapid'
        when lower(btrim(gb.time_control)) in ('blitz', 'bullet') then 'blitz'
      end as time_control_bucket
    from strict_live_rounds live_round
    join public.tours t on t.id = live_round.tour_id
    join public.group_broadcasts_current gb on gb.id = t.group_broadcast_id
    join public.games g on g.round_id = live_round.id and g.tour_id = live_round.tour_id
    where lower(btrim(coalesce(g.status, ''))) in ('*', 'ongoing', 'live')
      and not g.is_mirror
      and public.chat_tour_is_visible(g.tour_id)
  )
  select
    'game'::text,
    candidate.id,
    coalesce(
      nullif(btrim(candidate.name), ''),
      concat_ws(' vs ', candidate.player_white, candidate.player_black)
    ),
    candidate.player_white,
    candidate.player_black,
    candidate.status,
    candidate.board_nr,
    candidate.last_move,
    candidate.last_move_time,
    candidate.round_id,
    candidate.tour_id,
    candidate.current_event_id,
    candidate.current_event_name,
    candidate.event_time_control,
    candidate.event_max_avg_elo
  from candidates candidate
  where (
      (select count(*) from selected_time_controls) in (0, 3)
      or candidate.time_control_bucket in (select selected.bucket from selected_time_controls selected)
    )
    and (p_min_elo is null or candidate.event_max_avg_elo is null or candidate.event_max_avg_elo >= p_min_elo)
    and (p_max_elo is null or candidate.event_max_avg_elo is null or candidate.event_max_avg_elo <= p_max_elo)
  order by
    candidate.event_max_avg_elo desc nulls last,
    candidate.current_event_name,
    candidate.last_move_time desc nulls last,
    candidate.board_nr nulls last,
    candidate.id
  limit v_limit;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chat_search_openings(p_query text, p_limit integer DEFAULT 8)
 RETURNS TABLE(event_type text, event_id text, name text, eco text, games_recorded bigint, sample_game_id text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_query text := nullif(btrim(coalesce(p_query, '')), '');
  v_limit integer := least(greatest(coalesce(p_limit, 8), 1), 12);
begin
  if not public.chat_is_signed_in_user() then
    raise exception 'signed-in user required' using errcode = '42501';
  end if;
  if v_query is null or char_length(v_query) > 120 then
    raise exception 'invalid search query' using errcode = '22023';
  end if;

  return query
  with matches as (
    select
      upper(g.eco) as eco,
      g.opening_name,
      count(*) as games_recorded,
      (array_agg(g.id order by g.last_move_time desc nulls last, g.id))[1]
        as sample_game_id,
      max(
        case
          when upper(g.eco) = upper(v_query) then 100.0
          when lower(g.opening_name) = lower(v_query) then 95.0
          when lower(g.opening_name) like lower(v_query) || '%' then 80.0
          when lower(g.opening_name) like '%' || lower(v_query) || '%' then 60.0
          else extensions.similarity(lower(g.opening_name), lower(v_query)) * 50
        end
      ) as score
    from public.games g
    where not g.is_mirror
      and g.eco is not null
      and g.opening_name is not null
      and public.chat_tour_is_visible(g.tour_id)
      and (
        upper(g.eco) = upper(v_query)
        or lower(g.opening_name) like '%' || lower(v_query) || '%'
        or lower(g.opening_name) operator(extensions.%) lower(v_query)
      )
    group by upper(g.eco), g.opening_name
  )
  select
    'opening'::text,
    matches.eco,
    matches.opening_name,
    matches.eco,
    matches.games_recorded,
    matches.sample_game_id
  from matches
  order by matches.score desc, matches.games_recorded desc, matches.eco
  limit v_limit;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Admin tournament automation
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.chessever_admin_tournaments(operation text, input jsonb DEFAULT '{}'::jsonb, actor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
 s admin_portal.tournament_settings%rowtype; e admin_portal.tournament_events%rowtype;
 o record; t record; r record; c text; k text; result jsonb; custom jsonb;
 v integer; next_category_since jsonb; next_tour_since jsonb; earliest timestamptz;
 cid uuid; q text; p integer; minimum_elo integer; typ text; route text;
 suppressed boolean=false; first_round boolean;
begin
 if operation in ('settings','save','tournaments') then
  if actor is null or not exists(select 1 from auth.users where id=actor
   and jsonb_typeof(raw_app_meta_data->'broadcast_scopes')='array'
   and raw_app_meta_data->'broadcast_scopes' ? 'broadcast:admin') then
   raise exception 'Admin access denied' using errcode='42501';
  end if;
 end if;
 -- All paths take settings before events/campaigns, so save cannot race acceptance.
 if operation='save' then
  select * into s from admin_portal.tournament_settings where singleton for update;
 else
  select * into s from admin_portal.tournament_settings where singleton for share;
 end if;
 if operation='settings' then return s.value;
 elsif operation='tournaments' then
  q=coalesce(input->>'search','');p=coalesce((input->>'page')::integer,0);
  if input ? 'minAvgElo' and (jsonb_typeof(input->'minAvgElo') is distinct from 'number' or (input->>'minAvgElo') !~ '^[0-9]{1,4}$') then
   raise exception 'Minimum Avg Elo must be a whole number from 0 to 4000' using errcode='22023'; end if;
  minimum_elo=coalesce((input->>'minAvgElo')::integer,(s.value->>'minAvgElo')::integer,2500);
  if minimum_elo not between 0 and 4000 then raise exception 'Minimum Avg Elo must be a whole number from 0 to 4000' using errcode='22023'; end if;

  if length(q)>200 or p<0 or p>100000 then raise exception 'Invalid tournament search' using errcode='22023'; end if;
  select jsonb_build_object('total',count(*)) into result from public.tours t
   left join public.group_broadcasts g on g.id=t.group_broadcast_id
   where (position(lower(q) in lower(t.id||' '||coalesce(t.name,'')||' '||coalesce(g.name,'')))>0 or q='')
   and (minimum_elo=0 or t.avg_elo>=minimum_elo);
  return result||jsonb_build_object('items',coalesce((select jsonb_agg(x) from (
   select t.id,t.name,t.avg_elo as "avgElo",coalesce(g.name,t.name) as "eventName",coalesce(t.dates,'{}') as dates,
    admin_portal.tournament_round_count(t.info) is not null as "hasRoundCount"
   from public.tours t left join public.group_broadcasts g on g.id=t.group_broadcast_id
   where (position(lower(q) in lower(t.id||' '||coalesce(t.name,'')||' '||coalesce(g.name,'')))>0 or q='')
   and (minimum_elo=0 or t.avg_elo>=minimum_elo)
   order by (select max(d) from unnest(t.dates) d) desc nulls last,t.id limit 50 offset p*50
  )x),'[]'));
 elsif operation='save' then
  input=jsonb_set(input,'{minAvgElo}',coalesce(input->'minAvgElo',s.value->'minAvgElo','2500'::jsonb));
  if jsonb_typeof(input->'minAvgElo') is distinct from 'number' or (input->>'minAvgElo') !~ '^[0-9]{1,4}$' then
   raise exception 'Minimum Avg Elo must be a whole number from 0 to 4000' using errcode='22023'; end if;
  if (input->>'minAvgElo')::integer>4000 then
   raise exception 'Minimum Avg Elo must be a whole number from 0 to 4000' using errcode='22023'; end if;
  v=(s.value->>'version')::integer;
  if (input->>'version')::integer is distinct from v then
   raise exception 'Someone changed tournament settings. Reload and apply your changes again.' using errcode='40001';
  end if;
  if jsonb_typeof(input->'enabled') is distinct from 'boolean'
   or jsonb_typeof(input->'ignorePushDisabled') is distinct from 'boolean'
   or jsonb_typeof(input->'excludedTourIds') is distinct from 'array'
   or jsonb_typeof(input->'categories') is distinct from 'object' then
   raise exception 'Invalid tournament settings' using errcode='22023'; end if;
  if jsonb_array_length(input->'excludedTourIds')>10000 or exists(select 1 from jsonb_array_elements(input->'excludedTourIds') id
    where jsonb_typeof(id)<>'string' or length(id#>>'{}') not between 1 and 120) then
   raise exception 'Invalid tournament exclusions' using errcode='22023'; end if;
  next_category_since=s.category_since;next_tour_since=s.tour_since;
  foreach c in array array['tournament_started','round_started','tournament_ended','round_ended'] loop
   custom=input->'categories'->c;
   if jsonb_typeof(custom->'enabled') is distinct from 'boolean'
    or jsonb_typeof(custom->'title') is distinct from 'string' or jsonb_typeof(custom->'body') is distinct from 'string'
    or length(custom->>'title')>160 or length(custom->>'body')>2000
    or regexp_replace((custom->>'title')||(custom->>'body'),'\{(event|name|num|podium|rating|players)\}','','g') ~ '[{}]' then
    raise exception 'Invalid category template or placeholder' using errcode='22023'; end if;
   if (input->>'enabled')::boolean and (custom->>'enabled')::boolean
    and (not (s.value->>'enabled')::boolean or not (s.value->'categories'->c->>'enabled')::boolean) then
    next_category_since=jsonb_set(next_category_since,array[c],to_jsonb(now()));
   end if;
  end loop;
  for k in select jsonb_array_elements_text(s.value->'excludedTourIds') except select jsonb_array_elements_text(input->'excludedTourIds') loop
   next_tour_since=jsonb_set(next_tour_since,array[k],to_jsonb(now()));
  end loop;
  -- Seed already-started sections when start notifications are newly activated.
  -- No existing product tables, triggers or companion repository files are changed.
  if (input->>'enabled')::boolean and (input->'categories'->'tournament_started'->>'enabled')::boolean
   and (not (s.value->>'enabled')::boolean or not (s.value->'categories'->'tournament_started'->>'enabled')::boolean) then
   insert into admin_portal.tournament_events(key,category,tour_id,round_id,observed_at,deadline,status)
   select 'tournament_started:'||t.id,'tournament_started',t.id,'',now(),now(),'baseline'
   from public.tours t where not t.is_mirror and exists(select 1 from public.games g where g.tour_id=t.id and nullif(g.last_move,'') is not null)
   on conflict do nothing;
  end if;
  update admin_portal.tournament_settings set value=input||jsonb_build_object('version',v+1),category_since=next_category_since,tour_since=next_tour_since where singleton;
  update admin_portal.tournament_events e set status='canceled' where e.status in ('pending','waiting_final','enqueued')
   and not admin_portal.tournament_allowed(input,e.tour_id,e.category);
  update admin_portal.campaigns c set status='canceled' from admin_portal.tournament_events e
   where e.campaign_id=c.id and e.status='canceled' and c.status in ('scheduled','sending');
  update admin_portal.deliveries d set status='skipped',reason='tournament_disabled',updated_at=now()
   from admin_portal.tournament_events e where e.campaign_id=d.campaign_id and e.status='canceled' and d.status='queued';
  insert into admin_portal.audit(actor,operation,subject) values(actor,'tournament_settings', (v+1)::text);
  return input||jsonb_build_object('version',v+1);
 elsif operation='observe' then
  if not (s.value->>'enabled')::boolean then return 'false'::jsonb; end if;
  select * into o from public.notification_outbox where id=(input->>'outboxId')::uuid;
  if not found or o.event_type not in ('round_started','round_finished') or o.round_id is null then return 'false'::jsonb; end if;
  select * into r from public.rounds where id=o.round_id;
  if not found then return 'false'::jsonb; end if;
  select * into t from public.tours where id=r.tour_id;
  if not found or s.value->'excludedTourIds' ? t.id or t.is_mirror then return 'false'::jsonb; end if;
  -- Repeat the existing producer/dispatcher historical guard, including import origins.
  if public.notification_replay_reason(o.round_id,t.id,t.group_broadcast_id,o.event_type,o.payload->>'notification_origin') is not null then return 'false'::jsonb; end if;
  if o.created_at<now()-interval '1 hour' then return 'false'::jsonb; end if;
  if o.event_type='round_started' and not exists(select 1 from public.games g where g.round_id=r.id and nullif(g.last_move,'') is not null) then return 'false'::jsonb; end if;
  if o.event_type='round_finished' and (not exists(select 1 from public.games g where g.round_id=r.id)
   or exists(select 1 from public.games g where g.round_id=r.id and not public.is_game_finished(g.status))) then return 'false'::jsonb; end if;
  first_round=not exists(select 1 from public.rounds previous where previous.tour_id=t.id and previous.id<>r.id
   and (coalesce(previous.starts_at,previous.created_at),previous.id)<(coalesce(r.starts_at,r.created_at),r.id));
  foreach c in array case when o.event_type='round_started' then array['tournament_started','round_started'] else array['tournament_ended','round_ended'] end loop
   if not admin_portal.tournament_allowed(s.value,t.id,c) then continue; end if;
   earliest=greatest((s.category_since->>c)::timestamptz,(s.tour_since->>t.id)::timestamptz);
   if earliest is null or o.created_at<earliest then continue; end if;
   if c='tournament_started' and not first_round then continue; end if;
   k=c||':'||case when c like 'tournament_%' then t.id else r.id end;
   insert into admin_portal.tournament_events(key,category,tour_id,round_id,observed_at,deadline,status,standings_before)
   values(k,c,t.id,r.id,o.created_at,o.created_at+interval '15 minutes',case when c='tournament_ended' then 'waiting_final' else 'pending' end,md5(jsonb_build_object('players',t.players,'teams',t.info->'officialTeamStandings')::text))
   on conflict do nothing;
   -- Only tournament-end watchers may restart after a later, new completion event.
   if c='tournament_ended' then
    update admin_portal.tournament_events set status='waiting_final',round_id=r.id,observed_at=o.created_at,deadline=o.created_at+interval '15 minutes',check_after=now(),standings_before=md5(jsonb_build_object('players',t.players,'teams',t.info->'officialTeamStandings')::text)
     where key=k and ((status='canceled' and o.created_at>=earliest) or (status='waiting_final' and observed_at<o.created_at));
   else
    if c in ('round_started','round_ended') and exists(select 1 from admin_portal.tournament_events where key=k and status in ('pending','enqueued')) then suppressed=true; end if;
   end if;
  end loop;
  return to_jsonb(suppressed);
 elsif operation='pending' then
  if not (s.value->>'enabled')::boolean then return '[]'::jsonb; end if;
  for e in select * from admin_portal.tournament_events where status='waiting_final' and check_after<=now() order by check_after,observed_at limit 100 for update skip locked loop
   if not admin_portal.tournament_allowed(s.value,e.tour_id,e.category) then continue; end if;
   update admin_portal.tournament_events set check_after=now()+interval '15 minutes' where key=e.key;
   if admin_portal.tournament_finished(e.tour_id) then
    -- Countdown begins at confirmed tournament completion, not an intermediate round.
    update admin_portal.tournament_events set status='pending',deadline=now()+interval '15 minutes',
     round_id=(select id from public.rounds where tour_id=e.tour_id order by coalesce(starts_at,created_at) desc,id desc limit 1) where key=e.key;
   end if;
  end loop;
  return coalesce((select jsonb_agg(x) from (
   select e.key,e.category,coalesce(nullif(concat_ws(' · ',g.name,case when t.name is distinct from g.name then t.name end),''),t.id) as "eventName",
    admin_portal.tournament_round_number(e.round_id) as "roundNumber",e.observed_at as "observedAt",e.deadline,
    s.value->'categories'->e.category->>'title' as title,s.value->'categories'->e.category->>'body' as body,
    coalesce(t.info,'{}') as info,t.avg_elo as "avgElo",t.players,(md5(jsonb_build_object('players',t.players,'teams',t.info->'officialTeamStandings')::text) is distinct from e.standings_before) as "standingsChanged",(s.value->>'version')::integer as version
   from admin_portal.tournament_events e join public.tours t on t.id=e.tour_id
   left join public.group_broadcasts g on g.id=t.group_broadcast_id
   where e.status='pending' and admin_portal.tournament_allowed(s.value,e.tour_id,e.category)
   order by case when e.category like '%started' then 0 else 1 end,e.observed_at,e.key limit 50
  )x),'[]');
 elsif operation='complete' then
  if (input->>'version')::integer is distinct from (s.value->>'version')::integer then return 'null'::jsonb; end if;
  select * into e from admin_portal.tournament_events where key=input->>'key' for update;
  if not found or e.status<>'pending' or not admin_portal.tournament_allowed(s.value,e.tour_id,e.category) then return 'null'::jsonb; end if;
  if coalesce(length(input->>'title'),0) not between 1 and 160 or coalesce(length(input->>'body'),0) not between 1 and 2000 then
   raise exception 'Invalid tournament message' using errcode='22023'; end if;
  select * into t from public.tours where id=e.tour_id;
  if not found then return 'null'::jsonb; end if;
  -- Avoid delayed start alerts; ended notifications get a full day after acceptance.
  if e.category like '%started' and e.observed_at<now()-interval '15 minutes' then
   update admin_portal.tournament_events set status='canceled' where key=e.key;return 'null'::jsonb;
  end if;
  typ=case when e.category like '%started' then 'round_started' else 'round_finished' end;
  route='https://chessever.com/app/broadcast/'||coalesce(nullif(t.group_broadcast_id,''),t.id)||'/'||t.id;
  if e.category like '%ended' then route=route||'?tab=standings'; end if;
  insert into admin_portal.campaigns(name,title,body,audience,data,url,status,source,event_key,scheduled_at,quiet_hours,ttl_seconds,ignore_push_disabled)
  values('Tournament · '||e.category||' · '||coalesce(t.name,t.id),input->>'title',input->>'body','{}',
   jsonb_build_object('type',typ,'automation','tournament','category',e.category,'round_id',e.round_id,'tour_id',e.tour_id,'broadcast_id',t.group_broadcast_id),
   route,'scheduled','trigger','tournament:'||e.key,now(),false,case when e.category like '%started' then 900 else 86400 end,(s.value->>'ignorePushDisabled')::boolean)
  on conflict(event_key) do update set event_key=excluded.event_key returning id into cid;
  update admin_portal.tournament_events set status='enqueued',campaign_id=cid where key=e.key;
  return jsonb_build_object('id',cid);
 end if;
 raise exception 'Unknown tournament operation' using errcode='22023';
end;
$function$;

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.queue_game_notifications()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_notification_origin text := NULLIF(current_setting('chessever.notification_origin', true), '');
  is_live         BOOLEAN;
  was_live        BOOLEAN;
  is_finished     BOOLEAN;
  was_finished    BOOLEAN;
  is_fresh_start  BOOLEAN;
  is_fresh_finish BOOLEAN;
  gb_id           TEXT;
  v_board_nr      SMALLINT;
  v_round_name    TEXT;
  v_round_starts  TIMESTAMPTZ;
  v_round_dedupe  TEXT;
  v_round_row_id  UUID;
  v_round_status  TEXT;
  v_game_delay    TIMESTAMPTZ;
  fire_start      BOOLEAN := FALSE;
  fire_finish     BOOLEAN := FALSE;
BEGIN
  is_live     := NEW.status IN ('*', 'ongoing');
  is_finished := public.is_game_finished(NEW.status);

  IF TG_OP = 'INSERT' THEN
    was_live     := FALSE;
    was_finished := FALSE;
  ELSE
    was_live     := OLD.status IN ('*', 'ongoing');
    was_finished := public.is_game_finished(OLD.status);
  END IF;

  is_fresh_start  := NEW.last_move_time IS NOT NULL
                     AND NEW.last_move_time > now() - interval '5 minutes';
  is_fresh_finish := NEW.last_move_time IS NOT NULL
                     AND NEW.last_move_time > now() - interval '10 minutes';

  IF TG_OP = 'UPDATE'
     AND is_live AND NEW.last_move_time IS NOT NULL
     AND (NOT was_live OR OLD.last_move_time IS NULL) THEN
    fire_start := TRUE;
  ELSIF TG_OP = 'INSERT'
        AND is_live AND is_fresh_start THEN
    fire_start := TRUE;
  END IF;

  IF TG_OP = 'UPDATE'
     AND is_finished AND NOT was_finished THEN
    fire_finish := TRUE;
  ELSIF TG_OP = 'INSERT'
        AND is_finished AND is_fresh_finish THEN
    fire_finish := TRUE;
  END IF;

  IF NOT fire_start AND NOT fire_finish THEN
    RETURN NEW;
  END IF;

  SELECT t.group_broadcast_id INTO gb_id
    FROM public.tours t
   WHERE t.id = NEW.tour_id
   LIMIT 1;

  -- A mirror section (Combined) repeats real sections' boards: it raises no
  -- game or round pushes, and must never claim the group round-start key.
  IF NEW.is_mirror THEN
    RETURN NEW;
  END IF;

  -- Suppress notifications only; the AFTER trigger never cancels game writes.
  IF fire_start AND public.notification_replay_reason(NEW.round_id,NEW.tour_id,gb_id,'game_started',v_notification_origin) IS NOT NULL THEN
    fire_start := FALSE;
  END IF;
  IF fire_finish AND public.notification_replay_reason(NEW.round_id,NEW.tour_id,gb_id,'game_finished',v_notification_origin) IS NOT NULL THEN
    fire_finish := FALSE;
  END IF;
  IF NOT fire_start AND NOT fire_finish THEN RETURN NEW; END IF;

  v_board_nr := NEW.board_nr;

  IF fire_start THEN
    -- No round-level row to defer to unless one is queued below.
    v_game_delay := now();

    IF NEW.round_id IS NOT NULL THEN
      SELECT r.name, r.starts_at
        INTO v_round_name, v_round_starts
        FROM public.rounds r
       WHERE r.id = NEW.round_id
       LIMIT 1;

      -- Match cron's dedupe_key shape so trigger + cron collide.
      v_round_dedupe := CASE
        WHEN gb_id IS NOT NULL AND v_round_starts IS NOT NULL THEN
          'round_started:' || gb_id || ':' ||
          EXTRACT(EPOCH FROM v_round_starts)::bigint::text
        ELSE
          'round_started:' || NEW.round_id
      END;

      INSERT INTO public.notification_outbox (
        event_type, round_id, tour_id, group_broadcast_id, payload, dedupe_key
      )
      VALUES (
        'round_started',
        NEW.round_id,
        NEW.tour_id,
        gb_id,
        jsonb_build_object(
          'notification_origin', v_notification_origin,
          'round_name', v_round_name,
          'starts_at',  COALESCE(v_round_starts, now())
        ),
        v_round_dedupe
      )
      ON CONFLICT (dedupe_key) DO NOTHING
      RETURNING id INTO v_round_row_id;

      IF v_round_row_id IS NOT NULL THEN
        -- We just queued the round announcement; give it the short head start.
        v_game_delay := now() + interval '20 seconds';
      ELSE
        SELECT n.status INTO v_round_status
          FROM public.notification_outbox n
         WHERE n.dedupe_key = v_round_dedupe
         LIMIT 1;

        IF v_round_status IN ('pending', 'processing') THEN
          v_game_delay := now() + interval '20 seconds';
        END IF;

        -- The round row can be parked in the future: the cron queues it at the
        -- scheduled start and the dispatcher reschedules it every few seconds
        -- until a move exists. That move is this statement. Pull it forward and
        -- dispatch immediately rather than waiting out the retry and the next
        -- heartbeat â€” that wait was up to ~90 seconds.
        IF v_round_status = 'pending' THEN
          UPDATE public.notification_outbox n
             SET not_before = now()
           WHERE n.dedupe_key = v_round_dedupe
             AND n.status = 'pending'
             AND n.not_before > now();

          -- Only the first board of the round finds a future not_before, so a
          -- 12-board simultaneous start still pokes the dispatcher once.
          -- Never let the poke abort the write that carried the move: this
          -- trigger sits on the live ingestion path.
          IF FOUND THEN
            BEGIN
              PERFORM public.dispatch_notification_now();
            EXCEPTION WHEN OTHERS THEN
              NULL;
            END;
          END IF;
        END IF;
      END IF;
    END IF;

    INSERT INTO public.notification_outbox (
      event_type, game_id, tour_id, round_id, group_broadcast_id, payload, dedupe_key, not_before
    )
    VALUES (
      'game_started',
      NEW.id,
      NEW.tour_id,
      NEW.round_id,
      gb_id,
      jsonb_build_object(
        'notification_origin', v_notification_origin,
        'status',          NEW.status,
        'last_move_time',  NEW.last_move_time,
        'player_white',    NEW.player_white,
        'player_black',    NEW.player_black,
        'board_nr',        v_board_nr
      ),
      'game_started:' || NEW.id,
      v_game_delay
    )
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;

  IF fire_finish THEN
    INSERT INTO public.notification_outbox (
      event_type, game_id, tour_id, round_id, group_broadcast_id, payload, dedupe_key
    )
    VALUES (
      'game_finished',
      NEW.id,
      NEW.tour_id,
      NEW.round_id,
      gb_id,
      jsonb_build_object(
        'notification_origin', v_notification_origin,
        'status',          NEW.status,
        'last_move_time',  NEW.last_move_time,
        'player_white',    NEW.player_white,
        'player_black',    NEW.player_black,
        'board_nr',        v_board_nr
      ),
      'game_finished:' || NEW.id
    )
    ON CONFLICT (dedupe_key) DO NOTHING;

    IF NEW.round_id IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.games
         WHERE round_id = NEW.round_id
           AND id != NEW.id
           AND NOT public.is_game_finished(status)
      ) THEN
        INSERT INTO public.notification_outbox (
          event_type, round_id, tour_id, group_broadcast_id, payload, dedupe_key
        )
        VALUES (
          'round_finished',
          NEW.round_id,
          NEW.tour_id,
          gb_id,
          jsonb_build_object(
            'notification_origin', v_notification_origin,
            'results', (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'white',    g2.player_white,
                  'black',    g2.player_black,
                  'status',   g2.status,
                  'board_nr', g2.board_nr
                ) ORDER BY COALESCE(g2.board_nr, 32767), g2.player_white NULLS LAST
              )
              FROM public.games g2
              WHERE g2.round_id = NEW.round_id
            )
          ),
          'round_finished:' || NEW.round_id
        )
        ON CONFLICT (dedupe_key) DO NOTHING;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.queue_round_start_notifications()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  now_ts TIMESTAMPTZ := now();
BEGIN
  INSERT INTO public.notification_outbox (
    event_type,
    round_id,
    tour_id,
    group_broadcast_id,
    payload,
    dedupe_key
  )
  SELECT
    'round_started',
    r.id,
    r.tour_id,
    t.group_broadcast_id,
    jsonb_build_object(
      'round_name', r.name,
      'starts_at', r.starts_at
    ),
    CASE
      WHEN t.group_broadcast_id IS NOT NULL THEN
        'round_started:' ||
        t.group_broadcast_id::text || ':' ||
        EXTRACT(EPOCH FROM r.starts_at)::bigint::text
      ELSE
        'round_started:' || r.id::text
    END
  FROM public.rounds r
  JOIN public.tours t ON t.id = r.tour_id
  WHERE r.starts_at IS NOT NULL
    AND NOT t.is_mirror
    AND r.starts_at <= now_ts
    AND r.starts_at >= now_ts - interval '60 minutes'
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$function$;

CREATE OR REPLACE FUNCTION public.queue_round_heads_up_notifications()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  now_ts TIMESTAMPTZ := now();
BEGIN
  INSERT INTO public.notification_outbox (
    event_type,
    round_id,
    tour_id,
    group_broadcast_id,
    payload,
    dedupe_key
  )
  SELECT
    'round_heads_up',
    r.id,
    r.tour_id,
    t.group_broadcast_id,
    jsonb_build_object(
      'round_name', r.name,
      'starts_at', r.starts_at,
      'lead_minutes', lt.lead_minutes
    ),
    'round_heads_up:' || r.id || ':' || lt.lead_minutes
  FROM public.rounds r
  JOIN public.tours t ON t.id = r.tour_id
  JOIN (
    VALUES
      (5, interval '5 minutes'),
      (10, interval '10 minutes'),
      (30, interval '30 minutes')
  ) AS lt(lead_minutes, lead_interval) ON TRUE
  WHERE r.starts_at IS NOT NULL
    AND NOT t.is_mirror
    AND r.starts_at >= now_ts + (lt.lead_interval - interval '1 minute')
    AND r.starts_at < now_ts + (lt.lead_interval + interval '1 minute')
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Most-liked rankings (short term: mirror ids are left out)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION rewarded_private.most_liked_ranking_page(p_from timestamp with time zone, p_to timestamp with time zone, p_limit integer DEFAULT 13, p_after_likes bigint DEFAULT NULL::bigint, p_after_game_id text DEFAULT NULL::text)
 RETURNS TABLE(source_game_id text, like_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_from is null or p_to is null or p_to <= p_from
      or p_to - p_from > interval '367 days' then return; end if;
  if (p_after_likes is null) <> (p_after_game_id is null) then
    raise exception 'invalid_cursor';
  end if;
  return query
    select ranked.game_id, ranked.likes
    from (
      select l.source_game_id as game_id,
        count(distinct l.user_id)::bigint as likes
      from rewarded_private.game_likes l
      where l.created_at >= p_from and l.created_at < p_to
        and not exists (select 1 from public.games mg
          where mg.id = l.source_game_id and mg.is_mirror)
        and not exists (select 1 from public.games mg
          where mg.lichess_id = l.source_game_id and mg.is_mirror)
      group by l.source_game_id
      having count(distinct l.user_id) >= 2
    ) ranked
    where p_after_likes is null or ranked.likes < p_after_likes
      or (ranked.likes = p_after_likes and ranked.game_id > p_after_game_id)
    order by ranked.likes desc, ranked.game_id asc
    limit least(greatest(coalesce(p_limit, 13), 1), 50);
end;
$function$;

CREATE OR REPLACE FUNCTION rewarded_private.most_liked_ranking_preview(p_from timestamp with time zone, p_to timestamp with time zone, p_limit integer DEFAULT 20)
 RETURNS TABLE(source_game_id text, like_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_from is null or p_to is null or p_to <= p_from
      or p_to - p_from > interval '367 days' then return; end if;
  return query
    select l.source_game_id, count(distinct l.user_id)::bigint as likes
    from rewarded_private.game_likes l
    where l.created_at >= p_from and l.created_at < p_to
      and not exists (select 1 from public.games mg
        where mg.id = l.source_game_id and mg.is_mirror)
      and not exists (select 1 from public.games mg
        where mg.lichess_id = l.source_game_id and mg.is_mirror)
    group by l.source_game_id
    order by likes desc, l.source_game_id asc
    limit v_limit;
end;
$function$;

CREATE OR REPLACE FUNCTION public.signin_preview_likes(p_period text, p_timezone text, p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  local_start timestamp;
  local_end timestamp;
  expected_from timestamptz;
  expected_to timestamptz;
  result jsonb;
begin
  if p_period is null or p_period not in ('today','week','month','year')
    or p_timezone is null or length(p_timezone) > 64
    or not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = p_timezone)
    or p_from is null or p_to is null or not isfinite(p_from) or not isfinite(p_to)
  then raise exception using errcode = '22023', message = 'invalid_preview_window'; end if;

  -- Calendar boundaries in the visitor's actual IANA timezone, including DST.
  -- PostgreSQL date_trunc('week', ...) is the application's Monday-start week.
  local_start := date_trunc(case when p_period = 'today' then 'day' else p_period end, timezone(p_timezone, now()));
  local_end := local_start + case p_period when 'today' then interval '1 day'
    when 'week' then interval '1 week' when 'month' then interval '1 month'
    else interval '1 year' end;
  expected_from := timezone(p_timezone, local_start);
  expected_to := timezone(p_timezone, local_end);
  if p_from <> expected_from or p_to <> expected_to or p_to <= p_from
    or p_to - p_from > interval '367 days'
  then raise exception using errcode = '22023', message = 'invalid_preview_window'; end if;

  with ranked as materialized (
    select l.source_game_id, count(distinct l.user_id)::bigint as like_count
    from rewarded_private.game_likes l
    where l.created_at >= p_from and l.created_at < p_to
      and not exists (select 1 from public.games mg
        where mg.id = l.source_game_id and mg.is_mirror)
      and not exists (select 1 from public.games mg
        where mg.lichess_id = l.source_game_id and mg.is_mirror)
    group by l.source_game_id
    having count(distinct l.user_id) >= 2
    order by like_count desc, l.source_game_id asc
    limit 12
  ), hydrated as materialized (
    select ranked.source_game_id,
      rewarded_private.signin_preview_public_game(to_jsonb(g) || jsonb_build_object(
        'time_control', gb.time_control, 'avg_elo', t.avg_elo,
        'round_starts_at', r.starts_at, 'round_name', r.name,
        'tour_name', t.name, 'event_name', gb.name, 'time_control_text', t.info->>'tc'
      )) as game
    from ranked
    join public.games g on g.id = ranked.source_game_id
    left join public.tours t on t.id = g.tour_id
    left join public.group_broadcasts gb on gb.id = t.group_broadcast_id
    left join public.rounds r on r.id = g.round_id
  )
  select jsonb_build_object(
    'schemaVersion', 1, 'dataset', 'community-likes',
    'period', p_period, 'timeZone', p_timezone, 'from', p_from, 'to', p_to,
    'generatedAt', now(),
    'rows', coalesce((select jsonb_agg(to_jsonb(ranked) order by like_count desc, source_game_id asc) from ranked), '[]'::jsonb),
    'games', coalesce((select jsonb_agg(h.game order by r.like_count desc, r.source_game_id asc)
      from hydrated h join ranked r using(source_game_id)), '[]'::jsonb),
    -- A ranked Gamebase-only ID stays in rows; no invented starting FEN or
    -- substitute broadcast game. The client must report unresolved metadata.
    'unresolvedGameIds', coalesce((select jsonb_agg(r.source_game_id order by r.like_count desc, r.source_game_id asc)
      from ranked r where not exists(select 1 from hydrated h where h.source_game_id = r.source_game_id)), '[]'::jsonb),
    'missingPositionGameIds', coalesce((select jsonb_agg(h.source_game_id) from hydrated h
      where nullif(btrim(h.game->>'fen'), '') is null), '[]'::jsonb)
  ) into result;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION rewarded_private.most_liked_games(p_from timestamp with time zone, p_to timestamp with time zone, p_limit integer, p_rewarded_session text)
 RETURNS TABLE(source_game_id text, like_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if p_from is null or p_to is null or p_to <= p_from then
    return;
  end if;

  if (p_to - p_from > interval '26 hours'
      or p_from < now() - interval '26 hours')
    and not (coalesce(public._user_has_premium(auth.uid()), false)
      or coalesce(rewarded_private.has_access(p_rewarded_session), false)) then
    raise exception 'premium_required'
      using errcode = 'P0001',
            hint = 'Most Liked beyond the current day is a Premium ranking.';
  end if;

  return query
    select ranked.game_id, ranked.likes
    from (
      select
        a.source_game_id as game_id,
        count(distinct a.user_id)::bigint as likes
      from public.user_saved_analyses a
      join public.user_folders f
        on f.id = a.folder_id
       and f.user_id = a.user_id
       and f.is_liked_games
      where a.source_game_id is not null
        and btrim(a.source_game_id) <> ''
        and a.created_at >= p_from
        and a.created_at < p_to
        and not exists (select 1 from public.games mg
          where mg.id = a.source_game_id and mg.is_mirror)
        and not exists (select 1 from public.games mg
          where mg.lichess_id = a.source_game_id and mg.is_mirror)
      group by a.source_game_id
    ) ranked
    order by ranked.likes desc, ranked.game_id asc
    limit v_limit;
end;
$function$;

CREATE OR REPLACE FUNCTION public.most_liked_games(p_from timestamp with time zone, p_to timestamp with time zone, p_limit integer DEFAULT 20)
 RETURNS TABLE(source_game_id text, like_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if p_from is null or p_to is null or p_to <= p_from then
    return;
  end if;

  if (p_to - p_from > interval '26 hours'
      or p_from < now() - interval '26 hours')
    and not coalesce(public._user_has_premium(auth.uid()), false) then
    raise exception 'premium_required'
      using errcode = 'P0001',
            hint = 'Most Liked beyond the current day is a Premium ranking.';
  end if;

  return query
    select ranked.game_id, ranked.likes
    from (
      select
        a.source_game_id as game_id,
        count(distinct a.user_id)::bigint as likes
      from public.user_saved_analyses a
      join public.user_folders f
        on f.id = a.folder_id
       and f.user_id = a.user_id
       and f.is_liked_games
      where a.source_game_id is not null
        and btrim(a.source_game_id) <> ''
        and a.created_at >= p_from
        and a.created_at < p_to
        and not exists (select 1 from public.games mg
          where mg.id = a.source_game_id and mg.is_mirror)
        and not exists (select 1 from public.games mg
          where mg.lichess_id = a.source_game_id and mg.is_mirror)
      group by a.source_game_id
    ) ranked
    order by ranked.likes desc, ranked.game_id asc
    limit v_limit;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Backfill
-- ---------------------------------------------------------------------------

-- Recompute the flag on every candidate tour. The touch runs the BEFORE
-- triggers (override, then the mirror flag) and tours_zzz_propagate_mirror
-- restamps the tour's games, which marks their players.
--
-- Checked on 2026-11-11, this flags four tours, each a board-for-board copy
-- of its event's real sections:
--   wLrwkC0C  Total Chess World Championship Tour Pilot 2026 | Group Stage |
--             Combined (live; info.mirror already set by its override row)
--   WuOJlOwJ  Norway Chess 2026 | Combined Boards (95 games)
--   XWAK5Jdf  Dutch Championship 2026 Combined (74 games)
--   VxPSBCuf  Majstrovstva Slovenska 2026 | Combined boards (90 games)
update public.tours
   set info = info
 where public.tour_label_is_combined(name, slug)
    or info ? 'mirror';

-- Safety net for any game the touch did not reach. Driven by idx_games_tour_id
-- through the handful of mirror tours, never by a scan of games.
update public.games g
   set is_mirror = true
 where g.tour_id = any(array(select t.id from public.tours t where t.is_mirror))
   and not g.is_mirror;
