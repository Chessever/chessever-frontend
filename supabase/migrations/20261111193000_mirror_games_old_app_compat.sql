-- Mirror sections ("Combined") without duplicate games, for every app build.
--
-- Total Chess World Championship Tour Pilot 2026 publishes Group Stage A-D
-- and a "Group Stage | Combined" tour (wLrwkC0C) that repeats every board as
-- its own game row. Combined is the easiest way to follow this event, so it
-- stays. Its copies must not show up a second time in cross-event lists.
--
-- Released mobile builds query public.games directly. Their cross-event lists
-- filter on columns generated from games.players:
--   favorites, player profile, saved players  -> player_fide_ids
--   countrymen                                -> player_feds
--   smart events, For You                     -> player_max_rating
--   free-text game search                     -> search
-- A tour page loads its games by tour/round id and draws players from the
-- players jsonb itself (names, fideId, fed, rating stay intact).
--
-- So a mirror game keeps its full players jsonb, but every element carries
-- "mirror": true, and the generated-column functions skip marked elements:
-- the mirror row has no FIDE ids, no federations and no rating to match, and
-- an empty search array. Unmarked input gives exactly the old results, so
-- existing rows and index entries stay valid.
--
-- A tour is a mirror only when its info carries "mirror": true, set through
-- broadcasting_private.tour_info_overrides so the Lichess sync cannot drop it.

-- No column on public.games here: ADD COLUMN needs an ACCESS EXCLUSIVE lock,
-- which live reads keep from being granted. The trigger below needs only
-- SHARE ROW EXCLUSIVE.
set lock_timeout = '10s';

create or replace function public.games_player_fide_ids(players jsonb)
returns bigint[]
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  SELECT COALESCE(
    array_agg(DISTINCT (p->>'fideId')::bigint)
      FILTER (WHERE (p->>'fideId') ~ '^[0-9]+$'
                AND COALESCE(p->>'mirror', '') <> 'true'),
    ARRAY[]::bigint[]
  )
  FROM jsonb_array_elements(COALESCE(players, '[]'::jsonb)) p;
$function$;

create or replace function public.games_player_feds(players jsonb)
returns text[]
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  SELECT COALESCE(
    array_agg(DISTINCT upper(p->>'fed'))
      FILTER (WHERE p ? 'fed' AND p->>'fed' <> ''
                AND COALESCE(p->>'mirror', '') <> 'true'),
    ARRAY[]::text[]
  )
  FROM jsonb_array_elements(COALESCE(players, '[]'::jsonb)) p;
$function$;

create or replace function public.games_player_max_rating(players jsonb)
returns integer
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  SELECT COALESCE(
    MAX((p->>'rating')::int)
      FILTER (WHERE (p->>'rating') ~ '^[0-9]+$'
                AND COALESCE(p->>'mirror', '') <> 'true'),
    0
  )
  FROM jsonb_array_elements(COALESCE(players, '[]'::jsonb)) p;
$function$;

create or replace function public.smart_event_average_rating(players jsonb)
returns integer
language sql
immutable parallel safe
set search_path to ''
as $function$
  select case when coalesce(players->0->>'mirror', '') = 'true'
                or coalesce(players->1->>'mirror', '') = 'true'
    then 0
    when jsonb_typeof(players->0->'rating') = 'number'
                   and jsonb_typeof(players->1->'rating') = 'number'
    then case when trunc((players->0->>'rating')::numeric) > 0
                    and trunc((players->1->>'rating')::numeric) > 0
      then floor((trunc((players->0->>'rating')::numeric)
                + trunc((players->1->>'rating')::numeric)) / 2)::integer
      else 0 end
    else 0 end;
$function$;

-- Runs after the other BEFORE triggers on games (they fire in name order:
-- "game_..." < "games_..."); generated columns are computed after all of them.
create or replace function public.games_mark_mirror()
returns trigger
language plpgsql
set search_path to ''
as $$
declare
  mirror boolean;
begin
  select coalesce(t.info->>'mirror', '') = 'true' into mirror
  from public.tours t
  where t.id = new.tour_id;
  mirror := coalesce(mirror, false);

  if jsonb_typeof(new.players) = 'array' then
    if mirror then
      new.players := (
        select coalesce(jsonb_agg(
          case when jsonb_typeof(e) = 'object' then e || '{"mirror": true}'::jsonb else e end
          order by ord), '[]'::jsonb)
        from jsonb_array_elements(new.players) with ordinality as x(e, ord)
      );
    elsif new.players::text like '%"mirror"%' then
      new.players := (
        select coalesce(jsonb_agg(
          case when jsonb_typeof(e) = 'object' then e - 'mirror' else e end
          order by ord), '[]'::jsonb)
        from jsonb_array_elements(new.players) with ordinality as x(e, ord)
      );
    end if;
  end if;

  if mirror then
    new.search := array[]::text[];
  end if;
  return new;
end;
$$;

drop trigger if exists games_mark_mirror on public.games;
create trigger games_mark_mirror
before insert or update on public.games
for each row execute function public.games_mark_mirror();

-- Re-mark a tour's games when its mirror flag changes.
create or replace function public.tours_remark_mirror_games()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if (coalesce(new.info->>'mirror', '') = 'true')
     is distinct from (coalesce(old.info->>'mirror', '') = 'true') then
    update public.games set players = players where tour_id = new.id;
  end if;
  return null;
end;
$$;

drop trigger if exists tours_remark_mirror_games on public.tours;
create trigger tours_remark_mirror_games
after update of info on public.tours
for each row execute function public.tours_remark_mirror_games();

-- Mirror sections raise no pushes (live definitions, one filter added each).
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
  IF EXISTS (SELECT 1 FROM public.tours t WHERE t.id = NEW.tour_id
             AND COALESCE(t.info->>'mirror', '') = 'true') THEN
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
    AND COALESCE(t.info->>'mirror', '') <> 'true'
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
    AND COALESCE(t.info->>'mirror', '') <> 'true'
    AND r.starts_at >= now_ts + (lt.lead_interval - interval '1 minute')
    AND r.starts_at < now_ts + (lt.lead_interval + interval '1 minute')
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$function$;
