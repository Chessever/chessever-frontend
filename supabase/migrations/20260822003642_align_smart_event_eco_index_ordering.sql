-- The test branch briefly received the first index with PostgreSQL's default
-- DESC null ordering. Rebuild only that shape so the newest-day LIMIT query
-- can consume index order directly. Fresh databases already get NULLS LAST
-- from the preceding migration and skip this block.
do $$
declare
  current_definition text;
begin
  select indexdef
  into current_definition
  from pg_indexes
  where schemaname = 'public'
    and indexname = 'idx_games_eco_game_day_last_move';

  if current_definition is null
     or current_definition not like '%game_day DESC NULLS LAST%' then
    drop index if exists public.idx_games_eco_game_day_last_move;

    create index idx_games_eco_game_day_last_move
    on public.games (
      eco,
      game_day desc nulls last,
      last_move_time desc nulls last,
      player_max_rating desc nulls last,
      id
    )
    where eco is not null and game_day is not null;
  end if;
end
$$;
