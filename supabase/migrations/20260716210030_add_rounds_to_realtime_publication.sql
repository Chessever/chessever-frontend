-- Round rows are created before play and receive starts_at when ingestion
-- detects the first moves. The Games tab needs that update in Realtime so its
-- already-visible board cards do not keep a stale null datetime snapshot.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'rounds'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.rounds;
  END IF;
END
$$;

-- Rollback:
-- ALTER PUBLICATION supabase_realtime DROP TABLE public.rounds;
