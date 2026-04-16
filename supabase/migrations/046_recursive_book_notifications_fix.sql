-- Migration: Fix recursive book activity notifications
-- Purpose: Ensure notifications are enqueued for any level of folder hierarchy if a parent is shared/subscribed.
-- Created: 2026-04-16

-- 1. Helper function to check if a folder or any of its parents is shared
CREATE OR REPLACE FUNCTION public.is_folder_shared_recursive(p_folder_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_is_shared boolean;
BEGIN
  WITH RECURSIVE folder_path AS (
    SELECT id, parent_id, share_token
    FROM public.user_folders
    WHERE id = p_folder_id
    UNION ALL
    SELECT f.id, f.parent_id, f.share_token
    FROM public.user_folders f
    JOIN folder_path fp ON f.id = fp.parent_id
  )
  SELECT EXISTS (
    SELECT 1 FROM folder_path WHERE share_token IS NOT NULL
  ) INTO v_is_shared;
  
  RETURN v_is_shared;
END;
$$;

-- 2. Helper function to check if a folder or any of its parents has subscribers
CREATE OR REPLACE FUNCTION public.has_folder_subscribers_recursive(p_folder_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_has_subs boolean;
BEGIN
  WITH RECURSIVE folder_path AS (
    SELECT id, parent_id
    FROM public.user_folders
    WHERE id = p_folder_id
    UNION ALL
    SELECT f.id, f.parent_id
    FROM public.user_folders f
    JOIN folder_path fp ON f.id = fp.parent_id
  )
  SELECT EXISTS (
    SELECT 1 
    FROM public.book_subscriptions bs
    JOIN folder_path fp ON bs.folder_id = fp.id
  ) INTO v_has_subs;
  
  RETURN v_has_subs;
END;
$$;

-- 3. Update queue_book_activity_notifications to use recursive helpers
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
      COALESCE(f.owner_display_name, 'Someone')
    INTO
      v_old_folder_name,
      v_old_owner_name
    FROM public.user_folders f
    WHERE f.id = OLD.folder_id;
    
    v_old_is_shared := public.is_folder_shared_recursive(OLD.folder_id);
    v_old_has_subs := public.has_folder_subscribers_recursive(OLD.folder_id);
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.folder_id IS NOT NULL THEN
    SELECT
      f.name,
      COALESCE(f.owner_display_name, 'Someone')
    INTO
      v_new_folder_name,
      v_new_owner_name
    FROM public.user_folders f
    WHERE f.id = NEW.folder_id;
    
    v_new_is_shared := public.is_folder_shared_recursive(NEW.folder_id);
    v_new_has_subs := public.has_folder_subscribers_recursive(NEW.folder_id);
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

-- 4. Update queue_folder_activity_notifications to use recursive helpers
CREATE OR REPLACE FUNCTION public.queue_folder_activity_notifications()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_parent_id uuid;
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
  v_parent_id := COALESCE(NEW.parent_id, OLD.parent_id);
  
  IF v_parent_id IS NOT NULL THEN
    SELECT 
      f.name,
      COALESCE(f.owner_display_name, 'Someone')
    INTO v_parent_name, v_owner_name
    FROM public.user_folders f
    WHERE f.id = v_parent_id;
    
    v_parent_shared := public.is_folder_shared_recursive(v_parent_id);
    v_parent_has_subs := public.has_folder_subscribers_recursive(v_parent_id);
    
    IF v_parent_shared AND v_parent_has_subs THEN
      IF TG_OP = 'INSERT' THEN
        PERFORM public.enqueue_book_activity_notification(
          'book_folder_added',
          v_parent_id,
          v_parent_name,
          v_owner_name,
          NEW.id,
          NEW.name,
          'book_folder_added:' || NEW.id
        );
      ELSIF TG_OP = 'UPDATE' AND (NEW.name IS DISTINCT FROM OLD.name OR NEW.parent_id IS DISTINCT FROM OLD.parent_id) THEN
        PERFORM public.enqueue_book_activity_notification(
          'book_folder_updated',
          v_parent_id,
          v_parent_name,
          v_owner_name,
          NEW.id,
          NEW.name,
          'book_folder_updated:' || NEW.id || ':' || v_suffix
        );
      ELSIF TG_OP = 'DELETE' THEN
        PERFORM public.enqueue_book_activity_notification(
          'book_folder_removed',
          v_parent_id,
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
