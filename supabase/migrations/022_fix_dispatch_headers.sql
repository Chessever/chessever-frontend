-- Migration: Fix dispatch trigger headers (critical auth fix)
-- Problem: Both dispatch triggers pass headers as the 3rd positional arg to
--          net.http_post, but the 3rd arg is `params` (query parameters).
--          This causes x-stream-token to appear in the URL query string
--          instead of as an HTTP header, resulting in 401 on every call.
-- Fix: Use named parameters for net.http_post in both trigger functions.
-- Created: 2026-02-06

-- Fix 1: Live game update dispatch — use named params so headers go to headers
CREATE OR REPLACE FUNCTION public.dispatch_live_game_update_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  dispatch_url text;
  token text;
  hdrs jsonb;
BEGIN
  IF NEW.event_type <> 'live_game_update' OR NEW.status <> 'pending' THEN
    RETURN NEW;
  END IF;

  dispatch_url := public.get_vault_secret('live_dispatch_url');
  IF dispatch_url IS NULL OR dispatch_url = '' THEN
    RETURN NEW;
  END IF;

  token := public.get_vault_secret('live_dispatch_token');
  hdrs := jsonb_build_object('Content-Type', 'application/json');
  IF token IS NOT NULL AND token <> '' THEN
    hdrs := hdrs || jsonb_build_object('x-stream-token', token);
  END IF;

  BEGIN
    PERFORM net.http_post(
      url     := dispatch_url,
      body    := jsonb_build_object('limit', 10),
      headers := hdrs
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN NEW;
END;
$$;

-- Fix 2: General notification dispatch — add x-stream-token, skip live_game_update
--         (live events are handled by the dedicated trigger above)
CREATE OR REPLACE FUNCTION public.dispatch_notification_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  dispatch_url text;
  token text;
  hdrs jsonb;
BEGIN
  IF NEW.status IS DISTINCT FROM 'pending' THEN
    RETURN NEW;
  END IF;

  -- Skip live_game_update; handled by dispatch_live_game_update_outbox
  IF NEW.event_type = 'live_game_update' THEN
    RETURN NEW;
  END IF;

  dispatch_url := public.get_vault_secret('live_dispatch_url');
  IF dispatch_url IS NULL OR dispatch_url = '' THEN
    dispatch_url := 'https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/onesignal-dispatch';
  END IF;

  token := public.get_vault_secret('live_dispatch_token');
  hdrs := jsonb_build_object('Content-Type', 'application/json');
  IF token IS NOT NULL AND token <> '' THEN
    hdrs := hdrs || jsonb_build_object('x-stream-token', token);
  END IF;

  BEGIN
    PERFORM net.http_post(
      url     := dispatch_url,
      body    := jsonb_build_object('limit', 50),
      headers := hdrs
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN NEW;
END;
$$;
