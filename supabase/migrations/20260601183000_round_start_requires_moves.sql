-- Round-start pushes must mean the games are actually live.
-- The previous scheduler queued round_started rows from the scheduled start time;
-- Armageddon/tiebreak rounds can exist at the scheduled time before any game row
-- has moved, which produced false "first moves have been played" notifications.

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
    CASE
      WHEN t.group_broadcast_id IS NOT NULL THEN
        'round_started:' ||
        t.group_broadcast_id::text || ':' ||
        EXTRACT(EPOCH FROM r.starts_at)::bigint::text
      ELSE
        'round_started:' || r.id::text
    END
  FROM public.rounds r
  JOIN public.tours t ON t.id = r.tour_id
  WHERE r.starts_at IS NOT NULL
    AND r.starts_at <= now_ts
    AND r.starts_at >= now_ts - interval '10 minutes'
    AND EXISTS (
      SELECT 1
      FROM public.games g
      WHERE g.round_id = r.id
        AND g.last_move_time IS NOT NULL
    )
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
