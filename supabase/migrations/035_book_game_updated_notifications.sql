-- Book Game Updated Notifications
-- Alerts book subscribers when a game in a shared book is updated.

-- 1. Trigger function: queue notification when a saved analysis is meaningfully updated
CREATE OR REPLACE FUNCTION public.queue_book_game_updated_notification()
RETURNS TRIGGER AS $$
DECLARE
  v_folder_name TEXT;
  v_share_token TEXT;
  v_owner_name TEXT;
  v_has_subs BOOLEAN;
BEGIN
  IF NEW.folder_id IS NULL THEN RETURN NEW; END IF;

  -- Only fire when content actually changed
  IF NEW.chess_game IS NOT DISTINCT FROM OLD.chess_game
     AND NEW.variation_comments IS NOT DISTINCT FROM OLD.variation_comments
     AND NEW.title IS NOT DISTINCT FROM OLD.title
  THEN RETURN NEW; END IF;

  SELECT f.name, f.share_token, f.owner_display_name,
         EXISTS(SELECT 1 FROM book_subscriptions bs WHERE bs.folder_id = f.id)
    INTO v_folder_name, v_share_token, v_owner_name, v_has_subs
    FROM user_folders f WHERE f.id = NEW.folder_id;

  IF v_share_token IS NULL OR NOT v_has_subs THEN RETURN NEW; END IF;

  -- dedupe_key includes epoch so repeated edits each get their own notification,
  -- but the 1-hour stale window in dispatch naturally deduplicates rapid edits.
  INSERT INTO public.notification_outbox (event_type, payload, dedupe_key)
  VALUES (
    'book_game_updated',
    jsonb_build_object(
      'folder_id', NEW.folder_id,
      'folder_name', v_folder_name,
      'game_title', NEW.title,
      'owner_display_name', COALESCE(v_owner_name, 'Someone'),
      'analysis_id', NEW.id
    ),
    'book_game_updated:' || NEW.folder_id || ':' || NEW.id || ':' || extract(epoch from now())::bigint
  ) ON CONFLICT (dedupe_key) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER queue_book_game_updated
  AFTER UPDATE ON public.user_saved_analyses
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_book_game_updated_notification();

-- 2. Add book_game_updated to the priority claim function
-- Priority 2 (same as book_game_added)
CREATE OR REPLACE FUNCTION public.claim_notification_outbox_batch(p_limit integer DEFAULT 50)
RETURNS SETOF public.notification_outbox
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_ids uuid[];
BEGIN
  SELECT array_agg(id) INTO v_ids
  FROM (
    SELECT id
    FROM public.notification_outbox
    WHERE status = 'pending'
      AND claimed_at IS NULL
      AND created_at > now() - interval '1 hour'
    ORDER BY
      CASE event_type
        WHEN 'game_started'  THEN 0
        WHEN 'game_finished' THEN 0
        WHEN 'round_started' THEN 1
        WHEN 'round_heads_up' THEN 1
        WHEN 'book_game_added' THEN 2
        WHEN 'book_game_updated' THEN 2
        WHEN 'call_to_action' THEN 3
        WHEN 'live_game_update' THEN 4
        ELSE 3
      END,
      created_at ASC
    LIMIT p_limit
  ) sub;

  IF v_ids IS NULL OR array_length(v_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.notification_outbox
     SET claimed_at = now(),
         status = 'claimed'
   WHERE id = ANY(v_ids)
     AND status = 'pending';

  RETURN QUERY
  SELECT * FROM public.notification_outbox WHERE id = ANY(v_ids);
END;
$$;

-- 3. Recreate the priority index to include book_game_updated
DROP INDEX IF EXISTS idx_notification_outbox_pending_claim;
CREATE INDEX idx_notification_outbox_pending_claim
  ON public.notification_outbox (
    status, claimed_at, created_at,
    (CASE event_type
      WHEN 'game_started'      THEN 0
      WHEN 'game_finished'     THEN 0
      WHEN 'round_started'     THEN 1
      WHEN 'round_heads_up'    THEN 1
      WHEN 'book_game_added'   THEN 2
      WHEN 'book_game_updated' THEN 2
      WHEN 'call_to_action'    THEN 3
      WHEN 'live_game_update'  THEN 4
      ELSE 3
    END)
  )
  WHERE status = 'pending';
