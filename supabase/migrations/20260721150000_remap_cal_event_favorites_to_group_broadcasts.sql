-- Remap calendar synthetic favorite ids to group_broadcasts.id when the
-- display name matches, so onesignal-dispatch can resolve round notifications.
-- Also stamp metadata aliases for UI (Calendar / For You / Current) consistency.

-- 1) Drop pure-duplicate cal_event rows when the user already stars the GBID.
DELETE FROM public.user_favorite_events ufe
USING public.group_broadcasts gb,
      public.user_favorite_events existing
WHERE ufe.event_id LIKE 'cal_event_%'
  AND lower(gb.name) = lower(ufe.event_name)
  AND existing.user_id = ufe.user_id
  AND existing.event_id = gb.id
  AND existing.id IS DISTINCT FROM ufe.id;

-- 2) Remap remaining matchable cal_event rows → group_broadcasts.id
UPDATE public.user_favorite_events ufe
SET
  event_id = gb.id,
  metadata = coalesce(ufe.metadata, '{}'::jsonb) || jsonb_build_object(
    'source_event_id', ufe.event_id,
    'cal_event_alias', ufe.event_id
  ),
  updated_at = now()
FROM public.group_broadcasts gb
WHERE ufe.event_id LIKE 'cal_event_%'
  AND lower(gb.name) = lower(ufe.event_name)
  AND NOT EXISTS (
    SELECT 1
    FROM public.user_favorite_events other
    WHERE other.user_id = ufe.user_id
      AND other.event_id = gb.id
      AND other.id IS DISTINCT FROM ufe.id
  );

-- 3) Stamp cal_event_alias on remaining GBID favorites that lack it
UPDATE public.user_favorite_events ufe
SET
  metadata = coalesce(ufe.metadata, '{}'::jsonb) || jsonb_build_object(
    'cal_event_alias',
    'cal_event_' || lower(regexp_replace(regexp_replace(ufe.event_name, ' ', '_', 'g'), '[^\w\-]', '', 'g'))
  ),
  updated_at = now()
WHERE ufe.event_id NOT LIKE 'cal_event_%'
  AND ufe.event_id NOT LIKE 'twic_event_%'
  AND (
    ufe.metadata IS NULL
    OR NOT (ufe.metadata ? 'cal_event_alias')
  )
  AND length(trim(ufe.event_name)) > 0;
