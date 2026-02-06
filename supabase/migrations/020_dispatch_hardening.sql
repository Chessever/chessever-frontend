-- Migration: Harden immediate dispatch trigger
-- Purpose:
-- - Ensure dispatch failures never break game updates (best-effort)
-- - Restrict secret access function execution to service_role
-- Created: 2026-02-05

-- Lock down vault secret helper.
REVOKE EXECUTE ON FUNCTION public.get_vault_secret(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_vault_secret(text) TO service_role;

-- Lock down dispatch trigger function (not needed for clients).
REVOKE EXECUTE ON FUNCTION public.dispatch_live_game_update_outbox() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispatch_live_game_update_outbox() TO service_role;

-- Ensure trigger dispatch is best-effort and cannot abort the parent transaction.
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

  BEGIN
    -- Fire-and-forget: pg_net handles async HTTP call
    PERFORM net.http_post(
      url,
      jsonb_build_object('limit', 10),
      headers
    );
  EXCEPTION WHEN OTHERS THEN
    -- Never fail the enclosing transaction (game update), even if dispatch is down.
    NULL;
  END;

  RETURN NEW;
END;
$$;
