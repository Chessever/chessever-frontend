-- Migration: Add subfolder support to user_folders
-- Purpose: Allow 2-layer hierarchy for chess databases
-- Created: 2026-04-13

-- Add parent_id column to user_folders
ALTER TABLE public.user_folders 
ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES public.user_folders(id) ON DELETE CASCADE;

-- Add index for performance when querying children
CREATE INDEX IF NOT EXISTS idx_user_folders_parent_id ON public.user_folders(parent_id);

-- Add comment for documentation
COMMENT ON COLUMN public.user_folders.parent_id IS 'Self-referencing parent ID to support hierarchical folders (databases). Null for root folders.';
