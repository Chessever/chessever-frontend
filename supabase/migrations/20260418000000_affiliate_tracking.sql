-- Create affiliate referrals table
CREATE TABLE public.affiliate_referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referred_user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  affiliate_code TEXT NOT NULL,
  campaign_name TEXT,
  network TEXT,
  appsflyer_data JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.affiliate_referrals ENABLE ROW LEVEL SECURITY;

-- Users can insert their own referral (once)
CREATE POLICY "Users can insert their own referral" 
ON public.affiliate_referrals FOR INSERT 
TO authenticated 
WITH CHECK (auth.uid() = referred_user_id);

-- Users can see their own referral
CREATE POLICY "Users can read their own referral" 
ON public.affiliate_referrals FOR SELECT 
TO authenticated 
USING (auth.uid() = referred_user_id);

-- Create affiliate conversions table (for RevenueCat Webhooks)
CREATE TABLE public.affiliate_conversions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referred_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  affiliate_code TEXT NOT NULL,
  event_type TEXT NOT NULL, -- e.g., 'INITIAL_PURCHASE', 'RENEWAL'
  revenue_usd NUMERIC NOT NULL,
  currency TEXT,
  rc_event_id TEXT UNIQUE, -- RevenueCat event ID to prevent duplicates
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.affiliate_conversions ENABLE ROW LEVEL SECURITY;

-- Users can see their own conversions
CREATE POLICY "Users can read their own conversions" 
ON public.affiliate_conversions FOR SELECT 
TO authenticated 
USING (auth.uid() = referred_user_id);

-- Only service_role (webhooks) can insert/update conversions.
