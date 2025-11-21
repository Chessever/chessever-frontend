-- Migration: Create library tables for saved analyses and folders
-- Purpose: Allow users to save and organize chess game analyses
-- Created: 2025-01-21

-- Create user_folders table
CREATE TABLE IF NOT EXISTS public.user_folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT DEFAULT '#0FB4E5',
  icon TEXT DEFAULT 'folder',
  order_index INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, name)
);

-- Create user_saved_analyses table
CREATE TABLE IF NOT EXISTS public.user_saved_analyses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  folder_id UUID REFERENCES public.user_folders(id) ON DELETE SET NULL,
  title TEXT NOT NULL,

  -- Original game reference (if from live game)
  source_game_id TEXT,
  source_tournament_id TEXT,

  -- Core game data (stored as JSONB for flexibility)
  chess_game JSONB NOT NULL,

  -- Analysis-specific data
  analysis_state JSONB DEFAULT '{}'::jsonb,
  variation_comments JSONB DEFAULT '{}'::jsonb,
  last_viewed_position INT DEFAULT -1,

  -- Metadata
  tags TEXT[] DEFAULT ARRAY[]::TEXT[],
  notes TEXT,
  is_favorite BOOLEAN DEFAULT false,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_opened_at TIMESTAMPTZ
);

-- Enable RLS
ALTER TABLE public.user_folders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_saved_analyses ENABLE ROW LEVEL SECURITY;

-- Create policies for user_folders
CREATE POLICY "Users can view their own folders"
  ON public.user_folders
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own folders"
  ON public.user_folders
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own folders"
  ON public.user_folders
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own folders"
  ON public.user_folders
  FOR DELETE
  USING (auth.uid() = user_id);

-- Create policies for user_saved_analyses
CREATE POLICY "Users can view their own saved analyses"
  ON public.user_saved_analyses
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own saved analyses"
  ON public.user_saved_analyses
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own saved analyses"
  ON public.user_saved_analyses
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own saved analyses"
  ON public.user_saved_analyses
  FOR DELETE
  USING (auth.uid() = user_id);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_user_folders_user_id ON public.user_folders(user_id);
CREATE INDEX IF NOT EXISTS idx_user_folders_order ON public.user_folders(user_id, order_index);

CREATE INDEX IF NOT EXISTS idx_user_saved_analyses_user_id ON public.user_saved_analyses(user_id);
CREATE INDEX IF NOT EXISTS idx_user_saved_analyses_folder_id ON public.user_saved_analyses(folder_id);
CREATE INDEX IF NOT EXISTS idx_user_saved_analyses_created_at ON public.user_saved_analyses(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_saved_analyses_favorite ON public.user_saved_analyses(user_id, is_favorite) WHERE is_favorite = true;

-- Create triggers for updated_at (reuse existing function)
DROP TRIGGER IF EXISTS update_user_folders_updated_at ON public.user_folders;
CREATE TRIGGER update_user_folders_updated_at
  BEFORE UPDATE ON public.user_folders
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_user_saved_analyses_updated_at ON public.user_saved_analyses;
CREATE TRIGGER update_user_saved_analyses_updated_at
  BEFORE UPDATE ON public.user_saved_analyses
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
