-- Run by hand with psql (NOT inside a transaction, NOT via `supabase db push`,
-- which wraps files in a transaction and would reject CONCURRENTLY):
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/manual/20260923100001_most_liked_index_concurrently.sql
--
-- Builds the partial index behind public.most_liked_games() without blocking
-- writes to user_saved_analyses. Safe to re-run: IF NOT EXISTS skips a valid
-- index. If a previous concurrent build was interrupted it leaves an INVALID
-- index of the same name; drop that one (DROP INDEX CONCURRENTLY) and re-run.
create index concurrently if not exists user_saved_analyses_liked_window_idx
  on public.user_saved_analyses (created_at, folder_id)
  where source_game_id is not null;
