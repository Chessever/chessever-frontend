-- Book Sharing: share_token, owner_display_name, book_subscriptions
-- Enables users to share library books via deep links.

-- 1. Add share columns to user_folders
ALTER TABLE public.user_folders
  ADD COLUMN share_token TEXT UNIQUE,
  ADD COLUMN owner_display_name TEXT;

CREATE INDEX idx_user_folders_share_token ON public.user_folders (share_token)
  WHERE share_token IS NOT NULL;

-- 2. Create book_subscriptions table
CREATE TABLE public.book_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  folder_id UUID NOT NULL REFERENCES public.user_folders(id) ON DELETE CASCADE,
  subscriber_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subscribed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(folder_id, subscriber_id)
);

CREATE INDEX idx_book_subscriptions_subscriber ON public.book_subscriptions (subscriber_id);
CREATE INDEX idx_book_subscriptions_folder ON public.book_subscriptions (folder_id);

ALTER TABLE public.book_subscriptions ENABLE ROW LEVEL SECURITY;

-- Subscribers can view their own subscriptions
CREATE POLICY "Users can view own subscriptions"
  ON public.book_subscriptions FOR SELECT
  USING (auth.uid() = subscriber_id);

-- Subscribers can insert their own subscriptions (to shared folders only)
CREATE POLICY "Users can subscribe to shared books"
  ON public.book_subscriptions FOR INSERT
  WITH CHECK (
    auth.uid() = subscriber_id
    AND EXISTS (
      SELECT 1 FROM public.user_folders
      WHERE id = folder_id AND share_token IS NOT NULL
    )
  );

-- Subscribers can remove their own subscriptions
CREATE POLICY "Users can unsubscribe"
  ON public.book_subscriptions FOR DELETE
  USING (auth.uid() = subscriber_id);

-- 3. Allow subscribers to read shared folders
CREATE POLICY "Subscribers can read shared folders"
  ON public.user_folders FOR SELECT
  USING (
    share_token IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.book_subscriptions
      WHERE folder_id = id AND subscriber_id = auth.uid()
    )
  );

-- 4. Allow subscribers to read analyses in shared folders
CREATE POLICY "Subscribers can read shared folder analyses"
  ON public.user_saved_analyses FOR SELECT
  USING (
    folder_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.user_folders f
      JOIN public.book_subscriptions bs ON bs.folder_id = f.id
      WHERE f.id = folder_id
        AND f.share_token IS NOT NULL
        AND bs.subscriber_id = auth.uid()
    )
  );

-- 5. RPC function for unauthenticated web preview (anon key)
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
    )
  ) INTO result
  FROM public.user_folders f
  WHERE f.share_token = p_token;

  RETURN result;
END;
$$;
