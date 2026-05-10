-- Drop obsolete CHECK constraints on user_engine_settings.
--
-- piece_style_index_check capped the value at 4, but chessground 9.x ships 38
-- piece sets. Picking anything beyond index 4 (e.g. Fresca at 19) caused the
-- upsert to fail silently, so the next app launch re-loaded the old value from
-- Supabase and overwrote the local cache.
--
-- board_color_index_check is for a column that is no longer driven from the UI
-- (board_theme_index replaced it). Dropping it removes another silent-failure
-- vector if the deprecated column is ever written.
--
-- The Dart layer clamps both indices to the live enum length, so the DB-side
-- bound is redundant.

ALTER TABLE public.user_engine_settings
  DROP CONSTRAINT IF EXISTS piece_style_index_check;

ALTER TABLE public.user_engine_settings
  DROP CONSTRAINT IF EXISTS board_color_index_check;
