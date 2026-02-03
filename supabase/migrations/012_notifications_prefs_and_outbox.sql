-- Migration: Notifications preferences + outbox queue
-- Purpose: Store user push preferences and queue server-side notifications
-- Created: 2026-02-03

-- User-level notification preferences (opt-in + granularity)
CREATE TABLE IF NOT EXISTS public.user_notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  push_enabled BOOLEAN NOT NULL DEFAULT false,
  favorite_event_alerts BOOLEAN NOT NULL DEFAULT true,
  favorite_player_alerts BOOLEAN NOT NULL DEFAULT true,
  live_game_updates BOOLEAN NOT NULL DEFAULT true,
  daily_digest BOOLEAN NOT NULL DEFAULT true,
  timezone TEXT DEFAULT 'UTC',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own notification preferences"
  ON public.user_notification_preferences
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own notification preferences"
  ON public.user_notification_preferences
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own notification preferences"
  ON public.user_notification_preferences
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP TRIGGER IF EXISTS update_user_notification_preferences_updated_at
  ON public.user_notification_preferences;
CREATE TRIGGER update_user_notification_preferences_updated_at
  BEFORE UPDATE ON public.user_notification_preferences
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Notification outbox for server-side dispatching (service role only)
CREATE TABLE IF NOT EXISTS public.notification_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL,
  game_id TEXT,
  round_id TEXT,
  tour_id TEXT,
  group_broadcast_id TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  dedupe_key TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INT NOT NULL DEFAULT 0,
  last_error TEXT,
  not_before TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (dedupe_key)
);

ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_notification_outbox_status_not_before
  ON public.notification_outbox(status, not_before);
CREATE INDEX IF NOT EXISTS idx_notification_outbox_created_at
  ON public.notification_outbox(created_at DESC);

DROP TRIGGER IF EXISTS update_notification_outbox_updated_at
  ON public.notification_outbox;
CREATE TRIGGER update_notification_outbox_updated_at
  BEFORE UPDATE ON public.notification_outbox
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Helper: determine if a game status is finished
CREATE OR REPLACE FUNCTION public.is_game_finished(status TEXT)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN status IN (
    '1-0', '0-1', '1/2-1/2', '½-½', '0.5-0.5', 'W', 'B', 'D', 'DRAW'
  );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Trigger: queue notifications on game start/finish
CREATE OR REPLACE FUNCTION public.queue_game_notifications()
RETURNS TRIGGER AS $$
DECLARE
  is_live BOOLEAN;
  was_live BOOLEAN;
  is_finished BOOLEAN;
  was_finished BOOLEAN;
  gb_id TEXT;
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

DROP TRIGGER IF EXISTS queue_game_notifications ON public.games;
CREATE TRIGGER queue_game_notifications
  AFTER UPDATE OF status, last_move_time ON public.games
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_game_notifications();

-- Function: queue round start notifications (call via cron)
CREATE OR REPLACE FUNCTION public.queue_round_start_notifications()
RETURNS void AS $$
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
    AND r.starts_at <= now()
    AND r.starts_at >= now() - interval '5 minutes'
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

-- Function: queue live game update notifications (call via cron, e.g. every 1-2 minutes)
CREATE OR REPLACE FUNCTION public.queue_live_game_updates()
RETURNS void AS $$
BEGIN
  INSERT INTO public.notification_outbox (
    event_type,
    game_id,
    tour_id,
    round_id,
    group_broadcast_id,
    payload,
    dedupe_key
  )
  SELECT
    'live_game_update',
    g.id,
    g.tour_id,
    g.round_id,
    t.group_broadcast_id,
    jsonb_build_object(
      'last_move', g.last_move,
      'last_move_time', g.last_move_time,
      'player_white', g.player_white,
      'player_black', g.player_black,
      'status', g.status
    ),
    'live_game_update:' || g.id || ':' || coalesce(g.last_move_time::text, 'unknown')
  FROM public.games g
  LEFT JOIN public.tours t ON t.id = g.tour_id
  WHERE g.status IN ('*', 'ongoing')
    AND g.last_move_time IS NOT NULL
    AND g.last_move_time >= now() - interval '2 minutes'
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
