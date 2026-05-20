-- Web Stripe affiliate attribution support.
-- Existing mobile attribution writes affiliate_referrals. Stripe web checkout
-- now writes the same referral table and the Stripe webhook writes the same
-- affiliate_conversions ledger.

ALTER TABLE public.affiliate_referrals
  ADD COLUMN IF NOT EXISTS is_sandbox boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS platform text;

UPDATE public.affiliate_referrals
SET is_sandbox = false
WHERE is_sandbox IS NULL;

ALTER TABLE public.affiliate_referrals
  ALTER COLUMN is_sandbox SET DEFAULT false,
  ALTER COLUMN is_sandbox SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.affiliate_referrals'::regclass
      AND conname = 'affiliate_referrals_platform_check'
  ) THEN
    ALTER TABLE public.affiliate_referrals
      ADD CONSTRAINT affiliate_referrals_platform_check
      CHECK (platform IS NULL OR platform IN ('ios', 'android', 'web', 'unknown'));
  END IF;
END $$;

ALTER TABLE public.affiliate_conversions
  ADD COLUMN IF NOT EXISTS is_sandbox boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS platform text,
  ADD COLUMN IF NOT EXISTS is_trial_period boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS stripe_event_id text,
  ADD COLUMN IF NOT EXISTS stripe_invoice_id text,
  ADD COLUMN IF NOT EXISTS stripe_subscription_id text;

UPDATE public.affiliate_conversions
SET is_sandbox = false
WHERE is_sandbox IS NULL;

UPDATE public.affiliate_conversions
SET is_trial_period = false
WHERE is_trial_period IS NULL;

ALTER TABLE public.affiliate_conversions
  ALTER COLUMN is_sandbox SET DEFAULT false,
  ALTER COLUMN is_sandbox SET NOT NULL,
  ALTER COLUMN is_trial_period SET DEFAULT false,
  ALTER COLUMN is_trial_period SET NOT NULL;

ALTER TABLE public.affiliate_conversions
  DROP CONSTRAINT IF EXISTS valid_conversion_status;

ALTER TABLE public.affiliate_conversions
  ADD CONSTRAINT valid_conversion_status
  CHECK (status IN ('pending', 'trial', 'cleared', 'refunded', 'paid'));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.affiliate_conversions'::regclass
      AND conname = 'affiliate_conversions_platform_check'
  ) THEN
    ALTER TABLE public.affiliate_conversions
      ADD CONSTRAINT affiliate_conversions_platform_check
      CHECK (platform IS NULL OR platform IN ('ios', 'android', 'web', 'unknown'));
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS affiliate_conversions_stripe_event_id_key
  ON public.affiliate_conversions (stripe_event_id)
  WHERE stripe_event_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS affiliate_conversions_stripe_invoice_id_key
  ON public.affiliate_conversions (stripe_invoice_id)
  WHERE stripe_invoice_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS affiliate_conversions_stripe_subscription_id_idx
  ON public.affiliate_conversions (stripe_subscription_id)
  WHERE stripe_subscription_id IS NOT NULL;
