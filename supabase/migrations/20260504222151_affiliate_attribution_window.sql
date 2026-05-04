-- Persist install time captured from AppsFlyer so affiliate payout attribution
-- can be limited to conversions that happen within the PM-approved window.
ALTER TABLE public.affiliate_referrals
  ADD COLUMN IF NOT EXISTS install_at TIMESTAMPTZ;

UPDATE public.affiliate_referrals
SET install_at = COALESCE(
  CASE
    WHEN appsflyer_data->>'install_time' ~ '^[0-9]{13}$'
      THEN to_timestamp((appsflyer_data->>'install_time')::double precision / 1000)
    WHEN appsflyer_data->>'install_time' ~ '^[0-9]{10}$'
      THEN to_timestamp((appsflyer_data->>'install_time')::double precision)
    WHEN appsflyer_data->>'install_time' ~
      '^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?$'
      THEN (replace(appsflyer_data->>'install_time', ' ', 'T') || 'Z')::timestamptz
    ELSE NULL
  END,
  created_at
)
WHERE install_at IS NULL;

CREATE INDEX IF NOT EXISTS affiliate_referrals_affiliate_code_created_at_idx
  ON public.affiliate_referrals (affiliate_code, created_at DESC);

CREATE INDEX IF NOT EXISTS affiliate_conversions_affiliate_code_created_at_idx
  ON public.affiliate_conversions (affiliate_code, created_at DESC);
