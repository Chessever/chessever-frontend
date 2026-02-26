-- Migration 031: Optimize library book queries for pagination at scale
--
-- Problems addressed:
-- 1. No composite index for paginated folder content queries (seq scan)
-- 2. No composite index for bulk-save dedup checks (seq scan on IN clause)
-- 3. RLS policies on book_subscriptions use auth.uid() without (select ...)
--    wrapper, causing per-row re-evaluation instead of once-per-query
-- 4. Multiple permissive SELECT policies on user_folders and
--    user_saved_analyses both evaluate for every query (suboptimal)

-- ============================================================
-- 1. INDEXES
-- ============================================================

-- Paginated folder content: WHERE user_id=X AND folder_id=Y ORDER BY created_at DESC LIMIT N
CREATE INDEX IF NOT EXISTS idx_usa_user_folder_created
  ON public.user_saved_analyses (user_id, folder_id, created_at DESC);

-- Dedup check during bulk save: WHERE user_id=X AND folder_id=Y AND source_game_id IN (...)
CREATE INDEX IF NOT EXISTS idx_usa_user_folder_source_game
  ON public.user_saved_analyses (user_id, folder_id, source_game_id)
  WHERE source_game_id IS NOT NULL;

-- ============================================================
-- 2. FIX RLS: book_subscriptions
--    Wrap auth.uid() in (select ...) for initplan optimization
-- ============================================================

DROP POLICY IF EXISTS "Users can view own subscriptions" ON public.book_subscriptions;
CREATE POLICY "Users can view own subscriptions"
  ON public.book_subscriptions FOR SELECT
  USING ((select auth.uid()) = subscriber_id);

DROP POLICY IF EXISTS "Users can subscribe to shared books" ON public.book_subscriptions;
CREATE POLICY "Users can subscribe to shared books"
  ON public.book_subscriptions FOR INSERT
  WITH CHECK (
    (select auth.uid()) = subscriber_id
    AND EXISTS (
      SELECT 1 FROM public.user_folders
      WHERE id = book_subscriptions.folder_id
        AND share_token IS NOT NULL
    )
  );

DROP POLICY IF EXISTS "Users can unsubscribe" ON public.book_subscriptions;
CREATE POLICY "Users can unsubscribe"
  ON public.book_subscriptions FOR DELETE
  USING ((select auth.uid()) = subscriber_id);

-- ============================================================
-- 3. FIX RLS: user_folders
--    Merge two permissive SELECT policies into one
-- ============================================================

DROP POLICY IF EXISTS "Users can view their own folders" ON public.user_folders;
DROP POLICY IF EXISTS "Anyone can view shared folders" ON public.user_folders;
CREATE POLICY "Users can view own or shared folders"
  ON public.user_folders FOR SELECT
  USING (
    (select auth.uid()) = user_id
    OR share_token IS NOT NULL
  );

-- ============================================================
-- 4. FIX RLS: user_saved_analyses
--    Merge two permissive SELECT policies into one + fix initplan
-- ============================================================

DROP POLICY IF EXISTS "Users can view their own saved analyses" ON public.user_saved_analyses;
DROP POLICY IF EXISTS "Subscribers can read shared folder analyses" ON public.user_saved_analyses;
CREATE POLICY "Users can view own or subscribed analyses"
  ON public.user_saved_analyses FOR SELECT
  USING (
    (select auth.uid()) = user_id
    OR (
      folder_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.book_subscriptions bs
        JOIN public.user_folders f ON f.id = bs.folder_id
        WHERE bs.folder_id = user_saved_analyses.folder_id
          AND f.share_token IS NOT NULL
          AND bs.subscriber_id = (select auth.uid())
      )
    )
  );
