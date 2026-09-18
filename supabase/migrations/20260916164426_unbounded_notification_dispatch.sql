-- Unbounded notification dispatch.
--
-- Olympiad 2026 R1 Open is 404 boards. The dispatcher built one PostgREST
-- GET `.in(player_name, ~800 names)`, the gateway returned 400, and
-- requeue_stuck_notification_outbox then burned the grouped round_started
-- row after six abandoned claims (`stuck_processing_gave_up`).
--
-- This migration:
--   1. Matches favorites in Postgres (`= ANY(array)`) so the URL is never
--      the size of the round.
--   2. Stops treating "the edge function ran out of time" as a terminal
--      failure. A killed invocation leaves the row in `processing`; we put
--      it back to `pending` forever. Only processItem's explicit markFailed
--      may burn a row.
--   3. Drops the 500-row claim ceiling. A claim page is a work unit, not a
--      product max — the dispatcher drains until the queue is empty.
--   4. Heartbeat / poke no longer send `limit: 50` as if that were the max.

CREATE OR REPLACE FUNCTION public.match_notification_favorite_players(
  p_fide_ids text[] DEFAULT '{}'::text[],
  p_names text[] DEFAULT '{}'::text[],
  p_user_ids uuid[] DEFAULT NULL,
  p_offset integer DEFAULT 0,
  p_limit integer DEFAULT 1000
)
RETURNS TABLE (
  user_id uuid,
  fide_id text,
  player_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT ufp.user_id, ufp.fide_id, ufp.player_name
  FROM public.user_favorite_players ufp
  WHERE (p_user_ids IS NULL OR ufp.user_id = ANY (p_user_ids))
    AND (
      (
        COALESCE(cardinality(p_fide_ids), 0) > 0
        AND ufp.fide_id = ANY (p_fide_ids)
      )
      OR (
        COALESCE(cardinality(p_names), 0) > 0
        AND ufp.player_name = ANY (p_names)
      )
    )
  ORDER BY ufp.user_id, ufp.id
  OFFSET GREATEST(0, COALESCE(p_offset, 0))
  LIMIT GREATEST(1, COALESCE(p_limit, 1000));
$$;

COMMENT ON FUNCTION public.match_notification_favorite_players(text[], text[], uuid[], integer, integer) IS
  'onesignal-dispatch favorite match. Arrays travel in the POST body; page with offset/limit. LIMIT is a page, not a cap — the caller loops until a short page.';

REVOKE ALL ON FUNCTION public.match_notification_favorite_players(text[], text[], uuid[], integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.match_notification_favorite_players(text[], text[], uuid[], integer, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.outbox_has_due_work()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.notification_outbox
    WHERE status = 'pending'
      AND not_before <= now()
  );
$$;

REVOKE ALL ON FUNCTION public.outbox_has_due_work() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.outbox_has_due_work() TO service_role;

CREATE OR REPLACE FUNCTION public.claim_notification_outbox_batch(p_limit integer DEFAULT 50)
RETURNS SETOF public.notification_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit integer := GREATEST(1, COALESCE(p_limit, 50));
BEGIN
  RETURN QUERY
  WITH candidates AS (
    SELECT n.id
    FROM public.notification_outbox n
    WHERE n.status = 'pending'
      AND n.not_before <= now()
    ORDER BY
      CASE n.event_type
        WHEN 'game_started'      THEN 0
        WHEN 'game_finished'     THEN 0
        WHEN 'round_started'     THEN 1
        WHEN 'round_heads_up'    THEN 1
        WHEN 'round_finished'    THEN 1
        WHEN 'book_game_added'   THEN 2
        WHEN 'book_game_updated' THEN 2
        WHEN 'book_game_removed' THEN 2
        WHEN 'call_to_action'    THEN 3
        WHEN 'live_game_update'  THEN 4
        ELSE 3
      END ASC,
      n.not_before ASC,
      n.created_at ASC
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.notification_outbox n
  SET status     = 'processing',
      attempts   = n.attempts + 1,
      updated_at = now()
  FROM candidates c
  WHERE n.id = c.id
  RETURNING n.*;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_notification_outbox_batch(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_notification_outbox_batch(integer) TO service_role;

-- A wall-clock kill is not a verdict. Put the row back. processItem is the
-- only path allowed to mark failed.
CREATE OR REPLACE FUNCTION public.requeue_stuck_notification_outbox()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_requeued integer;
BEGIN
  UPDATE public.notification_outbox
     SET status = 'pending',
         last_error = 'requeued_stuck_processing',
         not_before = now()
   WHERE status = 'processing'
     AND updated_at < now() - interval '2 minutes';

  GET DIAGNOSTICS v_requeued = ROW_COUNT;
  RETURN v_requeued;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.requeue_stuck_notification_outbox() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.requeue_stuck_notification_outbox() TO service_role;

CREATE OR REPLACE FUNCTION public.dispatch_pending_heartbeat()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  dispatch_url text;
  token text;
  hdrs jsonb;
BEGIN
  IF NOT public.outbox_has_due_work() THEN
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
      body    := '{}'::jsonb,
      headers := hdrs
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.dispatch_notification_now()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  dispatch_url text;
  token text;
  hdrs jsonb;
BEGIN
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
      body    := '{}'::jsonb,
      headers := hdrs
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
END;
$$;
