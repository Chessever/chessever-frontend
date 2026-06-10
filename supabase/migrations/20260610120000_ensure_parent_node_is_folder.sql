-- Backwards-compat heal for old app builds that still seed the legacy
-- database -> subdatabase structure ("My Database" -> "My Subdatabase")
-- without a node_type. The column default makes both 'database', leaving the
-- child unreachable in the new Folder/Database UI (a database screen lists
-- games, not child nodes).
--
-- 1) One-time fix: any zero-game 'database' that has child nodes becomes a
--    'folder' (a folder must never contain games, so games-holding parents
--    are left untouched).
-- 2) Trigger: future child inserts/moves under a 'database' parent promote
--    that parent to 'folder' under the same zero-games guard. Complements
--    ensure_saved_analysis_database_folder(), which heals the other
--    direction (game-writes aimed at 'folder' nodes).
--
-- Applied to prod 2026-06-10 via supabase db query (remote migration history
-- has diverged from this directory; file kept for the record).

BEGIN;

UPDATE public.user_folders p SET node_type = 'folder'
WHERE p.node_type = 'database'
  AND EXISTS (SELECT 1 FROM public.user_folders c WHERE c.parent_id = p.id)
  AND NOT EXISTS (SELECT 1 FROM public.user_saved_analyses g WHERE g.folder_id = p.id);

CREATE OR REPLACE FUNCTION public.ensure_parent_node_is_folder()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  parent record;
BEGIN
  IF NEW.parent_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT id, node_type INTO parent
  FROM public.user_folders
  WHERE id = NEW.parent_id;

  IF parent.id IS NULL OR parent.node_type = 'folder' THEN
    RETURN NEW;
  END IF;

  -- Old app builds still create database -> subdatabase. Promote the parent
  -- to a folder so the child stays reachable in the new UI, but only when the
  -- parent holds no games (a folder must never contain games).
  IF NOT EXISTS (
    SELECT 1 FROM public.user_saved_analyses g WHERE g.folder_id = parent.id
  ) THEN
    UPDATE public.user_folders SET node_type = 'folder' WHERE id = parent.id;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS ensure_parent_node_is_folder_trigger ON public.user_folders;
CREATE TRIGGER ensure_parent_node_is_folder_trigger
BEFORE INSERT OR UPDATE OF parent_id ON public.user_folders
FOR EACH ROW EXECUTE FUNCTION public.ensure_parent_node_is_folder();

COMMIT;
