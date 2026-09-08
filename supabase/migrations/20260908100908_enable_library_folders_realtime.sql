-- The Library stream subscribes to public.user_folders. Creating the table
-- does not add it to Realtime: subscription setup finds no matching published
-- table and returns the error captured as Sentry CHESSEVER-1WJ.
-- Publish this table without changing the publication's other tables or RLS.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'user_folders'
  ) THEN
    -- Abort rather than wait behind another migration or long transaction.
    PERFORM set_config('lock_timeout', '3s', true);
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_folders;
  END IF;
END
$$;

-- Rollback, only if this migration added the table:
-- ALTER PUBLICATION supabase_realtime DROP TABLE public.user_folders;
