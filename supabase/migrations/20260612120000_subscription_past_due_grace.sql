-- Honor a billing-retry grace window on past_due subscriptions.
--
-- Background: prior to this migration `user_premium_view.is_premium` was
-- true only for `status IN ('active','trialing')`. The instant a
-- subscription flipped to `past_due` — Stripe renewal charge failed, or the
-- RC webhook mirrored a store BILLING_ISSUE — the user lost Premium, even
-- though Stripe Smart Retries keeps retrying the card for weeks and the
-- stores grant their own billing-retry grace. The in-app billing-issue
-- popups (BillingIssueGate on mobile / desktop) depend on is_premium
-- staying true during that window: they only fire for subscribed users.
--
-- Stripe period semantics (API 2024-12-18.acacia, see _shared/stripe.ts):
-- when a renewal invoice fails, the subscription's current_period_end has
-- already advanced to the end of the NEW (unpaid) period — a future
-- timestamp — and status goes past_due while Smart Retries runs. So
-- granting `past_due AND current_period_end > now()` keeps access through
-- the retry window; when Stripe exhausts retries it flips the subscription
-- to canceled/unpaid (dashboard: Billing -> Subscriptions and emails ->
-- Manage failed payments) and access ends there, well before period end
-- for monthly plans.
--
-- The 30-day cap (Stripe rows only) bounds the worst case for YEARLY
-- plans: without it, a misconfigured "leave subscription past_due" final
-- action would hand out up to a year of free access. current_period_start
-- is the start of the unpaid period, so the cap reads "at most 30 days of
-- grace from the moment the failed period began". Store-billed rows are
-- exempt because their current_period_start mirrors RevenueCat's
-- purchase_date (can legitimately be ~a year old on annual plans) while
-- their current_period_end is RC's authoritative grace cutoff.
--
-- Store-billed rows (provider apple/google/revenuecat) reach past_due two
-- ways:
--   * entitlement edge fn live-sync: billing issue on a still-active
--     entitlement -> status past_due with current_period_end = RC
--     expires_date (extended into the future during store grace) -> grace
--     clause grants access until the store gives up.
--   * RC webhook BILLING_ISSUE / markRevenueCatRowsInactive after the
--     entitlement died -> current_period_end in the past -> no access.
--     The store didn't grant grace, so neither do we.
--
-- Renewal / restore: a successful retry returns status to active and the
-- webhook upserts fresh period bounds, so the grace clause stops applying.

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
  (
    (
      status IN ('active','trialing')
      AND (current_period_end IS NULL OR current_period_end > now())
    )
    OR (
      status = 'past_due'
      AND current_period_end IS NOT NULL
      AND current_period_end > now()
      AND (
        provider <> 'stripe'
        OR current_period_start IS NULL
        OR current_period_start + interval '30 days' > now()
      )
    )
  ) AS is_premium
FROM public.subscriptions
ORDER BY user_id,
         (status IN ('active','trialing')) DESC,
         (status = 'past_due') DESC,
         current_period_end DESC NULLS LAST,
         updated_at DESC;

GRANT SELECT ON public.user_premium_view TO authenticated;
