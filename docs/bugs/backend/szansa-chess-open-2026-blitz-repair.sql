-- Authorized production repair: oelbsuggrzyqwzmvidju.
-- Apply in the SAME transaction as migration
-- 20260913122910_normalize_szansa_blitz_round13_board_numbers.sql.
-- The live source regenerated all 15 chapter IDs twice, leaving 45 rows.
-- These are the 15 current source IDs captured before repair.
CREATE TEMP TABLE szansa_blitz_plan (
  game_id text PRIMARY KEY, board_nr smallint NOT NULL, name text NOT NULL,
  white_fed text NOT NULL, black_fed text NOT NULL
) ON COMMIT DROP;
INSERT INTO szansa_blitz_plan VALUES
  ('U9IXmhqc', 1, 'Galperin, Platon - Borischik, Sergey', 'SWE', 'POL'),
  ('EidmK2WC', 2, 'Sowinski, Pawel - Krzysztof Jakubowski', 'POL', ''),
  ('3wD5yE5b', 3, 'Kyc, Jerzy - Maltsevskaya, Aleksandra', 'POL', 'POL'),
  ('59rjb2kl', 4, 'Psyk, Radoslaw - Egor Bogdanov', 'POL', ''),
  ('QV5v9Yur', 5, 'Niezhentsev, Kyrylo - Kowalski, Igor', 'POL', 'POL'),
  ('nNyO1D0v', 6, 'Piorun, Kacper - Socko, Monika', 'POL', 'POL'),
  ('4YNTADRI', 7, 'Mis, Mieszko - Nurkiewicz, Maciej', 'POL', 'POL'),
  ('V9uZluOm', 8, 'Serafin, Franciszek - Lee, Hyo', 'POL', 'KOR'),
  ('ldPnWE4t', 9, 'Lewczuk, Jakub - Fiszer, Bartosz', 'POL', 'POL'),
  ('t2v8vT5C', 10, 'Kazmierowski, Tymon - Antoni Kozak', 'POL', ''),
  ('PmX892ff', 11, 'Kowalski, Witold - Javier Rodriguez Rodriguez', 'POL', ''),
  ('6mz68Bp6', 12, 'Etut, Filbert - Jagodzinski, Piotr', 'POL', 'POL'),
  ('4SwMlgEm', 13, 'Skurniak, Szymon - Rajlich, Vaclav', 'POL', 'POL'),
  ('ohFQjskI', 14, 'Terkiewicz, Bruno - Liskiewicz, Jakub', 'POL', 'POL'),
  ('RGqVp5BU', 15, 'Wikar, Martyna - Stachniak, Stanislaw', 'POL', 'POL');

DO $$
BEGIN
  PERFORM id FROM public.games WHERE round_id = '5G3B46In' FOR UPDATE;
  IF (SELECT count(*) FROM public.games WHERE round_id = '5G3B46In') <> 45
    OR (SELECT count(*) FROM public.games g JOIN szansa_blitz_plan p ON g.id = p.game_id
      WHERE g.round_id = '5G3B46In' AND g.tour_id = 'I61J1bbh'
        AND g.name = p.name AND g.board_nr = p.board_nr) <> 15 THEN
    RAISE EXCEPTION 'Blitz snapshot changed; re-audit';
  END IF;
  IF EXISTS (SELECT 1 FROM broadcasting_private.game_overrides WHERE round_id = '5G3B46In')
    OR EXISTS (SELECT 1 FROM broadcasting_private.game_deletions WHERE round_id = '5G3B46In') THEN
    RAISE EXCEPTION 'Existing admin correction; do not overwrite';
  END IF;
  IF EXISTS (SELECT 1 FROM public.games g WHERE g.round_id = '5G3B46In'
      AND NOT EXISTS (SELECT 1 FROM szansa_blitz_plan p
        WHERE p.name = g.name AND p.board_nr = g.board_nr)) THEN
    RAISE EXCEPTION 'Unexpected pairing; do not remove a unique game';
  END IF;
END $$;

-- ID-only tombstones do not block valid games with identical players.
INSERT INTO broadcasting_private.game_deletions
  (game_id, round_id, tour_id, lichess_id, board_nr, name, note)
SELECT g.id, g.round_id, g.tour_id, g.lichess_id, g.board_nr, g.name,
  'Szansa 2026 Blitz Round 13: obsolete source chapter, retain ' || p.game_id || '. ID-only tombstone.'
FROM public.games g JOIN szansa_blitz_plan p ON p.name = g.name AND p.board_nr = g.board_nr
WHERE g.round_id = '5G3B46In' AND g.id <> p.game_id;

INSERT INTO broadcasting_private.game_override_events (game_id, round_id, action)
SELECT game_id, round_id, 'deleted' FROM broadcasting_private.game_deletions WHERE round_id = '5G3B46In';

DELETE FROM public.games g USING broadcasting_private.game_deletions d
WHERE g.id = d.game_id AND g.round_id = '5G3B46In' AND g.tour_id = 'I61J1bbh';

-- Keep live moves, clocks, results, and metadata unpinned. The existing
-- override trigger redirects subsequent source IDs by this protected board.
INSERT INTO broadcasting_private.game_overrides
  (game_id, round_id, tour_id, overrides, source_pgn, note)
SELECT g.id, g.round_id, g.tour_id, jsonb_build_object('board_nr', p.board_nr), g.pgn,
  'Szansa 2026 Blitz Round 13: stable board identity across source chapter regeneration. Only board_nr is pinned; live game data remains writable.'
FROM public.games g JOIN szansa_blitz_plan p ON p.game_id = g.id;

INSERT INTO broadcasting_private.game_override_events (game_id, round_id, action, columns, overrides)
SELECT game_id, '5G3B46In', 'applied', ARRAY['board_nr'], jsonb_build_object('board_nr', board_nr)
FROM szansa_blitz_plan;

-- Fill federation metadata omitted by the PGN-first importer, using the
-- captured source. Preserve existing nonempty values and every other field.
UPDATE public.games g SET board_nr = p.board_nr,
  players = jsonb_build_array(
    (g.players->0) || jsonb_strip_nulls(jsonb_build_object('fed',
      coalesce(nullif(g.players->0->>'fed', ''), nullif(p.white_fed, '')))),
    (g.players->1) || jsonb_strip_nulls(jsonb_build_object('fed',
      coalesce(nullif(g.players->1->>'fed', ''), nullif(p.black_fed, '')))))
FROM szansa_blitz_plan p WHERE g.id = p.game_id;

DO $$
BEGIN
  IF (SELECT count(*) FROM public.games WHERE round_id = '5G3B46In') <> 15
    OR (SELECT count(*) FROM broadcasting_private.game_deletions WHERE round_id = '5G3B46In') <> 30
    OR (SELECT count(*) FROM broadcasting_private.game_overrides WHERE round_id = '5G3B46In') <> 15 THEN
    RAISE EXCEPTION 'Blitz counts do not match the repair plan';
  END IF;
  IF EXISTS (SELECT 1 FROM public.games WHERE round_id = '5G3B46In'
      GROUP BY name HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'Duplicate Blitz pairings remain';
  END IF;
  IF EXISTS (SELECT 1 FROM public.games g WHERE g.tour_id = 'I61J1bbh'
      AND broadcasting_private.game_is_removed(g.round_id, g.id, g.lichess_id,
        g.player_white, g.player_black)) THEN
    RAISE EXCEPTION 'A tombstone would block a surviving Blitz game';
  END IF;
END $$;
