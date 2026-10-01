-- Run after the matching migration, outside a transaction, on the verified
-- test project. CONCURRENTLY keeps report/broadcast writes available.
create index concurrently if not exists games_report_game_classification_idx
  on public.games using gin (report_game_classification jsonb_path_ops)
  where report_game_classification is not null
    and status in ('1-0', '0-1', '1/2-1/2');
