-- Run outside a transaction (CREATE INDEX CONCURRENTLY takes no write lock).
-- Serves public.game_like_count: one game's likes by source_game_id.
create index concurrently if not exists user_saved_analyses_source_game_idx
  on public.user_saved_analyses (source_game_id)
  where source_game_id is not null;
