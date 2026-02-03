-- Migration: Live game subscriptions for Live Activities + Android live notifications
-- Purpose: Track per-game live update opt-ins by platform
-- Created: 2026-02-03

CREATE TABLE IF NOT EXISTS public.user_live_game_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  game_id TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  enabled BOOLEAN NOT NULL DEFAULT true,
  started_at TIMESTAMPTZ,
  last_event_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, game_id, platform)
);

ALTER TABLE public.user_live_game_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own live game subscriptions"
  ON public.user_live_game_subscriptions
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own live game subscriptions"
  ON public.user_live_game_subscriptions
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own live game subscriptions"
  ON public.user_live_game_subscriptions
  FOR UPDATE
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_live_game_subscriptions_user_id
  ON public.user_live_game_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_live_game_subscriptions_game_id
  ON public.user_live_game_subscriptions(game_id);
CREATE INDEX IF NOT EXISTS idx_live_game_subscriptions_platform
  ON public.user_live_game_subscriptions(platform);

DROP TRIGGER IF EXISTS update_user_live_game_subscriptions_updated_at
  ON public.user_live_game_subscriptions;
CREATE TRIGGER update_user_live_game_subscriptions_updated_at
  BEFORE UPDATE ON public.user_live_game_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
