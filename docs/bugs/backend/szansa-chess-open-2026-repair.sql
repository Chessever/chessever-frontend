-- Target: production project oelbsuggrzyqwzmvidju, explicitly authorized by user.
-- Event: szansa_chess_open_2026 / Rapid rQNo5wo2.
-- Source contains five empty duplicates in Round 1 and two superseded,
-- incorrectly attributed games in Round 4. Corrected PGNs were created at
-- 10:41:27/28 UTC, replacing the player attribution from 10:12:48 UTC.
-- Use existing admin tombstones and board overrides; no schema changes.
-- One-shot repair: snapshot preconditions deliberately reject a second run.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE TEMP TABLE szansa_repair_plan (
  game_id text PRIMARY KEY,
  round_id text NOT NULL,
  original_board smallint NOT NULL,
  pgn_md5 text NOT NULL,
  corrected_board smallint
) ON COMMIT DROP;

INSERT INTO szansa_repair_plan VALUES
  ('7d8vi8UK', 'KIqLvAKj', 96, 'a2ccd9f7fa1bb2ca23a4d946c321a71f', NULL),
  ('hk7KEly0', 'KIqLvAKj', 97, '41cc29ee7673768e6d5d8cadc02afb03', NULL),
  ('R6KpYi5J', 'KIqLvAKj', 98, 'f5c59e789378a946adbb295649e3f82f', NULL),
  ('LBVfDTJB', 'KIqLvAKj', 99, 'b0628222d5ca35adb1637133ea013422', NULL),
  ('g6zQWMKk', 'KIqLvAKj', 100, '84f9c542bf664d5e13c31cb2d1566af5', NULL),
  ('PWbqFGB4', 'zne7zskZ', 12, 'e94016705dbafb54485c4ab33e32208e', NULL),
  ('441zAoBz', 'zne7zskZ', 13, 'dc9bf470d9ceef77872cca5cbb02418b', NULL),
  ('0iBRWOF5', 'zne7zskZ', 14, '38d59bfe06e54d2ef9809a68d58a3583', 12),
  ('7VD5pWw8', 'zne7zskZ', 15, '4f42d12591379a85672d296eef83fc99', 13);

DO $$
BEGIN
  PERFORM g.id FROM public.games g JOIN szansa_repair_plan p ON p.game_id = g.id
    FOR UPDATE OF g;
  IF (SELECT count(*) FROM public.games g JOIN szansa_repair_plan p ON p.game_id = g.id
      WHERE g.tour_id = 'rQNo5wo2' AND g.round_id = p.round_id
        AND g.board_nr = p.original_board AND md5(g.pgn) = p.pgn_md5) <> 9 THEN
    RAISE EXCEPTION 'Szansa snapshot changed; re-audit before repairing';
  END IF;
  IF EXISTS (SELECT 1 FROM broadcasting_private.game_overrides o
      JOIN szansa_repair_plan p ON p.game_id = o.game_id)
    OR EXISTS (SELECT 1 FROM broadcasting_private.game_deletions d
      JOIN szansa_repair_plan p ON p.game_id = d.game_id) THEN
    RAISE EXCEPTION 'Existing admin correction; do not overwrite';
  END IF;
END $$;

-- Deliberately omit player_white/player_black: these tombstones must block
-- only the obsolete IDs, never the surviving games with the same pairing.
INSERT INTO broadcasting_private.game_deletions
  (game_id, round_id, tour_id, lichess_id, board_nr, name, note)
SELECT g.id, g.round_id, g.tour_id, g.lichess_id, g.board_nr, g.name,
  CASE WHEN g.round_id = 'KIqLvAKj'
    THEN 'Szansa 2026 repair: empty source duplicate of a completed Round 1 game; ID-only tombstone.'
    ELSE 'Szansa 2026 repair: superseded Round 4 player attribution; keep corrected 0iBRWOF5 and 7VD5pWw8. ID-only tombstone.'
  END
FROM public.games g JOIN szansa_repair_plan p ON p.game_id = g.id
WHERE p.corrected_board IS NULL;

INSERT INTO broadcasting_private.game_override_events (game_id, round_id, action)
SELECT game_id, round_id, 'deleted' FROM szansa_repair_plan WHERE corrected_board IS NULL;

DELETE FROM public.games g USING szansa_repair_plan p
WHERE g.id = p.game_id AND g.round_id = p.round_id AND g.tour_id = 'rQNo5wo2'
  AND p.corrected_board IS NULL;

INSERT INTO broadcasting_private.game_overrides
  (game_id, round_id, tour_id, overrides, source_pgn, note)
SELECT g.id, g.round_id, g.tour_id, jsonb_build_object('board_nr', p.corrected_board), g.pgn,
  'Szansa 2026 repair: retain corrected source PGN and pin physical board from Round tag (4.12/4.13), not appended source list position (14/15).'
FROM public.games g JOIN szansa_repair_plan p ON p.game_id = g.id
WHERE p.corrected_board IS NOT NULL;

INSERT INTO broadcasting_private.game_override_events
  (game_id, round_id, action, columns, overrides)
SELECT game_id, round_id, 'applied', ARRAY['board_nr'],
  jsonb_build_object('board_nr', corrected_board)
FROM szansa_repair_plan WHERE corrected_board IS NOT NULL;

UPDATE public.games g SET board_nr = p.corrected_board
FROM szansa_repair_plan p WHERE g.id = p.game_id AND p.corrected_board IS NOT NULL;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.games g JOIN szansa_repair_plan p ON p.game_id = g.id
      WHERE p.corrected_board IS NULL OR g.board_nr <> p.corrected_board) THEN
    RAISE EXCEPTION 'Repair did not remove duplicates and correct board numbers';
  END IF;
  IF (SELECT count(*) FROM public.games WHERE round_id = 'KIqLvAKj') <> 95
    OR (SELECT count(*) FROM public.games WHERE round_id = 'zne7zskZ') <> 13 THEN
    RAISE EXCEPTION 'Unexpected repaired round counts';
  END IF;
  IF EXISTS (SELECT 1 FROM public.games WHERE tour_id = 'rQNo5wo2'
      GROUP BY round_id, players->0->>'name', players->1->>'name' HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'Duplicate pairings remain';
  END IF;
  IF EXISTS (SELECT 1 FROM public.games g WHERE g.tour_id = 'rQNo5wo2'
      AND broadcasting_private.game_is_removed(g.round_id, g.id, g.lichess_id,
        g.player_white, g.player_black)) THEN
    RAISE EXCEPTION 'A tombstone would block a surviving game';
  END IF;
  IF (SELECT count(*) FROM broadcasting_private.game_deletions d
      JOIN szansa_repair_plan p ON p.game_id = d.game_id
      WHERE p.corrected_board IS NULL AND d.player_white IS NULL AND d.player_black IS NULL) <> 7 THEN
    RAISE EXCEPTION 'Expected seven ID-only tombstones';
  END IF;
END $$;
COMMIT;
