-- Migration: grouped round-start notification dedupe by exact start time
-- Purpose: A grouped event can contain several underlying tours (for example
--          Open, Women, Combined Boards) that start at the exact same time.
--          Queue one user-visible round-start notification for that grouped
--          event/start instant instead of one per raw tour round.

CREATE OR REPLACE FUNCTION public.queue_round_start_notifications()
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
    'round_started',
    r.id,
    r.tour_id,
    t.group_broadcast_id,
    jsonb_build_object(
      'round_name', r.name,
      'starts_at', r.starts_at
    ),
    'round_started:' ||
      COALESCE(t.group_broadcast_id::text, r.tour_id::text, r.id::text) || ':' ||
      EXTRACT(EPOCH FROM r.starts_at)::bigint::text
  FROM public.rounds r
  JOIN public.tours t ON t.id = r.tour_id
  WHERE r.starts_at IS NOT NULL
    AND r.starts_at <= now_ts
    AND r.starts_at >= now_ts - interval '10 minutes'
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
