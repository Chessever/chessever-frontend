-- Free-tier quota for on-device game analysis reports.
-- Premium users: unlimited. Free authenticated users: 1 new report per UTC day.
-- Authority is this RPC (not the client).

CREATE TABLE IF NOT EXISTS public.game_analysis_report_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  claim_day date NOT NULL,
  fingerprint text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT game_analysis_report_claims_user_day_unique UNIQUE (user_id, claim_day)
);

CREATE INDEX IF NOT EXISTS game_analysis_report_claims_user_day_idx
  ON public.game_analysis_report_claims (user_id, claim_day desc);

ALTER TABLE public.game_analysis_report_claims ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own analysis claims" ON public.game_analysis_report_claims;
CREATE POLICY "Users can read own analysis claims"
  ON public.game_analysis_report_claims
  FOR SELECT
  TO authenticated
  USING (user_id = (select auth.uid()));

-- No direct INSERT/UPDATE/DELETE for clients; only via claim RPC.

CREATE OR REPLACE FUNCTION public._user_has_premium(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.subscriptions s
    WHERE s.user_id = p_user_id
      AND (
        (
          s.status IN ('active', 'trialing')
          AND (s.current_period_end IS NULL OR s.current_period_end > now())
        )
        OR (
          s.status = 'past_due'
          AND s.current_period_end IS NOT NULL
          AND s.current_period_end > now()
          AND (
            s.provider <> 'stripe'
            OR s.current_period_start IS NULL
            OR s.current_period_start + interval '30 days' > now()
          )
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION public._user_has_premium(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._user_has_premium(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.claim_game_analysis_report(p_fingerprint text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_day date := (timezone('utc', now()))::date;
  v_fp text := nullif(btrim(coalesce(p_fingerprint, '')), '');
  v_existing text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'auth_required',
      'is_premium', false
    );
  END IF;

  IF v_fp IS NULL THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'invalid_fingerprint',
      'is_premium', false
    );
  END IF;

  IF public._user_has_premium(v_uid) THEN
    RETURN jsonb_build_object(
      'allowed', true,
      'reason', 'premium',
      'is_premium', true
    );
  END IF;

  SELECT c.fingerprint
  INTO v_existing
  FROM public.game_analysis_report_claims c
  WHERE c.user_id = v_uid
    AND c.claim_day = v_day;

  IF FOUND THEN
    IF v_existing = v_fp THEN
      -- Same game already claimed today: allow re-run without a second slot.
      RETURN jsonb_build_object(
        'allowed', true,
        'reason', 'same_day_same_game',
        'is_premium', false
      );
    END IF;
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'daily_limit',
      'is_premium', false
    );
  END IF;

  BEGIN
    INSERT INTO public.game_analysis_report_claims (user_id, claim_day, fingerprint)
    VALUES (v_uid, v_day, v_fp);
  EXCEPTION
    WHEN unique_violation THEN
      SELECT c.fingerprint
      INTO v_existing
      FROM public.game_analysis_report_claims c
      WHERE c.user_id = v_uid
        AND c.claim_day = v_day;
      IF v_existing = v_fp THEN
        RETURN jsonb_build_object(
          'allowed', true,
          'reason', 'same_day_same_game',
          'is_premium', false
        );
      END IF;
      RETURN jsonb_build_object(
        'allowed', false,
        'reason', 'daily_limit',
        'is_premium', false
      );
  END;

  RETURN jsonb_build_object(
    'allowed', true,
    'reason', 'claimed',
    'is_premium', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.claim_game_analysis_report(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_game_analysis_report(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_game_analysis_report(text) TO service_role;
