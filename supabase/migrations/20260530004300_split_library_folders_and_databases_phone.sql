-- Split the legacy "folder that is also a database" model into two clear
-- user-facing node types:
--   * folder   : organization only; holds databases; never holds games
--   * database : holds games; the leaf of the tree
--
-- This migration is written to be SAFE FOR OLD APP BUILDS still talking to this
-- database. Older clients do not know about node_type:
--   * they omit it on insert            -> the column DEFAULT 'database' applies
--   * they may still try to save a game directly into a node we just turned into
--     a 'folder'. Instead of REJECTING that write (which would break those old
--     builds), the guard trigger AUTO-HEALS by redirecting the game into a child
--     database under that folder. New builds never hit this path because their UI
--     only ever targets 'database' nodes.
--
-- Existing data is migrated without deleting games:
--   * has child folders                 -> folder (+ existing direct games moved
--                                          into a new child database)
--   * everything else (incl. empty)     -> database  (via column DEFAULT)
--   * the special Liked Games folder     -> always stays database (likes save here)

-- 1. Column + value constraint. Default 'database' keeps old-client inserts valid.
ALTER TABLE public.user_folders
  ADD COLUMN IF NOT EXISTS node_type text NOT NULL DEFAULT 'database';

ALTER TABLE public.user_folders
  DROP CONSTRAINT IF EXISTS user_folders_node_type_check;

ALTER TABLE public.user_folders
  ADD CONSTRAINT user_folders_node_type_check
  CHECK (node_type IN ('folder', 'database'));

-- 2. Mixed legacy nodes (direct games AND child folders) can't be both at once.
--    Keep the legacy row/id as the organization folder so children/subscriptions
--    keep working, then move its direct games into a newly-created child database.
DO $$
DECLARE
  mixed record;
  new_database_id uuid;
  candidate text;
  n int;
BEGIN
  FOR mixed IN
    SELECT f.*
    FROM public.user_folders f
    WHERE f.is_liked_games = false
      AND EXISTS (
        SELECT 1 FROM public.user_saved_analyses a WHERE a.folder_id = f.id
      )
      AND EXISTS (
        SELECT 1 FROM public.user_folders child WHERE child.parent_id = f.id
      )
  LOOP
    -- user_folders has UNIQUE(user_id, name); the child database can't reuse the
    -- parent's name. Derive a free "<name> Games" variant.
    candidate := mixed.name || ' Games';
    n := 0;
    WHILE EXISTS (
      SELECT 1 FROM public.user_folders
      WHERE user_id = mixed.user_id AND name = candidate
    ) LOOP
      n := n + 1;
      candidate := mixed.name || ' Games ' || n;
    END LOOP;

    INSERT INTO public.user_folders (
      user_id, name, color, icon, order_index, parent_id, node_type
    ) VALUES (
      mixed.user_id,
      candidate,
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

-- 3. Mark as 'folder' ONLY nodes that actually contain child folders (true
--    containers). Everything else keeps the DEFAULT 'database' on purpose:
--    empty roots, empty children, and game-leaf nodes all remain saveable, and
--    the special Liked Games folder stays a database so liking keeps working.
--    (The previous version of this migration flipped every game-less node to
--    'folder', which would have broken liking for users with an empty My Likes
--    and blocked saves into every empty database — do NOT reintroduce that.)
UPDATE public.user_folders f
SET node_type = 'folder',
    icon = CASE WHEN COALESCE(icon, '') = '' THEN 'folder' ELSE icon END,
    updated_at = now()
WHERE f.is_liked_games = false
  AND EXISTS (
    SELECT 1 FROM public.user_folders child WHERE child.parent_id = f.id
  );

-- 4. Auto-healing guard. Games may only live in 'database' nodes. Rather than
--    rejecting a write that targets a 'folder' (old builds would surface a hard
--    error), transparently redirect the game into a child database under that
--    folder, creating one once and reusing it thereafter. Idempotent and safe
--    for every client version.
CREATE OR REPLACE FUNCTION public.ensure_saved_analysis_database_folder()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target record;
  redirect_id uuid;
  candidate text;
  n int;
BEGIN
  IF NEW.folder_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT id, user_id, color, order_index, node_type
    INTO target
  FROM public.user_folders
  WHERE id = NEW.folder_id;

  -- Unknown folder, or already a database -> leave the write untouched.
  IF target.id IS NULL OR target.node_type <> 'folder' THEN
    RETURN NEW;
  END IF;

  -- Reuse the earliest existing child database, else create one.
  SELECT id INTO redirect_id
  FROM public.user_folders
  WHERE parent_id = target.id AND node_type = 'database'
  ORDER BY created_at ASC
  LIMIT 1;

  IF redirect_id IS NULL THEN
    -- Respect UNIQUE(user_id, name) when minting the child database.
    candidate := 'Games';
    n := 0;
    WHILE EXISTS (
      SELECT 1 FROM public.user_folders
      WHERE user_id = target.user_id AND name = candidate
    ) LOOP
      n := n + 1;
      candidate := 'Games ' || n;
    END LOOP;

    INSERT INTO public.user_folders (
      user_id, name, color, icon, order_index, parent_id, node_type
    ) VALUES (
      target.user_id,
      candidate,
      COALESCE(target.color, '#0FB4E5'),
      'database',
      COALESCE(target.order_index, 0),
      target.id,
      'database'
    )
    RETURNING id INTO redirect_id;
  END IF;

  NEW.folder_id := redirect_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ensure_saved_analysis_database_folder_trigger
  ON public.user_saved_analyses;

CREATE TRIGGER ensure_saved_analysis_database_folder_trigger
  BEFORE INSERT OR UPDATE OF folder_id ON public.user_saved_analyses
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_saved_analysis_database_folder();
