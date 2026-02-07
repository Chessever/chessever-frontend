-- Migration: Smart round notifications — pg_cron, simplified functions, anti-oversend
-- Purpose: Activate round notifications via pg_cron, simplify dedupe keys,
--          piggyback round_started in game trigger, suppress game_started when round covers it
-- Created: 2026-02-07

-- 1A. Install pg_cron
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
GRANT USAGE ON SCHEMA cron TO postgres;

-- 1B. Simplify & fix queue_round_heads_up_notifications()
-- New dedupe key: one per round (not per event/2h window)
-- Window: 25-45 min before starts_at (~30-40 min heads-up)
-- Payload includes computed lead_minutes
CREATE OR REPLACE FUNCTION public.queue_round_heads_up_notifications()
RETURNS void AS $$
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
      'lead_minutes', ROUND(EXTRACT(EPOCH FROM (r.starts_at - now_ts)) / 60)::int
    ),
    'round_heads_up:' || r.id
  FROM public.rounds r
  JOIN public.tours t ON t.id = r.tour_id
  WHERE r.starts_at IS NOT NULL
    AND r.starts_at >= now_ts + interval '25 minutes'
    AND r.starts_at <= now_ts + interval '45 minutes'
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

-- 1C. Simplify & fix queue_round_start_notifications()
-- New dedupe key: one per round
-- Window: starts_at <= now AND starts_at >= now - 10min
CREATE OR REPLACE FUNCTION public.queue_round_start_notifications()
RETURNS void AS $$
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
    'round_started:' || r.id
  FROM public.rounds r
  JOIN public.tours t ON t.id = r.tour_id
  WHERE r.starts_at IS NOT NULL
    AND r.starts_at <= now_ts
    AND r.starts_at >= now_ts - interval '10 minutes'
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

-- 1D & 1E. Extend queue_game_notifications() trigger:
--   - Piggyback round_started when a game goes live and has round_id
--   - Suppress game_started when a round_started already exists for this round (< 5 min old)
CREATE OR REPLACE FUNCTION public.queue_game_notifications()
RETURNS TRIGGER AS $$
DECLARE
  is_live BOOLEAN;
  was_live BOOLEAN;
  is_finished BOOLEAN;
  was_finished BOOLEAN;
  gb_id TEXT;
  round_notif_exists BOOLEAN;
BEGIN
  is_live := NEW.status IN ('*', 'ongoing');
  was_live := OLD.status IN ('*', 'ongoing');
  is_finished := public.is_game_finished(NEW.status);
  was_finished := public.is_game_finished(OLD.status);

  SELECT t.group_broadcast_id INTO gb_id
    FROM public.tours t
   WHERE t.id = NEW.tour_id
   LIMIT 1;

  -- Game started: status became live or first move arrived while live.
  IF is_live AND NEW.last_move_time IS NOT NULL AND (NOT was_live OR OLD.last_move_time IS NULL) THEN

    -- 1D. Piggyback round_started when game goes live and has a round_id.
    -- Catches rounds without starts_at or missed by cron.
    IF NEW.round_id IS NOT NULL THEN
      INSERT INTO public.notification_outbox (
        event_type,
        round_id,
        tour_id,
        group_broadcast_id,
        payload,
        dedupe_key
      )
      VALUES (
        'round_started',
        NEW.round_id,
        NEW.tour_id,
        gb_id,
        jsonb_build_object(
          'round_name', (SELECT r.name FROM public.rounds r WHERE r.id = NEW.round_id LIMIT 1),
          'starts_at', now()
        ),
        'round_started:' || NEW.round_id
      )
      ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;

    -- 1E. Suppress game_started when a round_started already covers this round.
    -- Check if a round_started notification exists for this round, created < 5 min ago.
    round_notif_exists := FALSE;
    IF NEW.round_id IS NOT NULL THEN
      SELECT EXISTS(
        SELECT 1 FROM public.notification_outbox
        WHERE dedupe_key = 'round_started:' || NEW.round_id
          AND created_at >= now() - interval '5 minutes'
      ) INTO round_notif_exists;
    END IF;

    -- Only queue game_started if no recent round_started covers it
    IF NOT round_notif_exists THEN
      INSERT INTO public.notification_outbox (
        event_type,
        game_id,
        tour_id,
        round_id,
        group_broadcast_id,
        payload,
        dedupe_key
      )
      VALUES (
        'game_started',
        NEW.id,
        NEW.tour_id,
        NEW.round_id,
        gb_id,
        jsonb_build_object(
          'status', NEW.status,
          'last_move_time', NEW.last_move_time,
          'player_white', NEW.player_white,
          'player_black', NEW.player_black
        ),
        'game_started:' || NEW.id
      )
      ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;
  END IF;

  -- Game finished: status transitioned to a finished state.
  IF is_finished AND NOT was_finished THEN
    INSERT INTO public.notification_outbox (
      event_type,
      game_id,
      tour_id,
      round_id,
      group_broadcast_id,
      payload,
      dedupe_key
    )
    VALUES (
      'game_finished',
      NEW.id,
      NEW.tour_id,
      NEW.round_id,
      gb_id,
      jsonb_build_object(
        'status', NEW.status,
        'last_move_time', NEW.last_move_time,
        'player_white', NEW.player_white,
        'player_black', NEW.player_black
      ),
      'game_finished:' || NEW.id
    )
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 1F. Schedule cron jobs
SELECT cron.schedule('queue-round-heads-up', '*/5 * * * *',
  $$SELECT public.queue_round_heads_up_notifications()$$);
SELECT cron.schedule('queue-round-started', '*/3 * * * *',
  $$SELECT public.queue_round_start_notifications()$$);
