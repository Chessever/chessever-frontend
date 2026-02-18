-- Migration: Notification outbox batch claim performance hardening
-- Purpose: eliminate full-table polling scans and reduce queue claim contention
-- Created: 2026-02-17

-- Optimize pending queue fetch order used by the dispatcher.
CREATE INDEX IF NOT EXISTS idx_notification_outbox_pending_claim
  ON public.notification_outbox (not_before, created_at, id)
  WHERE status = 'pending';

-- Optimize terminal-row cleanup batches.
CREATE INDEX IF NOT EXISTS idx_notification_outbox_terminal_cleanup
  ON public.notification_outbox (created_at, id)
  WHERE status IN ('sent', 'skipped', 'failed');

-- Atomically claim a bounded batch from the queue.
CREATE OR REPLACE FUNCTION public.claim_notification_outbox_batch(p_limit integer DEFAULT 50)
RETURNS SETOF public.notification_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit integer := GREATEST(1, LEAST(COALESCE(p_limit, 50), 500));
BEGIN
  RETURN QUERY
  WITH candidates AS (
    SELECT n.id
    FROM public.notification_outbox n
    WHERE n.status = 'pending'
      AND n.not_before <= now()
    ORDER BY n.not_before ASC, n.created_at ASC
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.notification_outbox n
  SET status = 'processing',
      attempts = n.attempts + 1,
      updated_at = now()
  FROM candidates c
  WHERE n.id = c.id
  RETURNING n.*;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_notification_outbox_batch(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_notification_outbox_batch(integer) TO service_role;

-- Clear stale processing rows left behind by interrupted workers.
UPDATE public.notification_outbox
SET status = 'skipped',
    last_error = COALESCE(last_error, 'stale_processing_recovered'),
    updated_at = now()
WHERE status = 'processing'
  AND created_at < now() - interval '1 hour';
