-- Book Game Added Notifications
-- Alerts book subscribers when a new game is added to a shared book.

-- 1. Add preference column (default true — subscribers presumably want updates)
ALTER TABLE public.user_notification_preferences
  ADD COLUMN IF NOT EXISTS book_update_alerts BOOLEAN NOT NULL DEFAULT true;

-- 2. Trigger function: queue notification when a game is inserted into a shared folder
CREATE OR REPLACE FUNCTION public.queue_book_game_added_notification()
RETURNS TRIGGER AS $$
DECLARE
  v_folder_name TEXT;
  v_share_token TEXT;
  v_owner_name TEXT;
  v_has_subs BOOLEAN;
BEGIN
  -- Only fire when the analysis is placed in a folder
  IF NEW.folder_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Check if folder is shared and has subscribers
  SELECT f.name, f.share_token, f.owner_display_name,
         EXISTS(SELECT 1 FROM book_subscriptions bs WHERE bs.folder_id = f.id)
    INTO v_folder_name, v_share_token, v_owner_name, v_has_subs
    FROM user_folders f
   WHERE f.id = NEW.folder_id;

  IF v_share_token IS NULL OR NOT v_has_subs THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.notification_outbox (
    event_type, payload, dedupe_key
  ) VALUES (
    'book_game_added',
    jsonb_build_object(
      'folder_id', NEW.folder_id,
      'folder_name', v_folder_name,
      'game_title', NEW.title,
      'owner_display_name', COALESCE(v_owner_name, 'Someone'),
      'analysis_id', NEW.id
    ),
    'book_game_added:' || NEW.folder_id || ':' || NEW.id
  ) ON CONFLICT (dedupe_key) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER queue_book_game_added
  AFTER INSERT ON public.user_saved_analyses
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_book_game_added_notification();
