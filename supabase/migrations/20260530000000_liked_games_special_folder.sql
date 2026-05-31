-- Liked Games becomes a special per-user folder in user_folders, identical
-- in mechanics to "My Database" (auto-created for everybody). Liking a game
-- is just createSavedAnalysis() into that folder.
--
-- Drop the now-obsolete dedicated liked_games table (created earlier this
-- session, never populated).
drop policy if exists "liked_games_select_own" on public.liked_games;
drop policy if exists "liked_games_insert_own" on public.liked_games;
drop policy if exists "liked_games_delete_own" on public.liked_games;
drop table if exists public.liked_games;

-- Mark the per-user "Liked Games" folder. Partial unique index enforces at
-- most one such folder per user.
alter table public.user_folders
  add column if not exists is_liked_games boolean not null default false;

create unique index if not exists user_folders_liked_unique
  on public.user_folders (user_id) where is_liked_games;
