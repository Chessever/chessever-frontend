-- Migration: Create user favorites tables
-- Purpose: Store user favorite events and players in Supabase with RLS
-- Created: 2025-10-29

-- Create user_favorite_events table
CREATE TABLE IF NOT EXISTS public.user_favorite_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_id TEXT NOT NULL,
  event_name TEXT NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, event_id)
);

-- Create user_favorite_players table
CREATE TABLE IF NOT EXISTS public.user_favorite_players (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fide_id TEXT,
  player_name TEXT NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, player_name)
);

-- Enable RLS
ALTER TABLE public.user_favorite_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_favorite_players ENABLE ROW LEVEL SECURITY;

-- Create policies for user_favorite_events
CREATE POLICY "Users can view their own favorite events"
  ON public.user_favorite_events
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own favorite events"
  ON public.user_favorite_events
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own favorite events"
  ON public.user_favorite_events
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own favorite events"
  ON public.user_favorite_events
  FOR DELETE
  USING (auth.uid() = user_id);

-- Create policies for user_favorite_players
CREATE POLICY "Users can view their own favorite players"
  ON public.user_favorite_players
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own favorite players"
  ON public.user_favorite_players
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own favorite players"
  ON public.user_favorite_players
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own favorite players"
  ON public.user_favorite_players
  FOR DELETE
  USING (auth.uid() = user_id);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_user_favorite_events_user_id ON public.user_favorite_events(user_id);
CREATE INDEX IF NOT EXISTS idx_user_favorite_events_event_id ON public.user_favorite_events(event_id);
CREATE INDEX IF NOT EXISTS idx_user_favorite_players_user_id ON public.user_favorite_players(user_id);
CREATE INDEX IF NOT EXISTS idx_user_favorite_players_fide_id ON public.user_favorite_players(fide_id);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
DROP TRIGGER IF EXISTS update_user_favorite_events_updated_at ON public.user_favorite_events;
CREATE TRIGGER update_user_favorite_events_updated_at
  BEFORE UPDATE ON public.user_favorite_events
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_user_favorite_players_updated_at ON public.user_favorite_players;
CREATE TRIGGER update_user_favorite_players_updated_at
  BEFORE UPDATE ON public.user_favorite_players
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
