-- Remove the first-report and same-day free allowances. The rewarded overload
-- still accepts a server-verified, launch-bound grant before calling this one.
CREATE OR REPLACE FUNCTION public.claim_game_analysis_report(p_fingerprint text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'auth_required', 'is_premium', false);
  END IF;
  IF nullif(btrim(coalesce(p_fingerprint, '')), '') IS NULL THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'invalid_fingerprint', 'is_premium', false);
  END IF;
  IF public._user_has_premium(v_uid) THEN
    RETURN jsonb_build_object('allowed', true, 'reason', 'premium', 'is_premium', true);
  END IF;
  RETURN jsonb_build_object('allowed', false, 'reason', 'premium_required', 'is_premium', false);
END;
$$;
REVOKE ALL ON FUNCTION public.claim_game_analysis_report(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_game_analysis_report(text) TO authenticated, service_role;
