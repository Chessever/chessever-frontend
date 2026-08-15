-- Migration: stop holding start alerts for two minutes.
--
-- Measured on prod, 2026-08-15 (36h of notification_outbox):
--   round_started : not_before = created_at, terminal after 1-2 seconds.
--   game_started  : not_before = created_at + 120s, terminal after 126-168s.
--
-- The 120 seconds is not a race or a delivery delay — queue_game_notifications
-- enqueues game_started with `now() + interval '2 minutes'` outright. It exists
-- so the round-level announcement (better copy, covers several favourites in
-- one push) always wins and the per-board row is suppressed by the game_start
-- window it writes. That is the right precedence, but the price is paid by
-- exactly the boards that round_started does NOT cover: a board whose first
-- move lands after its round was already announced has no round-level row left
-- to wait for, and still sits out the full two minutes. Carlsen–Lazavik was
-- that case.
--
-- Fixes here:
--   1. The hold is now conditional and 20s, not unconditional and 120s. It
--      applies only while a round_started row for the same round is actually
--      pending or processing — i.e. only when there is something to lose the
--      race to. round_started terminates in 1-2s, so 20s is ~10x margin.
--   2. A round_started row parked on `not_before` while it waits for the first
--      move is pulled forward and dispatched the moment that move lands,
--      instead of waiting out its retry delay and the next heartbeat.
--   3. The cron backstop covers a 60-minute start window instead of 10.
--   4. Rows abandoned in 'processing' are requeued instead of lost.
--   5. The heartbeat floor drops from 60s to 15s.
--
-- Function bodies below are prod's current definitions (which had drifted ahead
-- of this repo) plus those changes, so the repo is the source of truth again.
--
-- Created: 2026-08-15

-- Poke the dispatcher outside the pending-count check the heartbeat does. Used
-- when a row that was already enqueued becomes sendable *now*.
CREATE OR REPLACE FUNCTION public.dispatch_notification_now()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  dispatch_url text;
  token text;
  hdrs jsonb;
BEGIN
  dispatch_url := public.get_vault_secret('live_dispatch_url');
  IF dispatch_url IS NULL OR dispatch_url = '' THEN
    dispatch_url := 'https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/onesignal-dispatch';
  END IF;

  token := public.get_vault_secret('live_dispatch_token');
  hdrs := jsonb_build_object('Content-Type', 'application/json');
  IF token IS NOT NULL AND token <> '' THEN
    hdrs := hdrs || jsonb_build_object('x-stream-token', token);
  END IF;

  BEGIN
    PERFORM net.http_post(
      url     := dispatch_url,
      body    := jsonb_build_object('limit', 50),
      headers := hdrs
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.dispatch_notification_now() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.dispatch_notification_now() TO service_role;

CREATE OR REPLACE FUNCTION public.queue_game_notifications()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
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
        -- heartbeat — that wait was up to ~90 seconds.
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
$$;

-- Cron backstop: 10-minute start window was too tight for a round whose
-- scheduled start drifted. The send is still gated on a real move by the
-- dispatcher (hasRoundWithMoves), so a wider enqueue window cannot announce a
-- round that never began.
CREATE OR REPLACE FUNCTION public.queue_round_start_notifications()
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
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
    AND r.starts_at <= now_ts
    AND r.starts_at >= now_ts - interval '60 minutes'
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$;

-- Rows abandoned in 'processing'.
-- claim_notification_outbox_batch flips rows to 'processing' before the edge
-- function does any work. An invocation that hits the wall-clock limit or dies
-- mid-batch leaves them there permanently: the push is never sent and nothing
-- reports it.
CREATE OR REPLACE FUNCTION public.requeue_stuck_notification_outbox()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_requeued integer;
BEGIN
  UPDATE public.notification_outbox
     SET status = CASE WHEN attempts >= 6 THEN 'failed' ELSE 'pending' END,
         last_error = CASE
           WHEN attempts >= 6 THEN 'stuck_processing_gave_up'
           ELSE 'requeued_stuck_processing'
         END,
         not_before = now()
   WHERE status = 'processing'
     AND updated_at < now() - interval '2 minutes';

  GET DIAGNOSTICS v_requeued = ROW_COUNT;
  RETURN v_requeued;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.requeue_stuck_notification_outbox() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.requeue_stuck_notification_outbox() TO service_role;

SELECT cron.schedule(
  'requeue-stuck-notification-outbox',
  '* * * * *',
  $$SELECT public.requeue_stuck_notification_outbox()$$
);

-- Heartbeat floor 60s -> 15s. pg_cron's finest granularity is a minute, so
-- stagger three extra jobs inside it. Each sleeps then posts once; the post is
-- queued by pg_net and leaves when that job's transaction commits, i.e. at the
-- offset, not batched at the end of the minute.
CREATE OR REPLACE FUNCTION public.dispatch_pending_heartbeat_delayed(p_delay_seconds integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM pg_sleep(GREATEST(0, LEAST(COALESCE(p_delay_seconds, 0), 55)));
  PERFORM public.dispatch_pending_heartbeat();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.dispatch_pending_heartbeat_delayed(integer) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.dispatch_pending_heartbeat_delayed(integer) TO service_role;

SELECT cron.schedule(
  'dispatch-pending-heartbeat-15s',
  '* * * * *',
  $$SELECT public.dispatch_pending_heartbeat_delayed(15)$$
);
SELECT cron.schedule(
  'dispatch-pending-heartbeat-30s',
  '* * * * *',
  $$SELECT public.dispatch_pending_heartbeat_delayed(30)$$
);
SELECT cron.schedule(
  'dispatch-pending-heartbeat-45s',
  '* * * * *',
  $$SELECT public.dispatch_pending_heartbeat_delayed(45)$$
);
