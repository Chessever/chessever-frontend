-- Mirror (Combined) sections, follow-up to 20261111200000_mirror_tours.
--
-- 1. A real section that is deleted re-evaluates its event's Combined
--    sections, as joining, leaving or renaming already did. Without it a
--    Combined tour whose last real section is gone stays a mirror, and its
--    boards (now the only copy) stay out of every cross-event list.
-- 2. An empty group_broadcast_id is no event: a "combined" tour with group ''
--    is not a mirror because of unrelated tours that also have ''.
-- 3. Streak rows that point at mirror boards move to the real section's copy
--    of the same board. The Dutch Championship 2026 Combined copies carry a
--    different game_day from their section copies, so the reconcile's
--    fingerprint repoint never matched them and those rows stuck. From now on
--    a row on a mirror board that cannot be repointed is withdrawn (and the
--    player's coverage rechecked) instead of being kept forever.
--
-- No table rewrite and no ACCESS EXCLUSIVE lock. The only table lock is
-- SHARE ROW EXCLUSIVE on tours for CREATE OR REPLACE TRIGGER (reads continue,
-- tour writes wait); it is the last statement, so it is held only until the
-- commit. The streak cleanup takes about 4 s on production.

set lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- Tour flag: ignore an empty group id
-- ---------------------------------------------------------------------------

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
      and nullif(btrim(new.group_broadcast_id), '') is not null
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

-- ---------------------------------------------------------------------------
-- Re-evaluate Combined siblings on insert, update and delete
-- ---------------------------------------------------------------------------

-- A real section joining, leaving, being renamed or being deleted changes
-- whether its event's Combined sections are mirrors: touch them so the BEFORE
-- trigger recomputes. The touch sets only info, which this trigger does not
-- watch, so it cannot recurse. AFTER ROW triggers run once the statement has
-- finished, so a statement that deletes a whole event finds its Combined
-- tour already gone.
create or replace function public.tours_refresh_combined_siblings()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'DELETE' then
    if public.tour_label_is_combined(old.name, old.slug)
       or nullif(btrim(old.group_broadcast_id), '') is null then
      return null;
    end if;

    update public.tours c
       set info = c.info
     where c.group_broadcast_id = old.group_broadcast_id
       and public.tour_label_is_combined(c.name, c.slug);
    return null;
  end if;

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
     and ((nullif(btrim(new.group_broadcast_id), '') is not null
           and c.group_broadcast_id = new.group_broadcast_id)
          or (tg_op = 'UPDATE'
              and nullif(btrim(old.group_broadcast_id), '') is not null
              and c.group_broadcast_id = old.group_broadcast_id))
     and public.tour_label_is_combined(c.name, c.slug);

  return null;
end;
$$;

revoke execute on function public.tours_refresh_combined_siblings() from public, anon, authenticated;

-- Recompute any Combined tour that the empty-group rule flagged. None on
-- 2026-11-11 (the only tour with group '' is not a Combined section).
update public.tours
   set info = info
 where group_broadcast_id is not null
   and btrim(group_broadcast_id) = ''
   and public.tour_label_is_combined(name, slug);

-- ---------------------------------------------------------------------------
-- Streaks: withdraw rows stuck on a mirror board
-- ---------------------------------------------------------------------------

-- Same function as 20261111200000, except the withdraw step: a row whose game
-- is a mirror board and could not be repointed above it is withdrawn like a
-- vanished game, instead of being kept (it reset the player's coverage on
-- every run).
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
        AND EXISTS (SELECT 1 FROM games g WHERE g.id = l.game_id AND NOT g.is_mirror))
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
-- Streaks: one-time cleanup of rows on mirror boards
-- ---------------------------------------------------------------------------

-- Each row moves to the real section's copy of its board (same event, same
-- white and black FIDE ids, result and final position), taking that copy's
-- day, order and fingerprint from player_streak_candidate_games. When the
-- player's ledger already holds that board (same game or fingerprint), the
-- mirror row is a duplicate and is removed. Any row still on a mirror board
-- afterwards (no single copy, or the copy is not eligible) is removed too.
-- Each touched player's coverage is rechecked.
--
-- Checked on 2026-11-11: 10 rows, all on Dutch Championship 2026 Combined
-- (XWAK5Jdf). 9 repoint; row 1436 duplicates row 1435 and is removed.
create temp table _mirror_streak_fix as
with stuck as (
  select l.id, l.fide_id, copy.ids[1] as copy_id
  from public.player_streak_game l
  join public.games mg on mg.id = l.game_id and mg.is_mirror
  join public.tours mt on mt.id = mg.tour_id
  cross join lateral (
    select array_agg(s.id order by s.id) as ids
    from public.games s
    join public.tours st on st.id = s.tour_id
    where st.group_broadcast_id = mt.group_broadcast_id
      and not s.is_mirror
      and s.status is not distinct from mg.status
      and s.fen is not distinct from mg.fen
      and s.players->0->>'fideId' is not distinct from mg.players->0->>'fideId'
      and s.players->1->>'fideId' is not distinct from mg.players->1->>'fideId'
  ) copy
  where nullif(btrim(mt.group_broadcast_id), '') is not null
    and cardinality(copy.ids) = 1
)
-- The candidate list keeps one game per fingerprint, which may be another
-- id carrying the same board; match on the copy's fingerprint.
select st.id, st.fide_id, c.*
from stuck st
join public.games cg on cg.id = st.copy_id
cross join lateral public.player_streak_candidate_games(st.fide_id, cg.game_day) c
where c.fingerprint = concat_ws('|',
        coalesce(public.player_streak_fide(cg.players->0->'fideId')::text,
                 lower(coalesce(cg.players->0->>'name', ''))),
        coalesce(public.player_streak_fide(cg.players->1->'fideId')::text,
                 lower(coalesce(cg.players->1->>'name', ''))),
        cg.game_day::text, cg.status, coalesce(cg.live_ply_count::text, ''));

create temp table _mirror_streak_players (fide_id bigint);

with upd as (
  update public.player_streak_game l
     set game_id = r.game_id, fingerprint = r.fingerprint, game_day = r.game_day,
         sort_at = r.sort_at, color = r.color, result = r.result, status = r.status,
         player_name = r.player_name, player_rating = r.player_rating,
         opponent_fide_id = r.opponent_fide_id, opponent_name = r.opponent_name,
         opponent_title = r.opponent_title, opponent_fed = r.opponent_fed,
         opponent_rating = r.opponent_rating, tour_id = r.tour_id, tour_name = r.tour_name,
         round_id = r.round_id, round_name = r.round_name, round_starts_at = r.round_starts_at,
         group_broadcast_id = r.group_broadcast_id, group_broadcast_name = r.group_broadcast_name,
         time_control = r.time_control, time_start = r.time_start,
         last_move_time = r.last_move_time, live_ply_count = r.live_ply_count,
         updated_at = now()
    from _mirror_streak_fix r
   where l.id = r.id
     and r.id = (select min(r2.id) from _mirror_streak_fix r2
                 where r2.fide_id = r.fide_id and r2.fingerprint = r.fingerprint)
     and not exists (
       select 1 from public.player_streak_game x
       where x.fide_id = l.fide_id and x.id <> l.id
         and (x.game_id = r.game_id or x.fingerprint = r.fingerprint))
  returning l.fide_id
)
insert into _mirror_streak_players select fide_id from upd;

with del as (
  delete from public.player_streak_game l
   using public.games g
   where g.id = l.game_id and g.is_mirror
  returning l.fide_id
)
insert into _mirror_streak_players select fide_id from del;

update public.player_streak ps
   set coverage_checked_at = null
 where ps.fide_id in (select fide_id from _mirror_streak_players);

drop table _mirror_streak_fix, _mirror_streak_players;

-- ---------------------------------------------------------------------------
-- Delete trigger, last so the tours lock is held only until the commit
-- ---------------------------------------------------------------------------

create or replace trigger tours_zzz_refresh_combined_siblings_delete
after delete on public.tours
for each row execute function public.tours_refresh_combined_siblings();
