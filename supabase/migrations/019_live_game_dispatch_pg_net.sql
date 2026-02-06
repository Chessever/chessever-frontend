-- Migration: Immediate live game dispatch via pg_net
-- Purpose: Push live_game_update notifications immediately (no cron lag)
-- Created: 2026-02-05

-- Fetch secrets from Supabase Vault
CREATE OR REPLACE FUNCTION public.get_vault_secret(secret_name text)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = vault, public
AS $$
  SELECT decrypted_secret
    FROM vault.decrypted_secrets
   WHERE name = $1
   LIMIT 1;
$$;

-- Trigger hook: call edge function when a live_game_update is enqueued
CREATE OR REPLACE FUNCTION public.dispatch_live_game_update_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  url text;
  token text;
  headers jsonb;
BEGIN
  IF NEW.event_type <> 'live_game_update' OR NEW.status <> 'pending' THEN
    RETURN NEW;
  END IF;

  url := public.get_vault_secret('live_dispatch_url');
  IF url IS NULL OR url = '' THEN
    RETURN NEW;
  END IF;

  token := public.get_vault_secret('live_dispatch_token');
  headers := jsonb_build_object('Content-Type', 'application/json');
  IF token IS NOT NULL AND token <> '' THEN
    headers := headers || jsonb_build_object('x-stream-token', token);
  END IF;

  -- Fire-and-forget: pg_net handles async HTTP call
  PERFORM net.http_post(
    url,
    jsonb_build_object('limit', 10),
    headers
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS dispatch_live_game_update_outbox ON public.notification_outbox;

CREATE TRIGGER dispatch_live_game_update_outbox
  AFTER INSERT ON public.notification_outbox
  FOR EACH ROW
  EXECUTE FUNCTION public.dispatch_live_game_update_outbox();
