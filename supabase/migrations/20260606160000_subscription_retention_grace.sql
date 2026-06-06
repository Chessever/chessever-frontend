-- Subscription expiration retention grace.
-- Users who lose Pro become free immediately, but over-limit chess work is no
-- longer deleted in the RevenueCat webhook. Instead, the webhook opens this
-- grace window and a scheduled/server job enforces the two cleanup deadlines:
--   - favorites above the free cap after 7 days
--   - saved analyses/personal database overage above the free cap after 14 days
-- The app can read the row to show first-open, day-7, and tomorrow warnings.

CREATE TABLE IF NOT EXISTS public.user_subscription_retention_grace (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  expired_at timestamptz NOT NULL DEFAULT now(),
  favorite_cleanup_after timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  database_cleanup_after timestamptz NOT NULL DEFAULT (now() + interval '14 days'),
  favorite_trimmed_at timestamptz,
  database_trimmed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_subscription_retention_grace ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own subscription retention grace" ON public.user_subscription_retention_grace;
CREATE POLICY "Users can view own subscription retention grace"
  ON public.user_subscription_retention_grace
  FOR SELECT
  TO authenticated
  USING (user_id = (select auth.uid()));

CREATE INDEX IF NOT EXISTS user_subscription_retention_favorite_due_idx
  ON public.user_subscription_retention_grace (favorite_cleanup_after)
  WHERE favorite_trimmed_at IS NULL;

CREATE INDEX IF NOT EXISTS user_subscription_retention_database_due_idx
  ON public.user_subscription_retention_grace (database_cleanup_after)
  WHERE database_trimmed_at IS NULL;

GRANT SELECT ON public.user_subscription_retention_grace TO authenticated;

CREATE OR REPLACE FUNCTION public.subscription_retention_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_subscription_retention_set_updated_at
  ON public.user_subscription_retention_grace;
CREATE TRIGGER trg_subscription_retention_set_updated_at
BEFORE UPDATE ON public.user_subscription_retention_grace
FOR EACH ROW EXECUTE FUNCTION public.subscription_retention_set_updated_at();

CREATE OR REPLACE FUNCTION public.begin_subscription_retention_grace(
  p_user_id uuid,
  p_expired_at timestamptz DEFAULT now()
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expired_at timestamptz := COALESCE(p_expired_at, now());
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.user_subscription_retention_grace (
    user_id,
    expired_at,
    favorite_cleanup_after,
    database_cleanup_after,
    favorite_trimmed_at,
    database_trimmed_at
  ) VALUES (
    p_user_id,
    v_expired_at,
    v_expired_at + interval '7 days',
    v_expired_at + interval '14 days',
    NULL,
    NULL
  )
  ON CONFLICT (user_id) DO UPDATE SET
    expired_at = EXCLUDED.expired_at,
    favorite_cleanup_after = EXCLUDED.favorite_cleanup_after,
    database_cleanup_after = EXCLUDED.database_cleanup_after,
    favorite_trimmed_at = NULL,
    database_trimmed_at = NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_subscription_retention_grace(
  p_user_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  DELETE FROM public.user_subscription_retention_grace
  WHERE user_id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_subscription_retention_grace(
  p_user_id uuid DEFAULT NULL
) RETURNS TABLE(user_id uuid, favorites_deleted int, saved_analyses_deleted int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  grace_row public.user_subscription_retention_grace%ROWTYPE;
  v_favorites_deleted int;
  v_saved_deleted int;
BEGIN
  FOR grace_row IN
    SELECT *
    FROM public.user_subscription_retention_grace g
    WHERE (p_user_id IS NULL OR g.user_id = p_user_id)
      AND (
        (g.favorite_trimmed_at IS NULL AND g.favorite_cleanup_after <= now())
        OR (g.database_trimmed_at IS NULL AND g.database_cleanup_after <= now())
      )
  LOOP
    v_favorites_deleted := 0;
    v_saved_deleted := 0;

    IF grace_row.favorite_trimmed_at IS NULL
       AND grace_row.favorite_cleanup_after <= now() THEN
      v_favorites_deleted := public.trim_favorite_players_to_top_n(grace_row.user_id, 3);

      UPDATE public.user_subscription_retention_grace g
      SET favorite_trimmed_at = now()
      WHERE g.user_id = grace_row.user_id;
    END IF;

    IF grace_row.database_trimmed_at IS NULL
       AND grace_row.database_cleanup_after <= now() THEN
      v_saved_deleted := public.trim_saved_analyses_to_recent_n(grace_row.user_id, 10);

      UPDATE public.user_subscription_retention_grace g
      SET database_trimmed_at = now()
      WHERE g.user_id = grace_row.user_id;
    END IF;

    user_id := grace_row.user_id;
    favorites_deleted := v_favorites_deleted;
    saved_analyses_deleted := v_saved_deleted;
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.begin_subscription_retention_grace(uuid, timestamptz) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.clear_subscription_retention_grace(uuid) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_subscription_retention_grace(uuid) FROM public, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.begin_subscription_retention_grace(uuid, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.clear_subscription_retention_grace(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.enforce_subscription_retention_grace(uuid) TO service_role;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
GRANT USAGE ON SCHEMA cron TO postgres;
SELECT cron.unschedule('enforce-subscription-retention-grace')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'enforce-subscription-retention-grace'
);
SELECT cron.schedule(
  'enforce-subscription-retention-grace',
  '15 * * * *',
  $$SELECT public.enforce_subscription_retention_grace()$$
);
