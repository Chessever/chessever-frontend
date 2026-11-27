-- New accounts start with three engine lines (index 2), the app's default
-- since 39.8.3 (#433). Existing rows keep the value they hold: untouched
-- defaults (index 3/4) cannot be told apart from real choices.
-- Applied to production (oelbsuggrzyqwzmvidju) on 2026-11-28 as version
-- 20261127223029.
alter table public.user_engine_settings
  alter column principal_variation_index set default 2;
