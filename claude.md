Shahirizade Fresh Market(This app) will be used as showcase project created for client and will be our first prototype for future project Tabsy, all operation business logic will be same with tabsy so you can follow the logic from behind while making sure Stripe Connect and Uber Direct will work the same. We wanna first see how our business model showcasing in this project.

TABSY — MULTI-MERCHANT COMMERCE & LOGISTICS PLATFORM

Business Model, Financial Architecture, and Operational Integration Spec

1) What Tabsy Is

Tabsy is a multi-merchant digital commerce infrastructure for restaurants, cafés, fresh markets, coffee shops, and similar food-service brands. We build and operate each merchant’s white-label ordering website and/or mobile app, while Tabsy centrally handles payments, fee splits, delivery orchestration, customer service, and loyalty.
Tabsy is not a single restaurant. Tabsy is the platform operator.

2) Core Value Proposition

* Sell everywhere, instantly: Each merchant gets an owned digital storefront (web/app) managed by Tabsy.
* Get paid compliantly: Tabsy routes funds using Stripe Connect Express—no merchant engineering required.
* Deliver reliably: Tabsy dispatches last-mile deliveries via Uber Direct API (with optional future courier partners).
* Retain customers: Tabsy runs a built-in Loyalty Rewards program for every merchant’s storefront.
* Delight customers: Tabsy operates central Customer Services (chat + phone) and stores all cases in Supabase.
* Operate simply: One platform for onboarding, orders, payments, logistics, loyalty, reporting, and support.


3) Financial Model (Fees and Flows)

* Platform fee: Tabsy charges a 1% fee on every successfully processed order. we charge this fee to customers, not merchants @Berkay 
* Delivery fee: Each order includes a delivery fee component. Tabsy retains these funds to pay courier networks programmatically.
* Merchant share: After deducting the 1% platform fee and the delivery fee, the remaining order revenue belongs to the merchant and is transferred to the merchant’s Stripe connected account for payout.
* Single customer charge: The customer sees one payment for the full order; Tabsy orchestrates the split in the background.

Result: One seamless checkout → Tabsy keeps 1% + delivery fee → Merchant receives the remainder automatically.

4) Platform Roles and Responsibilities

* Tabsy (Platform Operator):
     Owns storefront tech, payment routing, fee application, delivery orchestration, loyalty system, customer services, fraud controls, ledgering, and data/analytics.
* Merchants (Restaurants/Markets/Cafés):
     Own the products, pricing, menus, order prep, and business operations; receive funds and handle tax obligations relevant to their jurisdiction.
* Couriers (Uber Direct at launch):
     Provide last-mile logistics; dispatched and funded by Tabsy from retained delivery fees.
* Customers:
     Place orders on merchant storefronts powered by Tabsy and interact with Tabsy support if issues arise.


5) Technology Stack (Authoritative Systems)

* Stripe Connect (Express): Merchant onboarding (KYC/KYB), compliant fund flows, automated payouts, capability state.
* Uber Direct API: Delivery creation, courier assignment, live tracking references, delivery status outcomes.
* Supabase: Single source of truth for merchants, menus, orders, payment/transfer references, delivery events, loyalty ledgers, referral events, and all customer service cases (chat + phone).
* Storefronts: White-label web/app for each merchant, powered by Tabsy modules (catalog, checkout, loyalty, support).


6) Merchant Onboarding (High-Level)

* Merchant registers through Tabsy and is guided through Stripe Express onboarding (Stripe-hosted flow).
* Stripe verifies identity, business info, and payout destinations.
* Once active (capabilities enabled), merchant is eligible to receive automated transfers and payouts.
* Tabsy stores the merchant’s account linkage and status in Supabase and exposes a “ready to sell” state in the merchant dashboard.

Principle: Tabsy never stores raw bank details; Stripe is the compliance and payout system of record.

7) Order Lifecycle (Conceptual)

1. Browse & Build Cart: Customer browses the merchant storefront, selects items, sets pickup/delivery, and checks out.
2. Payment: Customer pays one total amount.
3. Fee Handling: Tabsy’s financial logic applies the 1% platform fee and retains the delivery fee.
4. Merchant Settlement: Net revenue (after fees) is allocated to the merchant for payout.
5. Fulfillment:

    * Pickup: Merchant prepares order for customer pickup.
    * Delivery: Tabsy dispatches via Uber Direct; merchant preps/hand-off to courier.

1. Post-Order: Loyalty accrual posts, receipts and order confirmations are issued, and Tabsy remains the support contact.

All order, payment, transfer, delivery, and loyalty events are persisted in Supabase for auditability.

8) Delivery Orchestration (Uber Direct)

* Dispatch: On delivery orders, Tabsy creates a delivery job via Uber Direct using the order details, pickup window, and drop-off address.
* Status Tracking: Uber Direct returns statuses/labels (accepted, en route, delivered, failed, etc.). These are stored in Supabase and exposed to the customer and merchant.
* Funding: Delivery fees are retained by Tabsy and used to settle courier charges.
* Issue Handling: Failed/cancelled deliveries or surcharges are surfaced to Tabsy Customer Services for resolution and, if required, post-facto settlement adjustments.


9) Loyalty Rewards (Available to Every Merchant)

Scope: The loyalty program is part of Tabsy and is automatically available in every merchant’s app/website that Tabsy creates.
Earning model (standardized across the platform):

* $1 spent = 10 Stars
* Applies equally to pickup and delivery orders
* Stars accrue per-merchant (each merchant has a separate Stars ledger for the same customer)

Redemption:

* Stars can be redeemed for free items, discounts, and exclusive rewards.
* Redemption catalogs and thresholds are merchant-configurable; accrual rate is Tabsy-standard for simplicity and clarity.

Referrals:

* Customers can share an invite link.
* After the friend completes their first paid order (minimum order value applies), bonuses post to both parties (example: inviter +500 Stars, friend +300 Stars).
* All referral events and validations are recorded in Supabase.

Visibility & UX:

* “Earn Stars,” “Redeem Rewards,” “Invite Friends,” and “Track Balance” experiences live within each merchant storefront.
* Loyalty balances, redemptions, and adjustments are stored and auditable in Supabase.
* Customer support can correct balances or resolve disputes (also tracked in Supabase).


10) Customer Services (Tabsy-Operated)

Tabsy operates central support for all storefronts:

* Channels: In-app/web chat and phone support.
* Scope: Order issues, delivery problems, missing/wrong items, temperature/quality complaints, refund requests, loyalty balance inquiries, referral credit timing, etc.
* System of Record: Every support case is persisted in Supabase, linked to the customer, order, and merchant.
* Outcomes: Tabsy coordinates between merchant and courier to resolve; Tabsy may authorize adjustments, loyalty goodwill credits, partial refunds, or re-dispatches per policy.

Reasoning: Centralizing support reduces merchant burden, creates consistent quality, and protects brand trust.

11) Data Model — Conceptual Objects (authoritative storage in Supabase)

* Merchant: identity, legal info references, Stripe account linkage, payout readiness, storefront settings, loyalty catalog, hours.
* Menu & Catalog: categories, items, options, availability, pricing, taxation flags.
* Customer: identity, contact, preferences, saved addresses, loyalty ledgers (per merchant), referral graph.
* Order: line items, totals, taxes, tips, delivery method, timestamps, payment references, settlement breakdown, loyalty accrual.
* Payment/Settlement: platform fee value, delivery fee retained, merchant net amount, payout references.
* Delivery: Uber Direct job identifiers, status history, proof of delivery artifacts (when available).
* Support Case: channel (chat/phone), issue type, transcripts/notes, actions taken, financial adjustments, resolution outcome.
* Loyalty: balances, accrual events, redemptions, reversals, referral bonuses, audit trail.


12) Risk, Compliance, and Controls

* Payments and Payouts: Stripe is the regulated system; Stripe performs KYC/KYB, monitors capabilities, and manages payouts.
* Data Security: Sensitive payment credentials are never stored by Tabsy; Tabsy stores references and non-sensitive operational data in Supabase.
* Refunds and Chargebacks: Tabsy Customer Services triages; Tabsy coordinates with merchants and Stripe; outcomes are logged and reflected in settlement records and loyalty adjustments when relevant.
* Delivery Risk: Tabsy manages courier relationships; failed deliveries or surcharges are reconciled using retained delivery fees and clearly recorded.
* Auditability: All financial and operational events are persisted in Supabase with immutable event trails where feasible.


13) Operational SLAs (Policy-Level)

* Storefront uptime targets: aligned with Tabsy hosting stack SLAs.
* Payment availability: bound by Stripe availability; Tabsy monitors and fails over UX appropriately.
* Delivery dispatch latency: targets from order confirmation to courier acceptance; monitored by Tabsy.
* Support response times: separate SLAs for chat vs. phone; escalation paths clearly documented.
* Loyalty posting: accrual posts after successful payment capture; referral bonuses post after first eligible order clears any fraud/abuse checks.


14) Reporting and Analytics (Merchant + Tabsy)

* Merchant dashboards: sales, net revenue, top items, order channels (pickup vs delivery), refunds, loyalty engagement (Stars earned/redeemed), campaign results, payout schedules.
* Tabsy internal: merchant performance cohorts, delivery reliability metrics, support load by category, fraud signals, referral funnel conversion, LTV/CAC by merchant segment.


15) Edge Cases and Policies

* Partial refunds: proportional adjustments to merchant net and, if applicable, reversal or re-calculation of Stars earned.
* Void/cancel before preparation: full refund to customer, no Stars accrual, delivery fee voided if not dispatched.
* Delivery failure after dispatch: decision tree (re-dispatch, partial refund, goodwill Stars) based on Uber Direct status and evidence.
* Chargeback: freeze associated Stars until dispute resolves; adjust settlement records post-resolution.
* Abuse controls: referral self-dealing, high-risk devices, excessive redemptions; implement throttles and review workflows.
* Payout holds: in rare cases, payouts may be delayed by Stripe risk controls; Tabsy surfaces status to merchants and acts as liaison.


16) Launch and Expansion Plan

* Phase 1: Stripe Connect Express + Uber Direct + Loyalty + Customer Services + core reporting.
* Phase 2: Additional couriers (e.g., DoorDash Drive), scheduled delivery windows, multi-merchant carts (where lawful), instant payouts as an add-on.
* Phase 3: Deeper marketing automation (loyalty tiers, birthday rewards), inventory-aware menus, multi-location chain management, enterprise SLAs.


17) The Tabsy Promise (Operator’s Statement)

* Simple for merchants: Onboard, publish menu, start selling.
* Seamless for customers: One checkout, tracked delivery, clear support, tangible rewards.
* Compliant and reliable: Stripe for funds, Uber for last-mile, Supabase for operational truth.
* Aligned incentives: Tabsy earns 1% only when merchants earn; delivery fees are transparently retained solely to fund actual courier costs.

This document is the authoritative description of how Tabsy operates: fees, flows, responsibilities, systems, data, policies, and roadmap.


