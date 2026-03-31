-- Migration: Buffer game_started notifications for round-level aggregation
-- Purpose: Delay game_started dispatch long enough to aggregate multiple
--          favorite-player games that go live close together in the same round.
-- Strategy: Keep round_started immediate for event-starred fallback, but make
--           each game_started row claimable only after a two-minute buffer.

CREATE OR REPLACE FUNCTION public.queue_game_notifications()
RETURNS TRIGGER AS $$
DECLARE
  is_live      BOOLEAN;
  was_live     BOOLEAN;
  is_finished  BOOLEAN;
  was_finished BOOLEAN;
  gb_id        TEXT;
  v_board_nr   SMALLINT;
BEGIN
  is_live      := NEW.status IN ('*', 'ongoing');
  was_live     := OLD.status IN ('*', 'ongoing');
  is_finished  := public.is_game_finished(NEW.status);
  was_finished := public.is_game_finished(OLD.status);

  SELECT t.group_broadcast_id INTO gb_id
    FROM public.tours t
   WHERE t.id = NEW.tour_id
   LIMIT 1;

  v_board_nr := NEW.board_nr;

  IF is_live AND NEW.last_move_time IS NOT NULL
     AND (NOT was_live OR OLD.last_move_time IS NULL) THEN

    IF NEW.round_id IS NOT NULL THEN
      INSERT INTO public.notification_outbox (
        event_type, round_id, tour_id, group_broadcast_id, payload, dedupe_key
      )
      VALUES (
        'round_started',
        NEW.round_id,
        NEW.tour_id,
        gb_id,
        jsonb_build_object(
          'round_name', (SELECT r.name FROM public.rounds r WHERE r.id = NEW.round_id LIMIT 1),
          'starts_at', now()
        ),
        'round_started:' || NEW.round_id
      )
      ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;

    INSERT INTO public.notification_outbox (
      event_type, game_id, tour_id, round_id, group_broadcast_id, payload, dedupe_key, not_before
    )
    VALUES (
      'game_started',
      NEW.id,
      NEW.tour_id,
      NEW.round_id,
      gb_id,
      jsonb_build_object(
        'status',          NEW.status,
        'last_move_time',  NEW.last_move_time,
        'player_white',    NEW.player_white,
        'player_black',    NEW.player_black,
        'board_nr',        v_board_nr
      ),
      'game_started:' || NEW.id,
      now() + interval '2 minutes'
    )
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;

  IF is_finished AND NOT was_finished THEN
    INSERT INTO public.notification_outbox (
      event_type, game_id, tour_id, round_id, group_broadcast_id, payload, dedupe_key
    )
    VALUES (
      'game_finished',
      NEW.id,
      NEW.tour_id,
      NEW.round_id,
      gb_id,
      jsonb_build_object(
        'status',          NEW.status,
        'last_move_time',  NEW.last_move_time,
        'player_white',    NEW.player_white,
        'player_black',    NEW.player_black,
        'board_nr',        v_board_nr
      ),
      'game_finished:' || NEW.id
    )
    ON CONFLICT (dedupe_key) DO NOTHING;

    IF NEW.round_id IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.games
         WHERE round_id = NEW.round_id
           AND id       != NEW.id
           AND NOT public.is_game_finished(status)
      ) THEN
        INSERT INTO public.notification_outbox (
          event_type, round_id, tour_id, group_broadcast_id, payload, dedupe_key
        )
        VALUES (
          'round_finished',
          NEW.round_id,
          NEW.tour_id,
          gb_id,
          jsonb_build_object(
            'results', (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'white',    g2.player_white,
                  'black',    g2.player_black,
                  'status',   g2.status,
                  'board_nr', g2.board_nr
                ) ORDER BY COALESCE(g2.board_nr, 32767), g2.player_white NULLS LAST
              )
              FROM public.games g2
              WHERE g2.round_id = NEW.round_id
            )
          ),
          'round_finished:' || NEW.round_id
        )
        ON CONFLICT (dedupe_key) DO NOTHING;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
