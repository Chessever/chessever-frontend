-- Force every saved analysis to live inside a folder.
--
-- Before this migration:
--   user_saved_analyses.folder_id was NULLABLE and the FK to user_folders
--   used ON DELETE SET NULL. Two failure modes followed:
--
--   1) The "remove game" UI action called moveAnalysisToFolder(id, null)
--      instead of deleteSavedAnalysis(id). Rows stayed in the table with
--      folder_id = NULL, invisible to the folder-only library UI but still
--      counted toward the free-tier 10-game save cap. Users saw the paywall
--      with "only a few games left" because phantom orphans inflated the
--      count.
--
--   2) Deleting a folder set every child analysis to folder_id = NULL
--      (SET NULL) instead of cascading the delete. Same orphan accumulation.
--
-- After this migration:
--   * folder_id is NOT NULL — inserts without a folder are rejected at the
--     DB layer, eliminating the orphan creation surface entirely.
--   * FK is ON DELETE CASCADE — deleting a folder hard-deletes every game
--     inside it. The folder-delete confirmation dialog has been rewritten
--     in both clients to communicate this.
--
-- Pre-flight: any pre-existing orphan rows were backfilled (assigned to the
-- user's "My Database" folder) ahead of the constraint flip. The DELETE
-- below is a safety net for anything that might have slipped through.

DELETE FROM public.user_saved_analyses WHERE folder_id IS NULL;

ALTER TABLE public.user_saved_analyses
  ALTER COLUMN folder_id SET NOT NULL;

ALTER TABLE public.user_saved_analyses
  DROP CONSTRAINT user_saved_analyses_folder_id_fkey;

ALTER TABLE public.user_saved_analyses
  ADD CONSTRAINT user_saved_analyses_folder_id_fkey
  FOREIGN KEY (folder_id) REFERENCES public.user_folders(id) ON DELETE CASCADE;
