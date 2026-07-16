-- Engine Lines PV layout: make List (index 1) the default for everyone.
-- 0 = cards, 1 = list (must match EngineLinesView enum order in
-- lib/providers/engine_settings_provider.dart).

-- New signups / rows created outside the app get List by default.
ALTER TABLE public.user_engine_settings
  ALTER COLUMN engine_lines_view_index SET DEFAULT 1;

-- Flip all existing users to List.
UPDATE public.user_engine_settings
SET engine_lines_view_index = 1,
    updated_at = now()
WHERE engine_lines_view_index <> 1;
