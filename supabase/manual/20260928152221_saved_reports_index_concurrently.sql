-- Run this file on the explicitly selected database using a direct/session
-- connection with autocommit. Do NOT wrap it in a transaction or db push.
-- Allow enough statement_timeout in that maintenance session for both archive
-- scans. Do not alter database-wide, application, or role timeout settings.
--
-- Index only the candidates already requested by fetchAnalyzedGamesPage.
-- The predicates and ordering must stay in sync with that reader. PGN parsing
-- in the app still checks that the annotations belong to a played mainline move.
--
-- This changes no rows, columns, triggers, policies, or report writers. A
-- concurrent build permits existing reads/writes while scanning the archive.
-- Normal PostgreSQL index maintenance handles future PGN writebacks. The index
-- stores only the timestamp and id, never a second copy of the PGN.
--
-- IF NOT EXISTS also skips INVALID indexes left by an interrupted build.
-- Verify pg_index.indisvalid AND indisready after running. If a prior build
-- left this index invalid, drop only that invalid index CONCURRENTLY and retry.
create index concurrently if not exists games_saved_reports_page_idx
  on public.games (last_move_time desc nulls last, id asc)
  where status in ('1-0', '0-1', '1/2-1/2')
    and pgn like '%[\%eval %'
    and (pgn like '%$24%' or pgn ilike '%chessever_annotation%');
