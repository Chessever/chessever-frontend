-- Follow-up to grouped round-start notification dedupe.
-- The visible dedupe identity is group_broadcast_id + round name + exact start
-- instant, matching the Edge Function collapse key. This keeps Open/Women/
-- Combined copies of the same visible round to one push, without collapsing
-- distinct named rounds that happen to share a grouped event start timestamp.

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
      WHEN t.group_broadcast_id IS NOT NULL AND nullif(btrim(r.name), '') IS NOT NULL THEN
        'round_started:' ||
        t.group_broadcast_id::text || ':' ||
        lower(regexp_replace(btrim(r.name), '\s+', ' ', 'g')) || ':' ||
        EXTRACT(EPOCH FROM r.starts_at)::bigint::text
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
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
