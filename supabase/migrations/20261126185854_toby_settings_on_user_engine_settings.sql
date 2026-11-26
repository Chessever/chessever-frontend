-- Toby account settings, shared by the phone, desktop/app.chessever.com and
-- chessever.com on the reader's one settings row (user_engine_settings:
-- unique per user_id, owner-only RLS, created by the first settings upsert).
--
-- toby_enabled: the reader's Toby switch in every app's settings. false turns
--   every Toby surface off (Toby Predicts, the Toby bar, Toby engine lines,
--   the Game Report's Toby rating). null = never chosen, read as on.
-- engine_source: the phone's engine lines (Stockfish or Toby; desktop and the
--   site show both side by side and do not use it). null = never chosen,
--   read as stockfish.
--
-- Additive: two nullable columns, no default, no backfill. Older builds and
-- the other upserts name their own columns and never touch these. Revert:
-- stop reading them in the apps; leave the columns (dropping loses choices).
--
-- Applied to production oelbsuggrzyqwzmvidju on 2026-11-26 (version
-- 20261126185854).

alter table public.user_engine_settings
  add column if not exists toby_enabled boolean,
  add column if not exists engine_source text
    constraint user_engine_settings_engine_source_check
    check (engine_source in ('stockfish', 'toby'));

comment on column public.user_engine_settings.toby_enabled is
  'Toby on or off in every app (Settings); null = never chosen (read as on).';
comment on column public.user_engine_settings.engine_source is
  'Phone engine lines: stockfish or toby; null = never chosen (read as stockfish).';
