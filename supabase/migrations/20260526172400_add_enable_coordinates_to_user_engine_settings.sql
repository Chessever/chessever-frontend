-- Allow users to hide/show board edge coordinates (A-H, 1-8).
ALTER TABLE public.user_engine_settings
ADD COLUMN IF NOT EXISTS enable_coordinates BOOLEAN NOT NULL DEFAULT true;
