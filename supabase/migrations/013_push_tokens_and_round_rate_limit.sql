-- Migration: Push token tracking + round rate limiting + heads-up pref
-- Purpose: Track OneSignal tokens, enforce round notification throttle, add heads-up toggle
-- Created: 2026-02-03

-- Add heads-up toggle (off by default)
ALTER TABLE public.user_notification_preferences
  ADD COLUMN IF NOT EXISTS heads_up_alerts BOOLEAN NOT NULL DEFAULT false;

-- Track device push tokens / subscription IDs
CREATE TABLE IF NOT EXISTS public.user_push_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL DEFAULT 'onesignal',
  subscription_id TEXT NOT NULL,
  push_token TEXT,
  platform TEXT,
  opted_in BOOLEAN NOT NULL DEFAULT true,
  app_version TEXT,
  device_model TEXT,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, subscription_id)
);

ALTER TABLE public.user_push_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own push tokens"
  ON public.user_push_tokens
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own push tokens"
  ON public.user_push_tokens
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own push tokens"
  ON public.user_push_tokens
  FOR UPDATE
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_user_push_tokens_user_id
  ON public.user_push_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_user_push_tokens_subscription_id
  ON public.user_push_tokens(subscription_id);
CREATE INDEX IF NOT EXISTS idx_user_favorite_players_player_name
  ON public.user_favorite_players(player_name);
CREATE INDEX IF NOT EXISTS idx_games_round_id
  ON public.games(round_id);

DROP TRIGGER IF EXISTS update_user_push_tokens_updated_at
  ON public.user_push_tokens;
CREATE TRIGGER update_user_push_tokens_updated_at
  BEFORE UPDATE ON public.user_push_tokens
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Replace round start queue function to enforce 2-hour rate limit per event
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
    'round_started:' ||
    COALESCE(t.group_broadcast_id::text, r.tour_id::text, r.id::text) || ':' ||
    FLOOR(EXTRACT(EPOCH FROM COALESCE(r.starts_at, now_ts)) / 7200)::text
  FROM public.rounds r
  JOIN public.tours t ON t.id = r.tour_id
  WHERE r.starts_at IS NOT NULL
    AND r.starts_at <= now_ts
    AND r.starts_at >= now_ts - interval '10 minutes'
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
