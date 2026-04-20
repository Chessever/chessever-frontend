-- 1. Create a Master Affiliates Table for your partners
CREATE TABLE public.affiliates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL, -- e.g., 'gothamchess'
  name TEXT,
  email TEXT,
  commission_rate NUMERIC NOT NULL DEFAULT 0.30, -- default 30% cut
  payout_details JSONB DEFAULT '{}'::jsonb, -- e.g., PayPal email, bank details
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.affiliates ENABLE ROW LEVEL SECURITY;
-- Only service_role (your backend/dashboard) handles this table by default.
-- You can add policies later if you want affiliates to log in to the app themselves.

-- 2. Upgrade the affiliate_conversions table
ALTER TABLE public.affiliate_conversions
  ADD COLUMN commission_usd NUMERIC,
  ADD COLUMN product_id TEXT,
  ADD COLUMN status TEXT DEFAULT 'pending';

-- Add a constraint to ensure status is valid
ALTER TABLE public.affiliate_conversions
  ADD CONSTRAINT valid_conversion_status 
  CHECK (status IN ('pending', 'cleared', 'refunded', 'paid'));

