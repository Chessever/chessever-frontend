-- Incident guard for Szansa 2026 Blitz Round 13. The source recreated all
-- chapter IDs, while the PGN importer initially omitted board_nr. Existing
-- game_overrides can redirect replacement IDs to a protected board only
-- after that number is populated. Do this before game_override_trigger.
-- Depends on the existing broadcasting_private admin-override subsystem.
CREATE OR REPLACE FUNCTION broadcasting_private.normalize_szansa_round13_board()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  board_text text;
BEGIN
  board_text := substring(NEW.pgn FROM '(?m)^\[Round "13\.(1[0-5]|[1-9])"\]');
  IF board_text IS NOT NULL THEN
    NEW.board_nr := board_text::smallint;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION broadcasting_private.normalize_szansa_round13_board() FROM PUBLIC;

CREATE OR REPLACE TRIGGER a_szansa_round13_board_number
BEFORE INSERT ON public.games
FOR EACH ROW
WHEN (NEW.tour_id = 'I61J1bbh' AND NEW.round_id = '5G3B46In' AND NEW.board_nr IS NULL)
EXECUTE FUNCTION broadcasting_private.normalize_szansa_round13_board();
