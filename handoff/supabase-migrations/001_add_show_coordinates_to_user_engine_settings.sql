-- Allow users to hide/show board edge coordinates (A-H, 1-8).
ALTER TABLE public.user_engine_settings
ADD COLUMN IF NOT EXISTS show_coordinates BOOLEAN NOT NULL DEFAULT true;

-- Compatibility for older feature branches that used enable_coordinates.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'user_engine_settings'
      AND column_name = 'enable_coordinates'
  ) THEN
    UPDATE public.user_engine_settings
    SET show_coordinates = enable_coordinates
    WHERE enable_coordinates IS NOT NULL;
  END IF;
END $$;
