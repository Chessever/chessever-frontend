-- Migration: Persistent cache for FIDE photo fetches
-- Purpose: avoid repeated upstream calls when FIDE is down or a player has no photo
-- Created: 2026-02-17

CREATE TABLE IF NOT EXISTS public.fide_photo_fetch_cache (
  fide_id text PRIMARY KEY,
  status text NOT NULL CHECK (status IN ('photo', 'no_photo', 'fetch_failed')),
  reason text,
  storage_path text,
  checked_at timestamptz NOT NULL DEFAULT now(),
  retry_after timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fide_photo_fetch_cache_retry_after
  ON public.fide_photo_fetch_cache (retry_after);

ALTER TABLE public.fide_photo_fetch_cache ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS update_fide_photo_fetch_cache_updated_at
  ON public.fide_photo_fetch_cache;
CREATE TRIGGER update_fide_photo_fetch_cache_updated_at
  BEFORE UPDATE ON public.fide_photo_fetch_cache
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

