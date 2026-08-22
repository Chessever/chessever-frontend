-- Smart-event opening queries first locate the newest matching game_day, then
-- load that day's games ordered by recency/rating. ECO filters are emitted as
-- equality or IN predicates, so this one partial B-tree serves exact codes,
-- named families, and irregular inclusive ECO ranges without ILIKE scans.
create index if not exists idx_games_eco_game_day_last_move
on public.games (
  eco,
  game_day desc nulls last,
  last_move_time desc nulls last,
  player_max_rating desc nulls last,
  id
)
where eco is not null and game_day is not null;
