-- Starts finish-live-saved-games (see 20261114060424_finish_live_saved_games).

-- Every two minutes, off the minute the dispatch jobs share. A run with
-- nothing to finish stops at the `exists` in kick_finish_live_saved_games.
select cron.schedule(
  'finish-live-saved-games',
  '1-59/2 * * * *',
  $$select public.kick_finish_live_saved_games()$$
);
