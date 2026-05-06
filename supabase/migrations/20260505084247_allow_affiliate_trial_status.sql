ALTER TABLE public.affiliate_conversions
  DROP CONSTRAINT IF EXISTS valid_conversion_status;

ALTER TABLE public.affiliate_conversions
  ADD CONSTRAINT valid_conversion_status
  CHECK (status IN ('pending', 'trial', 'cleared', 'refunded', 'paid'));

CREATE INDEX IF NOT EXISTS affiliate_conversions_referred_user_id_idx
  ON public.affiliate_conversions (referred_user_id);
