-- Unified premium authority shared by mobile, desktop, and web.
-- RevenueCat and Stripe webhooks write here; every frontend reads either this
-- RLS-protected table/view or the entitlement edge function built on top of it.

CREATE TABLE IF NOT EXISTS public.subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider text NOT NULL CHECK (provider IN ('stripe','revenuecat','apple','google')),
  status text NOT NULL,
  tier int CHECK (tier IN (1,2,3)),
  product_id text,
  price_id text,
  price_lookup_key text,
  interval text CHECK (interval IN ('month','year')),
  currency text,
  amount_cents int,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at timestamptz,
  canceled_at timestamptz,
  trial_end timestamptz,
  stripe_customer_id text,
  stripe_subscription_id text UNIQUE,
  rc_app_user_id text,
  rc_original_app_user_id text,
  raw jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS subscriptions_user_status_idx
  ON public.subscriptions (user_id, status);

CREATE INDEX IF NOT EXISTS subscriptions_provider_user_idx
  ON public.subscriptions (provider, user_id);

CREATE INDEX IF NOT EXISTS subscriptions_period_end_idx
  ON public.subscriptions (current_period_end);

CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_non_stripe_identity_idx
  ON public.subscriptions (provider, user_id, product_id)
  WHERE provider IN ('revenuecat','apple','google');

CREATE OR REPLACE FUNCTION public.subscriptions_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_subscriptions_set_updated_at ON public.subscriptions;
CREATE TRIGGER trg_subscriptions_set_updated_at
BEFORE UPDATE ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION public.subscriptions_set_updated_at();

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Subscribers can view own row" ON public.subscriptions;
CREATE POLICY "Subscribers can view own row"
  ON public.subscriptions
  FOR SELECT
  TO authenticated
  USING (user_id = (select auth.uid()));

CREATE TABLE IF NOT EXISTS public.user_stripe_customers (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  stripe_customer_id text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_stripe_customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "User reads own stripe customer" ON public.user_stripe_customers;
CREATE POLICY "User reads own stripe customer"
  ON public.user_stripe_customers
  FOR SELECT
  TO authenticated
  USING (user_id = (select auth.uid()));

CREATE OR REPLACE VIEW public.user_premium_view
WITH (security_invoker = true) AS
SELECT DISTINCT ON (user_id)
  user_id,
  status,
  provider,
  tier,
  current_period_end,
  cancel_at,
  trial_end,
  product_id,
  interval,
  (status IN ('active','trialing')
    AND (current_period_end IS NULL OR current_period_end > now())) AS is_premium
FROM public.subscriptions
ORDER BY user_id,
         (status IN ('active','trialing')) DESC,
         current_period_end DESC NULLS LAST,
         updated_at DESC;

GRANT SELECT ON public.user_premium_view TO authenticated;
