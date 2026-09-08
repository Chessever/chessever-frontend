-- Both clients save imported PGNs in this existing, RLS-protected table.
-- Publish its changes so an already-open Library can refresh after a save
-- from another device. Preserve all existing publication members and settings.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'user_saved_analyses'
  ) THEN
    PERFORM set_config('lock_timeout', '3s', true);
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_saved_analyses;
  END IF;
END
$$;
