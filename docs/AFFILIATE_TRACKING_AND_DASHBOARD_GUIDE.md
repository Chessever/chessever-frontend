# Affiliate Tracking & Dashboard Implementation Guide

This document outlines the architecture, database schema, and operational know-how for the custom affiliate marketing system built for ChessEver. It serves as the blueprint for building the backend webhooks and the dual dashboard setup.

## 1. System Architecture Overview

Because ChessEver is open-source, the client app cannot be trusted with financial data or payout calculations. Therefore, the system is split into two phases: **Client-Side Attribution** (who referred the user) and **Server-Side Conversion** (did they actually pay?).

### The Flow:
1. **The Click**: A user clicks an affiliate's AppsFlyer OneLink (e.g., `chessever.onelink.me/abc?af_sub1=gothamchess`).
2. **The Install (Flutter)**: The user installs the app. The `AppsflyerSdk` fires the `onInstallConversionData` callback. The app caches install metadata locally and only treats the payload as affiliate-eligible when `af_status = Non-organic` and an affiliate code is present (`af_sub1` / `deep_link_sub1`).
3. **The Signup (Flutter)**: Once the user logs in or signs up, the app triggers `setCustomerUserId` in AppsFlyer and writes the cached non-organic attribution data to the Supabase `affiliate_referrals` table, including `install_at`.
4. **The Link to RevenueCat (Flutter)**: The app retrieves the `AppsFlyer UID` and sends it to RevenueCat via `Purchases.setAppsflyerID()`.
5. **The Purchase (RevenueCat -> Webhook)**: When the user buys a subscription, RevenueCat fires a webhook to our Supabase Edge Function (`revenuecat-webhook`).
6. **The Commission (Supabase)**: The Edge Function calculates the commission based on the partner's rate in the `affiliates` table and inserts a record into `affiliate_conversions`.

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

### C. `affiliate_conversions` (Financial Ledger)
Records actual money spent and commissions owed.
*   `revenue_usd`: NUMERIC - Standardized USD revenue.
*   `commission_usd`: NUMERIC - The affiliate's cut calculated at purchase time.
*   `status`: TEXT - `pending`, `cleared`, `refunded`, `paid`.
*   `is_sandbox`: BOOLEAN - Tracks if it's a test purchase.

---

## 3. Webhook Logic (Implemented)

The `revenuecat-webhook` Edge Function handles the following:
1. **Verification**: 표준화된 USD 가격 (`price` field)을 사용하여 수수료를 계산합니다.
2. **Idempotency**: Prevents duplicate payouts using `rc_event_id` unique constraint.
3. **Refunds**: Automatically marks conversions as `refunded` when a cancellation occurs.
4. **Sandbox Support**: Identifies test events from RevenueCat and marks them with `is_sandbox: true`.
5. **Attribution Window**: Only records new affiliate trials/purchases when the RevenueCat `purchased_at_ms` is within 14 days of the AppsFlyer install time. Later renewals are only credited if an earlier paid affiliate conversion already exists.

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
3. Financial records are only created when RevenueCat confirms a cryptographically verified Apple/Google transaction.
4. Affiliate financial records are only created for non-organic AppsFlyer attribution and only inside the 14-day install-to-conversion window; renewals require an existing paid affiliate conversion.

---

## 6. Understanding the AppsFlyer SKAN Postback Warning

The `NSAdvertisingAttributionReportEndpoint` is correctly configured in `Info.plist`. The warning in the AppsFlyer dashboard will persist until the first live App Store installation from a real ad occurs and Apple's 48-hour privacy timer expires.

---

## 7. Sandbox Testing Workflow

During the development of the Next.js dashboards:
1. Use a test affiliate code (e.g., `test_partner`).
2. Tapping a Sandbox OneLink will trigger a Sandbox attribution in Supabase.
3. Making a Sandbox purchase in the Flutter app will trigger a Sandbox conversion in Supabase.
4. Use the **"Test Mode"** toggle on the dashboards to filter by `is_sandbox = true` to verify all charts and tables are working correctly before going live.
