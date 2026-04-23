# Software Specification: ChessEver Affiliate System Dashboards

## 1. Project Overview
The ChessEver Affiliate System consists of two distinct web portals built with Next.js, both powered by a single Supabase backend. These dashboards allow for transparent performance tracking and professional management of the ChessEver partner program.

### A. Partner Dashboard (`partner.chessever.com`)
A portal for hand-picked affiliates to monitor their link performance, track their referred users (anonymized), and view their accumulated commissions.

### B. Super Admin Dashboard (`aff.chessever.com`)
A private internal portal for the ChessEver team to manage partners, set commission rates, monitor global financial health, and handle payout approvals.

---

## 2. Tech Stack (Unified)
*   **Framework**: Next.js 14+ (App Router)
*   **Language**: TypeScript
*   **Authentication**: Supabase Auth (Magic Link, Social, or Password)
*   **Database & API**: Supabase (PostgreSQL, Edge Functions)
*   **Styling**: Tailwind CSS + Shadcn UI + Lucide Icons
*   **Charts**: Recharts or Tremor (for high-fidelity financial visualization)

---

## 3. Data Model (Source of Truth: Supabase)
Both dashboards query the following tables in the `public` schema:
*   `public.affiliates`: Partner metadata, commission rates, and status.
*   `public.affiliate_referrals`: Attribution records (Links users to partners).
*   `public.affiliate_conversions`: Financial ledger (Revenue, commission, status, sandbox flag).

---

## 4. Partner Dashboard Requirements (`partner.chessever.com`)

### A. Access & Security
*   **Login**: Restricted to users whose email exists in the `public.affiliates` table.
*   **Data Privacy**: RLS policies ensure partners can only see their own rows. Referred users are identified only by anonymized IDs.

### B. Features
1.  **Overview Performance (Cards)**:
    *   **Total Referrals**: Count of installs/signups attributed to them.
    *   **Total Revenue**: Standardized USD revenue generated from their audience.
    *   **Current Balance**: Sum of `commission_usd` where `status = 'cleared'`.
    *   **Pending Earnings**: Sum of `commission_usd` where `status = 'pending'`.
2.  **Growth Analytics**:
    *   Daily/Weekly/Monthly charts for Installs and Conversions.
3.  **Affiliate Tools**:
    *   Display unique OneLinks: Branded (`get.chessever.com`) and Standard (`chessever.onelink.me`).
    *   One-click "Copy to Clipboard".
4.  **Payout History**:
    *   A searchable table of all transactions, their status, and dates.

---

## 5. Super Admin Dashboard Requirements (`aff.chessever.com`)

### A. Access & Security
*   **Login**: Restricted to ChessEver team members (verified via `auth.users` metadata or a specific `is_admin` flag).
*   **Full Visibility**: Bypasses the partner-specific RLS to show global data.

### B. Financial Statistics & Global Overview
1.  **Macro Metrics**:
    *   **Total Ecosystem Revenue**: Total revenue across all affiliate campaigns.
    *   **Total Commission Owed**: Sum of all `cleared` but not yet `paid` commissions.
    *   **Profit After Payouts**: Ecosystem Revenue minus Total Commission.
    *   **Conversion Rate**: Global percentage of referrals that turn into paying subscribers.
2.  **Top Partners Leaderboard**: List of partners ranked by revenue or referral count.
3.  **Global Conversion Feed**: A live list of every purchase event happening in the system across all partners.

### C. Partner Management
1.  **Onboarding UI**: Form to create a new partner (Generate code, set name, email, and commission percentage).
2.  **Management Table**: 
    *   Search/Filter partners.
    *   Toggle `is_active` (Kill a link instantly if a partner violates terms).
    *   Override `commission_rate` (e.g., Increase from 30% to 50% for a specific VIP partner).
3.  **Payout Detail View**: Update banking/PayPal details on behalf of a partner.

### D. Financial Ledger & Payout Approval
1.  **Approval Workflow**: 
    *   A view filtering all `pending` conversions that are older than the refund window (e.g., 14 days).
    *   Action: Bulk update `status` from `pending` to `cleared`.
2.  **Payout Execution**:
    *   Filter by `status = 'cleared'`.
    *   Action: "Mark as Paid" after manual payment is sent. This updates status to `paid` and moves the balance out of the partner's "Available" view.

---

## 6. Functional Isolation (Sandbox vs. Production)
Both dashboards must include a clearly visible **"Test Mode" (Sandbox)** toggle.
*   **Default**: Shows real production money/referrals (`is_sandbox = false`).
*   **Toggle On**: Shows test transactions from developers and sandbox links (`is_sandbox = true`).
*   This ensures the team can safely code the dashboard logic using fake data without affecting real financial reporting.

---

## 7. API Requirements
1.  **`get_financial_report` (Edge Function)**: For Super Admin to pull aggregated time-series data for global charts.
2.  **`get_partner_report` (Edge Function)**: Securely fetch a single partner's performance stats with server-side validation.
3.  **RevenueCat Webhook (Existing)**: Already handles the ingestion of verified financial data.
