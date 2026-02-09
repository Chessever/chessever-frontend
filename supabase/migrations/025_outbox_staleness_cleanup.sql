-- Migration: Periodic cleanup of terminal notification_outbox rows
-- Purpose: Prevent unbounded table growth by pruning sent/skipped/failed rows older than 48 hours
-- Created: 2026-02-09

-- Cleanup function: deletes terminal rows older than 48 hours in batches
CREATE OR REPLACE FUNCTION public.cleanup_notification_outbox()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  deleted_count integer := 0;
  batch_deleted integer;
BEGIN
  -- Delete in batches of 5000 to avoid long locks
  LOOP
    DELETE FROM public.notification_outbox
    WHERE id IN (
      SELECT id FROM public.notification_outbox
      WHERE status IN ('sent', 'skipped', 'failed')
        AND created_at < now() - interval '48 hours'
      LIMIT 5000
    );
    GET DIAGNOSTICS batch_deleted = ROW_COUNT;
    deleted_count := deleted_count + batch_deleted;
    EXIT WHEN batch_deleted < 5000;
    -- Brief pause between batches to reduce lock contention
    PERFORM pg_sleep(0.1);
  END LOOP;
  RETURN deleted_count;
END;
$$;

-- Schedule cleanup every 6 hours
SELECT cron.schedule(
  'outbox-staleness-cleanup',
  '0 */6 * * *',
  $$SELECT public.cleanup_notification_outbox()$$
);
