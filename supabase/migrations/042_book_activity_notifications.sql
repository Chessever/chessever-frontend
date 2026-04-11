-- Book activity notifications for shared databases.
-- Covers:
--   1. New analyses inserted directly into a shared folder
--   2. Existing analyses moved into a shared folder
--   3. Meaningful edits inside a shared folder
--   4. Analyses removed from a shared folder (move out or delete)

CREATE OR REPLACE FUNCTION public.enqueue_book_activity_notification(
  p_event_type text,
  p_folder_id uuid,
  p_folder_name text,
  p_owner_display_name text,
  p_analysis_id uuid,
  p_game_title text,
  p_dedupe_key text
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.notification_outbox (
    event_type,
    payload,
    dedupe_key
  ) VALUES (
    p_event_type,
    jsonb_build_object(
      'folder_id', p_folder_id,
      'folder_name', p_folder_name,
      'game_title', p_game_title,
      'owner_display_name', COALESCE(p_owner_display_name, 'Someone'),
      'analysis_id', p_analysis_id
    ),
    p_dedupe_key
  )
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.queue_book_activity_notifications()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_old_folder_name text;
  v_old_owner_name text;
  v_old_is_shared boolean := false;
  v_old_has_subs boolean := false;

  v_new_folder_name text;
  v_new_owner_name text;
  v_new_is_shared boolean := false;
  v_new_has_subs boolean := false;

  v_suffix text := floor(extract(epoch from clock_timestamp()) * 1000)::bigint::text;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.folder_id IS NOT NULL THEN
    SELECT
      f.name,
      COALESCE(f.owner_display_name, 'Someone'),
      f.share_token IS NOT NULL,
      EXISTS (
        SELECT 1
        FROM public.book_subscriptions bs
        WHERE bs.folder_id = f.id
      )
    INTO
      v_old_folder_name,
      v_old_owner_name,
      v_old_is_shared,
      v_old_has_subs
    FROM public.user_folders f
    WHERE f.id = OLD.folder_id;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.folder_id IS NOT NULL THEN
    SELECT
      f.name,
      COALESCE(f.owner_display_name, 'Someone'),
      f.share_token IS NOT NULL,
      EXISTS (
        SELECT 1
        FROM public.book_subscriptions bs
        WHERE bs.folder_id = f.id
      )
    INTO
      v_new_folder_name,
      v_new_owner_name,
      v_new_is_shared,
      v_new_has_subs
    FROM public.user_folders f
    WHERE f.id = NEW.folder_id;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF v_new_is_shared AND v_new_has_subs THEN
      PERFORM public.enqueue_book_activity_notification(
        'book_game_added',
        NEW.folder_id,
        v_new_folder_name,
        v_new_owner_name,
        NEW.id,
        COALESCE(NULLIF(NEW.title, ''), 'a new game'),
        'book_game_added:' || NEW.folder_id || ':' || NEW.id
      );
    END IF;

    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF v_old_is_shared AND v_old_has_subs THEN
      PERFORM public.enqueue_book_activity_notification(
        'book_game_removed',
        OLD.folder_id,
        v_old_folder_name,
        v_old_owner_name,
        OLD.id,
        COALESCE(NULLIF(OLD.title, ''), 'a game'),
        'book_game_removed:' || OLD.folder_id || ':' || OLD.id || ':' || v_suffix
      );
    END IF;

    RETURN OLD;
  END IF;

  -- UPDATE
  IF NEW.folder_id IS DISTINCT FROM OLD.folder_id THEN
    IF v_old_is_shared AND v_old_has_subs THEN
      PERFORM public.enqueue_book_activity_notification(
        'book_game_removed',
        OLD.folder_id,
        v_old_folder_name,
        v_old_owner_name,
        OLD.id,
        COALESCE(NULLIF(OLD.title, ''), NULLIF(NEW.title, ''), 'a game'),
        'book_game_removed:' || OLD.folder_id || ':' || OLD.id || ':' || v_suffix
      );
    END IF;

    IF v_new_is_shared AND v_new_has_subs THEN
      PERFORM public.enqueue_book_activity_notification(
        'book_game_added',
        NEW.folder_id,
        v_new_folder_name,
        v_new_owner_name,
        NEW.id,
        COALESCE(NULLIF(NEW.title, ''), NULLIF(OLD.title, ''), 'a new game'),
        'book_game_added:' || NEW.folder_id || ':' || NEW.id || ':' || v_suffix
      );
    END IF;

    RETURN NEW;
  END IF;

  IF v_new_is_shared
     AND v_new_has_subs
     AND (
       NEW.chess_game IS DISTINCT FROM OLD.chess_game
       OR NEW.variation_comments IS DISTINCT FROM OLD.variation_comments
       OR NEW.title IS DISTINCT FROM OLD.title
     ) THEN
    PERFORM public.enqueue_book_activity_notification(
      'book_game_updated',
      NEW.folder_id,
      v_new_folder_name,
      v_new_owner_name,
      NEW.id,
      COALESCE(NULLIF(NEW.title, ''), 'a game'),
      'book_game_updated:' || NEW.folder_id || ':' || NEW.id || ':' || v_suffix
    );
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enqueue_book_activity_notification(
  text,
  uuid,
  text,
  text,
  uuid,
  text,
  text
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.queue_book_activity_notifications() FROM PUBLIC;

DROP TRIGGER IF EXISTS queue_book_game_added ON public.user_saved_analyses;
DROP TRIGGER IF EXISTS queue_book_game_updated ON public.user_saved_analyses;
DROP TRIGGER IF EXISTS queue_book_activity_notifications_trigger ON public.user_saved_analyses;

CREATE TRIGGER queue_book_activity_notifications_trigger
  AFTER INSERT OR UPDATE OR DELETE ON public.user_saved_analyses
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_book_activity_notifications();

CREATE OR REPLACE FUNCTION public.claim_notification_outbox_batch(p_limit integer DEFAULT 50)
RETURNS SETOF public.notification_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit integer := GREATEST(1, LEAST(COALESCE(p_limit, 50), 500));
BEGIN
  RETURN QUERY
  WITH candidates AS (
    SELECT n.id
    FROM public.notification_outbox n
    WHERE n.status = 'pending'
      AND n.not_before <= now()
    ORDER BY
      CASE n.event_type
        WHEN 'game_started'      THEN 0
        WHEN 'game_finished'     THEN 0
        WHEN 'round_started'     THEN 1
        WHEN 'round_heads_up'    THEN 1
        WHEN 'round_finished'    THEN 1
        WHEN 'book_game_added'   THEN 2
        WHEN 'book_game_updated' THEN 2
        WHEN 'book_game_removed' THEN 2
        WHEN 'call_to_action'    THEN 3
        WHEN 'live_game_update'  THEN 4
        ELSE 3
      END ASC,
      n.not_before ASC,
      n.created_at ASC
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.notification_outbox n
  SET status     = 'processing',
      attempts   = n.attempts + 1,
      updated_at = now()
  FROM candidates c
  WHERE n.id = c.id
  RETURNING n.*;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_notification_outbox_batch(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_notification_outbox_batch(integer) TO service_role;

DROP INDEX IF EXISTS idx_notification_outbox_pending_claim;
CREATE INDEX idx_notification_outbox_pending_claim
  ON public.notification_outbox (
    (CASE event_type
      WHEN 'game_started'      THEN 0
      WHEN 'game_finished'     THEN 0
      WHEN 'round_started'     THEN 1
      WHEN 'round_heads_up'    THEN 1
      WHEN 'round_finished'    THEN 1
      WHEN 'book_game_added'   THEN 2
      WHEN 'book_game_updated' THEN 2
      WHEN 'book_game_removed' THEN 2
      WHEN 'call_to_action'    THEN 3
      WHEN 'live_game_update'  THEN 4
      ELSE 3
    END),
    not_before,
    created_at,
    id
  )
  WHERE status = 'pending';
