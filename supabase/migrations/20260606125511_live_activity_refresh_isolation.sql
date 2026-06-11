-- Isolate Live Activity refresh from the regular push notification outbox.
--
-- Live Activity clock refreshes are now handled by the
-- live-activity-refresh Edge Function, called directly by the data hub.
-- This migration disables only the live_game_update outbox family. Normal
-- notification events such as game_started, game_finished, round_started, and
-- round_finished keep their existing outbox flow.

DROP TRIGGER IF EXISTS queue_live_game_update_on_move ON public.games;
DROP TRIGGER IF EXISTS queue_live_game_update_on_change ON public.games;
DROP TRIGGER IF EXISTS queue_live_game_update_on_eval_change ON public.evals;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM pg_trigger
     WHERE tgname = 'dispatch_live_game_update_outbox'
       AND tgrelid = 'public.notification_outbox'::regclass
       AND NOT tgisinternal
  ) THEN
    ALTER TABLE public.notification_outbox DISABLE TRIGGER dispatch_live_game_update_outbox;
  END IF;
END $$;

-- Leave harmless no-op definitions behind so accidental function calls or
-- future trigger recreation cannot enqueue Live Activity transport rows into
-- notification_outbox.
CREATE OR REPLACE FUNCTION public.queue_live_game_update_on_move()
RETURNS trigger AS $$
BEGIN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.queue_live_game_update_on_change()
RETURNS trigger AS $$
BEGIN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.queue_live_game_update_on_eval_change()
RETURNS trigger AS $$
BEGIN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.queue_live_game_updates()
RETURNS void AS $$
BEGIN
  RETURN;
END;
$$ LANGUAGE plpgsql;

UPDATE public.notification_outbox
   SET status = 'skipped',
       last_error = 'live_activity_refresh_isolated',
       updated_at = now()
 WHERE event_type = 'live_game_update'
   AND status IN ('pending', 'processing');

DELETE FROM public.notification_outbox
 WHERE event_type = 'live_game_update'
   AND dedupe_key LIKE 'clock_ping%';
