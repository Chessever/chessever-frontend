-- Migration: Fix access and counts for hierarchical library folders
-- Purpose: Allow subscribers to see sub-databases and their games, and fix recursive game counts
-- Created: 2026-04-14

-- 1. Update user_folders SELECT policy to include children of subscribed folders
DROP POLICY IF EXISTS "Subscribers can read shared folders" ON public.user_folders;

CREATE POLICY "Subscribers can read shared folders"
  ON public.user_folders FOR SELECT
  USING (
    -- Direct subscription
    (share_token IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.book_subscriptions
      WHERE folder_id = public.user_folders.id AND subscriber_id = auth.uid()
    ))
    OR
    -- Child of subscribed folder
    (parent_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.book_subscriptions
      WHERE folder_id = public.user_folders.parent_id AND subscriber_id = auth.uid()
    ))
  );

-- 2. Update user_saved_analyses SELECT policy to include games in children of subscribed folders
DROP POLICY IF EXISTS "Subscribers can read shared folder analyses" ON public.user_saved_analyses;

CREATE POLICY "Subscribers can read shared folder analyses"
  ON public.user_saved_analyses FOR SELECT
  USING (
    folder_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.user_folders f
      WHERE f.id = user_saved_analyses.folder_id
      AND (
        -- Directly subscribed
        EXISTS (SELECT 1 FROM public.book_subscriptions bs WHERE bs.folder_id = f.id AND bs.subscriber_id = auth.uid())
        OR
        -- Parent is subscribed
        (f.parent_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.book_subscriptions bs WHERE bs.folder_id = f.parent_id AND bs.subscriber_id = auth.uid()))
      )
    )
  );

-- 3. Update get_shared_book RPC to include recursive count
CREATE OR REPLACE FUNCTION public.get_shared_book(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'id', f.id,
    'name', f.name,
    'color', f.color,
    'icon', f.icon,
    'owner_display_name', f.owner_display_name,
    'game_count', (
      SELECT count(*)
      FROM public.user_saved_analyses a
      WHERE a.folder_id = f.id 
         OR a.folder_id IN (SELECT id FROM public.user_folders WHERE parent_id = f.id)
    )
  ) INTO result
  FROM public.user_folders f
  WHERE f.share_token = p_token;

  RETURN result;
END;
$$;
