-- Migration: Recursive book activity notifications
-- Purpose: Notify subscribers of parent folders for any update in sub-folders, and folder-level changes.
-- Created: 2026-04-15

-- 1. Update queue_book_activity_notifications to check for parent subscribers
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
      (f.share_token IS NOT NULL OR (f.parent_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.user_folders pf WHERE pf.id = f.parent_id AND pf.share_token IS NOT NULL))),
      EXISTS (
        SELECT 1
        FROM public.book_subscriptions bs
        WHERE bs.folder_id = f.id
           OR (f.parent_id IS NOT NULL AND bs.folder_id = f.parent_id)
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
      (f.share_token IS NOT NULL OR (f.parent_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.user_folders pf WHERE pf.id = f.parent_id AND pf.share_token IS NOT NULL))),
      EXISTS (
        SELECT 1
        FROM public.book_subscriptions bs
        WHERE bs.folder_id = f.id
           OR (f.parent_id IS NOT NULL AND bs.folder_id = f.parent_id)
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

-- 2. Add trigger for folder-level activity notifications
CREATE OR REPLACE FUNCTION public.queue_folder_activity_notifications()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_parent_shared boolean := false;
  v_parent_has_subs boolean := false;
  v_parent_name text;
  v_owner_name text;
  v_suffix text := floor(extract(epoch from clock_timestamp()) * 1000)::bigint::text;
BEGIN
  -- Handle root folder name changes
  IF TG_OP = 'UPDATE' AND OLD.parent_id IS NULL AND NEW.name IS DISTINCT FROM OLD.name THEN
    IF NEW.share_token IS NOT NULL THEN
      IF EXISTS (SELECT 1 FROM public.book_subscriptions WHERE folder_id = NEW.id) THEN
        PERFORM public.enqueue_book_activity_notification(
          'book_folder_updated',
          NEW.id,
          OLD.name,
          COALESCE(NEW.owner_display_name, 'Someone'),
          NEW.id,
          NEW.name,
          'book_database_renamed:' || NEW.id || ':' || v_suffix
        );
      END IF;
    END IF;
  END IF;

  -- Handle sub-folder activity (recursive)
  IF (TG_OP = 'INSERT' AND NEW.parent_id IS NOT NULL) OR 
     (TG_OP = 'UPDATE' AND NEW.parent_id IS NOT NULL) OR
     (TG_OP = 'DELETE' AND OLD.parent_id IS NOT NULL) THEN
     
    SELECT 
      f.share_token IS NOT NULL OR (f.parent_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.user_folders pf WHERE pf.id = f.parent_id AND pf.share_token IS NOT NULL)),
      EXISTS (
        SELECT 1 
        FROM public.book_subscriptions bs 
        WHERE bs.folder_id = f.id 
           OR (f.parent_id IS NOT NULL AND bs.folder_id = f.parent_id)
      ),
      f.name,
      COALESCE(f.owner_display_name, 'Someone')
    INTO v_parent_shared, v_parent_has_subs, v_parent_name, v_owner_name
    FROM public.user_folders f
    WHERE f.id = COALESCE(NEW.parent_id, OLD.parent_id);
    
    IF v_parent_shared AND v_parent_has_subs THEN
      IF TG_OP = 'INSERT' THEN
        PERFORM public.enqueue_book_activity_notification(
          'book_folder_added',
          COALESCE(NEW.parent_id, OLD.parent_id),
          v_parent_name,
          v_owner_name,
          NEW.id,
          NEW.name,
          'book_folder_added:' || NEW.id
        );
      ELSIF TG_OP = 'UPDATE' AND (NEW.name IS DISTINCT FROM OLD.name OR NEW.parent_id IS DISTINCT FROM OLD.parent_id) THEN
        PERFORM public.enqueue_book_activity_notification(
          'book_folder_updated',
          NEW.parent_id,
          v_parent_name,
          v_owner_name,
          NEW.id,
          NEW.name,
          'book_folder_updated:' || NEW.id || ':' || v_suffix
        );
      ELSIF TG_OP = 'DELETE' THEN
        PERFORM public.enqueue_book_activity_notification(
          'book_folder_removed',
          OLD.parent_id,
          v_parent_name,
          v_owner_name,
          OLD.id,
          OLD.name,
          'book_folder_removed:' || OLD.id || ':' || v_suffix
        );
      END IF;
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS queue_folder_activity_notifications_trigger ON public.user_folders;
CREATE TRIGGER queue_folder_activity_notifications_trigger
  AFTER INSERT OR UPDATE OR DELETE ON public.user_folders
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_folder_activity_notifications();
