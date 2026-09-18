-- Run inside a transaction after the Blitz repair, then ROLLBACK.
-- Uses the real public.games insert/upsert path; all replay writes roll back.
DO $$
DECLARE
  g public.games%ROWTYPE;
  writable_columns text;
  payload jsonb;
  updated_think integer;
  affected integer;
BEGIN
  SELECT string_agg(quote_ident(attname), ', ' ORDER BY attnum)
    INTO writable_columns
  FROM pg_attribute WHERE attrelid = 'public.games'::regclass
    AND attnum > 0 AND NOT attisdropped AND attgenerated = '' AND attidentity = '';

  FOR g IN SELECT * FROM public.games WHERE round_id = '5G3B46In' ORDER BY board_nr LOOP
    payload := to_jsonb(g) || jsonb_build_object(
      'id', 'szansa-replay-' || g.board_nr,
      'lichess_id', 'szansa-replay-' || g.board_nr,
      'board_nr', NULL,
      'last_move_time', NULL,
      'think_time', coalesce(g.think_time, 0) + 1);
    EXECUTE format(
      'INSERT INTO public.games (%1$s) SELECT %1$s FROM jsonb_populate_record(NULL::public.games, $1)
       ON CONFLICT (id) DO UPDATE SET board_nr = excluded.board_nr, think_time = excluded.think_time',
      writable_columns) USING payload;
    SELECT think_time INTO updated_think FROM public.games WHERE id = g.id;
    IF updated_think IS DISTINCT FROM coalesce(g.think_time, 0) + 1 THEN
      RAISE EXCEPTION 'Replacement source ID with missing board_nr did not update canonical board %', g.board_nr;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.games WHERE round_id = '5G3B46In') <> 15 THEN
    RAISE EXCEPTION 'Replacement source IDs created duplicates';
  END IF;

  INSERT INTO public.games (id, round_id, tour_id, lichess_id, player_white, player_black)
  SELECT game_id, round_id, tour_id, lichess_id, 'source white', 'source black'
  FROM broadcasting_private.game_deletions
  WHERE tour_id IN ('rQNo5wo2', 'I61J1bbh');
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 0 THEN RAISE EXCEPTION 'Deleted source IDs were resurrected'; END IF;
END $$;

-- The normalizer has no effect outside the specified tour and round, on a
-- supplied board number, or on an invalid/out-of-range/missing PGN Round tag.
CREATE TEMP TABLE szansa_guard_fixture (
  label text, pgn text, board_nr smallint, tour_id text, round_id text, expected smallint
) ON COMMIT DROP;
CREATE TRIGGER a_szansa_round13_board_number BEFORE INSERT ON szansa_guard_fixture
FOR EACH ROW
WHEN (NEW.tour_id = 'I61J1bbh' AND NEW.round_id = '5G3B46In' AND NEW.board_nr IS NULL)
EXECUTE FUNCTION broadcasting_private.normalize_szansa_round13_board();
INSERT INTO szansa_guard_fixture VALUES
  ('valid', E'[Event "Chess"]\n[Round "13.14"]\n', NULL, 'I61J1bbh', '5G3B46In', 14),
  ('different round', '[Round "13.14"]', NULL, 'I61J1bbh', 'other-round', NULL),
  ('different tour', '[Round "13.14"]', NULL, 'other-tour', '5G3B46In', NULL),
  ('supplied board', '[Round "13.14"]', 8, 'I61J1bbh', '5G3B46In', 8),
  ('out of range', '[Round "13.16"]', NULL, 'I61J1bbh', '5G3B46In', NULL),
  ('wrong PGN round', '[Round "12.14"]', NULL, 'I61J1bbh', '5G3B46In', NULL),
  ('no PGN', NULL, NULL, 'I61J1bbh', '5G3B46In', NULL);
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM szansa_guard_fixture WHERE board_nr IS DISTINCT FROM expected) THEN
    RAISE EXCEPTION 'Normalizer changed an unintended input';
  END IF;
END $$;
