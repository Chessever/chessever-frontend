-- Split the legacy "folder that is also a database" model into two clear
-- user-facing node types:
--   * folder   : organization only; can contain folders/databases; no games
--   * database : contains games; cannot contain child nodes going forward
--
-- Existing data is migrated without deleting games:
--   * only games       -> database
--   * only children    -> folder
--   * games + children -> folder + a new child database holding the games
--   * empty            -> folder

ALTER TABLE public.user_folders
  ADD COLUMN IF NOT EXISTS node_type text NOT NULL DEFAULT 'database';

ALTER TABLE public.user_folders
  DROP CONSTRAINT IF EXISTS user_folders_node_type_check;

ALTER TABLE public.user_folders
  ADD CONSTRAINT user_folders_node_type_check
  CHECK (node_type IN ('folder', 'database'));

-- Mixed legacy nodes need to stop being both things at once. Keep the legacy
-- row/id as the organization folder so children/subscriptions keep working,
-- then move its direct games into a newly-created database under it.
DO $$
DECLARE
  mixed record;
  new_database_id uuid;
BEGIN
  FOR mixed IN
    SELECT f.*
    FROM public.user_folders f
    WHERE EXISTS (
      SELECT 1 FROM public.user_saved_analyses a WHERE a.folder_id = f.id
    )
    AND EXISTS (
      SELECT 1 FROM public.user_folders child WHERE child.parent_id = f.id
    )
  LOOP
    INSERT INTO public.user_folders (
      user_id,
      name,
      color,
      icon,
      order_index,
      parent_id,
      node_type
    ) VALUES (
      mixed.user_id,
      mixed.name,
      mixed.color,
      COALESCE(NULLIF(mixed.icon, ''), 'database'),
      mixed.order_index,
      mixed.id,
      'database'
    )
    RETURNING id INTO new_database_id;

    UPDATE public.user_saved_analyses
    SET folder_id = new_database_id
    WHERE folder_id = mixed.id;

    UPDATE public.user_folders
    SET node_type = 'folder', icon = 'folder', updated_at = now()
    WHERE id = mixed.id;
  END LOOP;
END $$;

-- Legacy nodes with no direct games are organizational folders. Nodes with
-- direct games and no children remain databases.
UPDATE public.user_folders f
SET node_type = 'folder',
    icon = CASE WHEN COALESCE(icon, '') = '' THEN 'folder' ELSE icon END,
    updated_at = now()
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_saved_analyses a WHERE a.folder_id = f.id
);

-- Guard the new invariant at the database level: games may only point at
-- database nodes. The trigger is intentionally NOT VALIDATED against old app
-- versions at compile time; it checks runtime rows and rejects future writes
-- into organization folders.
CREATE OR REPLACE FUNCTION public.ensure_saved_analysis_database_folder()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.folder_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.user_folders f
    WHERE f.id = NEW.folder_id
      AND f.node_type = 'folder'
  ) THEN
    RAISE EXCEPTION 'Cannot save games directly into an organization folder';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ensure_saved_analysis_database_folder_trigger
  ON public.user_saved_analyses;

CREATE TRIGGER ensure_saved_analysis_database_folder_trigger
  BEFORE INSERT OR UPDATE OF folder_id ON public.user_saved_analyses
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_saved_analysis_database_folder();
