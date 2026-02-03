-- Migration: Heads-up notification queueing
-- Purpose: Create queue function for heads-up round notifications (opt-in)
-- Created: 2026-02-03

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
      'lead_minutes', 30
    ),
    'round_heads_up:' ||
    COALESCE(t.group_broadcast_id::text, r.tour_id::text, r.id::text) || ':' ||
    FLOOR(EXTRACT(EPOCH FROM COALESCE(r.starts_at, now_ts)) / 7200)::text
  FROM public.rounds r
  JOIN public.tours t ON t.id = r.tour_id
  WHERE r.starts_at IS NOT NULL
    AND r.starts_at >= now_ts + interval '20 minutes'
    AND r.starts_at <= now_ts + interval '40 minutes'
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
