-- Fix: the original policy's `f.id = folder_id` inside the EXISTS resolved
-- to bs.folder_id (the JOIN table) instead of user_saved_analyses.folder_id,
-- making it match ANY subscription. Qualify explicitly to tie back to the row.

DROP POLICY IF EXISTS "Subscribers can read shared folder analyses"
  ON public.user_saved_analyses;

CREATE POLICY "Subscribers can read shared folder analyses"
  ON public.user_saved_analyses FOR SELECT
  USING (
    folder_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.book_subscriptions bs
      JOIN public.user_folders f ON f.id = bs.folder_id
      WHERE bs.folder_id = user_saved_analyses.folder_id
        AND f.share_token IS NOT NULL
        AND bs.subscriber_id = auth.uid()
    )
  );
