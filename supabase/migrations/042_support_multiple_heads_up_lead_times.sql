-- Migration: Queue heads-up notifications for all supported lead times
-- Purpose:
-- 1. Preserve 5-minute default behavior
-- 2. Also support user-selected 10-minute and 30-minute heads-up windows
-- 3. Emit distinct outbox rows per round/lead-time combination

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
      'lead_minutes', lt.lead_minutes
    ),
    'round_heads_up:' || r.id || ':' || lt.lead_minutes
  FROM public.rounds r
  JOIN public.tours t ON t.id = r.tour_id
  JOIN (
    VALUES
      (5, interval '5 minutes'),
      (10, interval '10 minutes'),
      (30, interval '30 minutes')
  ) AS lt(lead_minutes, lead_interval) ON TRUE
  WHERE r.starts_at IS NOT NULL
    AND r.starts_at >= now_ts + (lt.lead_interval - interval '1 minute')
    AND r.starts_at < now_ts + (lt.lead_interval + interval '1 minute')
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
