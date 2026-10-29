-- Like count for one game, shown inside the heart of the board's Like button.
--
-- A like is a user_saved_analyses row inside that user's liked folder
-- (user_folders.is_liked_games = true), keyed by the original game in
-- source_game_id: the same definition as most_liked_games
-- (20260923100000_most_liked_games_rpc.sql). Those rows are private, so this
-- runs as SECURITY DEFINER and returns only the aggregate.
--
-- The caller's own like is NOT counted. The app adds it from its local liked
-- state, so the heart answers a tap at once and cannot count the caller twice
-- or miss them while the write is still in flight.
--
-- Additive only: one function and its grants. The supporting index is built
-- CONCURRENTLY from supabase/manual/20261029120001_game_like_count_index_concurrently.sql
-- so no like/save write ever waits on it. Correct without it, only slower.

create or replace function public.game_like_count(p_source_game_id text)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(distinct a.user_id)::bigint
  from public.user_saved_analyses a
  join public.user_folders f
    on f.id = a.folder_id
   and f.user_id = a.user_id
   and f.is_liked_games
  where a.source_game_id = btrim(p_source_game_id)
    and a.user_id is distinct from auth.uid();
$$;

revoke all on function public.game_like_count(text) from public;
grant execute on function public.game_like_count(text) to anon, authenticated;
