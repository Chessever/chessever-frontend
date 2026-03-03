-- Migration: Fallback heartbeat dispatcher + cooldown window cleanup
-- Purpose: If trigger-based dispatch fails silently (pg_net issue, transient error),
--          a 1-minute cron heartbeat ensures pending items degrade to bounded delay
--          instead of silent backlog growth. Also cleans up expired cooldown windows.
-- Created: 2026-03-02

-- 1. Fallback dispatcher function — calls the edge function if there are pending items
CREATE OR REPLACE FUNCTION public.dispatch_pending_heartbeat()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pending_count integer;
  dispatch_url text;
  token text;
  hdrs jsonb;
BEGIN
  -- Only fire if there are actually pending items (avoid unnecessary HTTP calls)
  SELECT count(*) INTO pending_count
  FROM public.notification_outbox
  WHERE status = 'pending'
    AND not_before <= now()
  LIMIT 1;

  IF pending_count = 0 THEN
    RETURN;
  END IF;

  dispatch_url := public.get_vault_secret('live_dispatch_url');
  IF dispatch_url IS NULL OR dispatch_url = '' THEN
    dispatch_url := 'https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/onesignal-dispatch';
  END IF;

  token := public.get_vault_secret('live_dispatch_token');
  hdrs := jsonb_build_object('Content-Type', 'application/json');
  IF token IS NOT NULL AND token <> '' THEN
    hdrs := hdrs || jsonb_build_object('x-stream-token', token);
  END IF;

  BEGIN
    PERFORM net.http_post(
      url     := dispatch_url,
      body    := jsonb_build_object('limit', 50),
      headers := hdrs
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
END;
$$;

-- 2. Schedule 1-minute heartbeat
SELECT cron.schedule(
  'dispatch-pending-heartbeat',
  '* * * * *',
  $$SELECT public.dispatch_pending_heartbeat()$$
);

-- 3. Schedule cooldown window cleanup every 10 minutes (lightweight)
SELECT cron.schedule(
  'cleanup-notification-user-windows',
  '*/10 * * * *',
  $$SELECT public.cleanup_notification_user_windows()$$
);
