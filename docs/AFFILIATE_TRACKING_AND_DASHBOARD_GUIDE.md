# Affiliate Tracking & Dashboard Implementation Guide

This document outlines the architecture, database schema, and operational know-how for the custom affiliate marketing system built for ChessEver. It serves as the blueprint for building the backend webhooks and the dual dashboard setup.

## 1. System Architecture Overview

Because ChessEver is open-source, the client app cannot be trusted with financial data or payout calculations. Therefore, the system is split into two phases: **Client-Side Attribution** (who referred the user) and **Server-Side Conversion** (did they actually pay?).

### Mobile App Flow:
1. **The Click**: A user clicks an affiliate's AppsFlyer OneLink (e.g., `chessever.onelink.me/abc?af_sub1=gothamchess`).
2. **The Install (Flutter)**: The user installs the app. The `AppsflyerSdk` fires the `onInstallConversionData` callback. The app caches install metadata locally and only treats the payload as affiliate-eligible when `af_status = Non-organic` and an affiliate code is present (`af_sub1` / `deep_link_sub1`).
3. **The Signup (Flutter)**: Once the user logs in or signs up, the app triggers `setCustomerUserId` in AppsFlyer and writes the cached non-organic attribution data to the Supabase `affiliate_referrals` table, including `install_at`.
4. **The Link to RevenueCat (Flutter)**: The app retrieves the `AppsFlyer UID` and sends it to RevenueCat via `Purchases.setAppsflyerID()`.
5. **The Purchase (RevenueCat -> Webhook)**: When the user buys a subscription, RevenueCat fires a webhook to our Supabase Edge Function (`revenuecat-webhook`).
6. **The Commission (Supabase)**: The Edge Function calculates the commission based on the partner's rate in the `affiliates` table and inserts a record into `affiliate_conversions`.

### Web Stripe Flow:
1. **The Click**: Partner links now include `deep_link_sub1=<code>` for mobile deferred deep linking and `af_web_dp=https://chessever.com/pricing?af_sub1=<code>` for desktop/web redirection.
2. **The Website Visit**: The Next.js website captures `af_sub1` / `deep_link_sub1` and related AppsFlyer parameters into local storage for 14 days. AppsFlyer Web SDK/PBA also loads when `NEXT_PUBLIC_APPSFLYER_WEB_DEV_KEY` is configured.
3. **The Signup/Login**: If checkout requires Google OAuth, the affiliate code is preserved through the redirect and sent to the Stripe checkout Edge Function after login.
4. **The Checkout (Stripe)**: `stripe-checkout` validates the affiliate code against an active `affiliates` row, creates a `platform = web` referral if the user does not already have one, and stamps the Stripe Session/Subscription metadata.
5. **The Purchase (Stripe -> Webhook)**: `stripe-webhook` listens for paid invoices, writes the Stripe subscription mirror, and inserts a server-side `affiliate_conversions` row immediately. There is no web trial state.
6. **Refunds**: Stripe charge refunds mark matching web affiliate conversions as `refunded`.

---

## 2. Database Schema (Supabase)

We created three tables to securely manage this lifecycle.

### A. `affiliates` (Master Partner Table)
Stores your hand-picked partners and their custom rates.
*   `id`: UUID
*   `code`: TEXT (UNIQUE) - The tracking code (e.g., `gothamchess`).
*   `commission_rate`: NUMERIC - e.g., `0.30` for 30%.
*   `is_active`: BOOLEAN - Toggle to disable a partner.

### B. `affiliate_referrals` (Attribution Table)
Links a ChessEver user to the affiliate who brought them in.
*   `referred_user_id`: UUID (UNIQUE) -> `auth.users(id)`.
*   `affiliate_code`: TEXT - Matches `affiliates.code`.
*   `is_sandbox`: BOOLEAN - Tracks if it's a test install.
*   `platform`: TEXT - `ios`, `android`, `web`, or `unknown`.

### C. `affiliate_conversions` (Financial Ledger)
Records actual money spent and commissions owed.
*   `revenue_usd`: NUMERIC - Standardized USD revenue.
*   `commission_usd`: NUMERIC - The affiliate's cut calculated at purchase time.
*   `status`: TEXT - `pending`, `cleared`, `refunded`, `paid`.
*   `is_sandbox`: BOOLEAN - Tracks if it's a test purchase.
*   `platform`: TEXT - `ios`, `android`, `web`, or `unknown`.
*   `stripe_invoice_id`: TEXT - Idempotency key for Stripe web invoice payouts.

---

## 3. Webhook Logic (Implemented)

The `revenuecat-webhook` Edge Function handles mobile App Store / Play Store purchases:
1. **Verification**: Uses standardized USD RevenueCat event pricing for commission calculation.
2. **Idempotency**: Prevents duplicate payouts using `rc_event_id` unique constraint.
3. **Refunds**: Automatically marks conversions as `refunded` when a cancellation occurs.
4. **Sandbox Support**: Identifies test events from RevenueCat and marks them with `is_sandbox: true`.
5. **Attribution Window**: Only records affiliate trials/purchases when the user's first app install is attributed to the partner link and the RevenueCat `purchased_at_ms` is within 14 days of that AppsFlyer install time. Renewals, upgrades, duplicate installs, and purchases outside that window are not newly commissionable.

The `stripe-webhook` Edge Function handles web purchases:
1. **Verification**: Stripe webhook signature verification is mandatory.
2. **Idempotency**: Prevents duplicate payouts with `stripe_invoice_id`.
3. **No Trial**: Successful web subscription invoices become `pending` affiliate revenue immediately.
4. **Sandbox Mode**: Stripe test-mode events are stored with `is_sandbox = true`; live-mode events are stored with `is_sandbox = false`.
5. **Refunds**: Charge refunds mark matching web conversions as `refunded`.
6. **Attribution Window**: First paid web invoices must be within 14 days of the captured affiliate click. Later renewal invoices are commissionable only after a prior paid conversion exists for that affiliate/user.

---

## 4. The Dual Dashboard Setup

The system is designed to support two separate frontends:

### A. Partner Dashboard (`partner.chessever.com`)
*   **Audience**: The affiliates themselves.
*   **Purpose**: Transparency. Affiliates login to see how many people they've referred and how much money they've made.
*   **Security**: RLS restricted. Partners can ONLY query data where `affiliate_code` matches their own.

### B. Super Admin Dashboard (`aff.chessever.com`)
*   **Audience**: ChessEver Internal Team.
*   **Purpose**: Management & Financial Oversight.
*   **Features**:
    *   Onboard new partners and set their commission percentages.
    *   Monitor **Global Financial Stats** (Total Revenue, Total Owed, Profit).
    *   Approve Payouts (Bulk-moving `pending` to `cleared`).
    *   Manage partner statuses (Activate/Deactivate).

---

## 5. Security & Open Source Considerations

The architecture is bulletproof against client-side spoofing:
1. You **never** pay based on the `affiliate_referrals` table (which is client-side).
2. You **only** pay based on the `affiliate_conversions` table (which is server-side).
3. Financial records are only created when RevenueCat confirms a cryptographically verified Apple/Google transaction or Stripe confirms a signed paid invoice.
4. Affiliate financial records are only created for first-install/mobile attribution or web click attribution inside the 14-day attribution-to-conversion window; renewals require an existing paid affiliate conversion.

---

## 6. Understanding the AppsFlyer SKAN Postback Warning

The `NSAdvertisingAttributionReportEndpoint` is correctly configured in `Info.plist`. The warning in the AppsFlyer dashboard will persist until the first live App Store installation from a real ad occurs and Apple's 48-hour privacy timer expires.

---

## 7. AppsFlyer Web Setup Notes

The AppsFlyer web app has been created as `ChessEver Web Platform` for `chessever.com`. The public PBA Web SDK key is wired in the website; it is a browser SDK identifier, not a server secret.

AppsFlyer currently shows the brand bundle/product-line web setup path as unavailable in this account: the brand-bundle pages return 404 and PBA apps cannot be added to the existing `ChessEver` product line. Stripe and Supabase remain the authoritative payout ledger, so affiliate commissions do not depend on AppsFlyer dashboard reporting after the affiliate code reaches checkout metadata.

---

## 8. Sandbox Testing Workflow

For mobile dashboard testing:
1. Use a test affiliate code (e.g., `test_partner`).
2. Tapping a Sandbox OneLink will trigger a Sandbox attribution in Supabase.
3. Making a Sandbox purchase in the Flutter app will trigger a Sandbox conversion in Supabase.
4. Use the **"Test Mode"** toggle on the dashboards to filter by `is_sandbox = true` to verify all charts and tables are working correctly before going live.

For web Stripe testing:
1. Temporarily configure the deployed Stripe Edge Function secrets with Stripe test-mode keys and the matching test webhook signing secret.
2. Use a fresh Supabase user that has no existing `affiliate_referrals` row. Attribution is first-touch per user, so an already-attributed user will not create a second sandbox referral.
3. Visit `https://chessever.com/pricing?af_sub1=<affiliate_code>` or the partner OneLink that redirects to that URL.
4. Complete Stripe Checkout with a Stripe test card.
5. Run `scripts/verify_web_stripe_affiliate_e2e.sh <affiliate_code> --sandbox` from the desktop/backend repo.
6. Open the partner/admin dashboards with **Test Mode** enabled and confirm the row appears as `platform = web`.
7. Refund the Stripe test charge, then run `scripts/verify_web_stripe_affiliate_e2e.sh <affiliate_code> --sandbox --require-refund`.

Use environment variables or a secret manager when switching Stripe modes; never paste actual secrets into docs, commits, or shell history. The reversible shape is:

```bash
supabase secrets set \
  STRIPE_SECRET_KEY="$STRIPE_TEST_SECRET_KEY" \
  STRIPE_WEBHOOK_SECRET="$STRIPE_TEST_WEBHOOK_SECRET"

# Run the sandbox checkout and verifier, then restore live secrets:
supabase secrets set \
  STRIPE_SECRET_KEY="$STRIPE_LIVE_SECRET_KEY" \
  STRIPE_WEBHOOK_SECRET="$STRIPE_LIVE_WEBHOOK_SECRET"

scripts/check_web_stripe_affiliate_deploy.sh
```

---

## 9. Production Rollout Checklist

Before treating web Stripe affiliate attribution as live:
1. Rotate any previously exposed Stripe or Supabase service-role secrets before deploying.
2. Apply the web Stripe affiliate migration to the production Supabase project.
3. Deploy `stripe-checkout` and `stripe-webhook` with `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`, and `REVENUECAT_STRIPE_PUBLIC_API_KEY` configured.
4. Deploy the Next.js website with the public AppsFlyer PBA Web SDK key configured as `NEXT_PUBLIC_APPSFLYER_WEB_DEV_KEY`.
5. Click a partner referral link on desktop, complete a real Stripe checkout, and confirm Supabase has a `platform = web` `affiliate_referrals` row plus a matching `affiliate_conversions` row with `stripe_invoice_id`.
6. Refund that Stripe charge and confirm the matching web conversion moves to `refunded`.
7. Treat AppsFlyer brand-bundle/product-line dashboard reporting as separate from payout correctness until AppsFlyer resolves the account-side brand-bundle 404 / PBA product-line limitation.

From the desktop/backend repo, run the read-only final verifier after the real checkout:

```bash
scripts/verify_web_stripe_affiliate_e2e.sh <affiliate_code>
scripts/verify_web_stripe_affiliate_e2e.sh <affiliate_code> --invoice <stripe_invoice_id>
scripts/verify_web_stripe_affiliate_e2e.sh <affiliate_code> --sandbox
scripts/verify_web_stripe_affiliate_e2e.sh <affiliate_code> --require-refund
```
