-- Migration: Align heads-up notifications with 5-minute default
-- Purpose:
-- 1. Queue round heads-up notifications ~5 minutes before start
-- 2. Run the heads-up cron every minute so the 5-minute window is reliable

CREATE OR REPLACE FUNCTION public.queue_round_heads_up_notifications()
RETURNS void AS $$
DECLARE
  now_ts TIMESTAMPTZ := now();
BEGIN
  INSERT INTO public.notification_outbox (
    event_type,
    round_id,
    tour_id,
    group_broadcast_id,
    payload,
    dedupe_key
  )
  SELECT
    'round_heads_up',
    r.id,
    r.tour_id,
    t.group_broadcast_id,
    jsonb_build_object(
      'round_name', r.name,
      'starts_at', r.starts_at,
      'lead_minutes', 5
    ),
    'round_heads_up:' || r.id
  FROM public.rounds r
  JOIN public.tours t ON t.id = r.tour_id
  WHERE r.starts_at IS NOT NULL
    AND r.starts_at >= now_ts + interval '4 minutes'
    AND r.starts_at < now_ts + interval '6 minutes'
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'queue-round-heads-up';

SELECT cron.schedule(
  'queue-round-heads-up',
  '* * * * *',
  $$SELECT public.queue_round_heads_up_notifications()$$
);
