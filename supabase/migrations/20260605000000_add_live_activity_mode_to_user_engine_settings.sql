-- Live Activity / live-notification eligibility mode, mirroring pip_mode.
-- Stored as the LiveActivityMode index: 0 = off (default), 1 = live, 2 = all.
-- Read/written by the Flutter board settings provider
-- (user_engine_settings.live_activity_mode). Additive + defaulted so older
-- clients that never write the column keep working.
ALTER TABLE public.user_engine_settings
  ADD COLUMN IF NOT EXISTS live_activity_mode integer NOT NULL DEFAULT 0;
