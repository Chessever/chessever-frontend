# Szansa Chess Open 2026: production repair

Applied on 2026-09-13 to Supabase project `oelbsuggrzyqwzmvidju`, after the
user confirmed the issue was in production. No app release or broadcasting
repository change was made.

## Findings and repair

- Rapid (`rQNo5wo2`), Round 1 (`KIqLvAKj`): the source contained five empty
  copies of completed pairings, appended as boards 96–100. Removed those
  five copies, retaining all 95 distinct pairings.
- Rapid, Round 4 (`zne7zskZ`): later source PGNs corrected a player-label
  swap on boards 12 and 13, but the older records remained. Retained corrected
  games `0iBRWOF5` and `7VD5pWw8`, removed `PWbqFGB4` and `441zAoBz`, and
  corrected the retained games' board numbers from 14/15 to 12/13. The PGN
  Round tags and later UTC timestamps identify the corrections.
- Blitz (`I61J1bbh`), Round 13 (`5G3B46In`): all 15 source chapter IDs were
  replaced twice during the investigation. The database grew to 45 records
  for 15 pairings. Retained the latest 15 source IDs and removed the 30
  superseded records. Filled missing federation values from the source.

All 37 removals use the existing private deletion ledger, with player-match
columns deliberately left null. This blocks only obsolete IDs and preserves
the valid records for the same players. The existing override system pins
board numbers for the two corrected Rapid games and all 15 final-round Blitz
games. Moves, clocks, results and player data remain unpinned.

The PGN importer initially inserted replacement IDs without `board_nr`, which
bypassed the override system's board-based identity matching. A narrowly
scoped BEFORE INSERT trigger now extracts boards 1–15 from the PGN Round tag
for this specific Blitz tour and round when `board_nr` is absent. Its name
places it before the existing game override trigger. No authorization or RLS
policies were changed; the helper is a private, security-invoker function with
a fixed search path and no PUBLIC execute grant.

## Validation

- The live-data audit initially failed on seven duplicate pairings and two
  wrong board numbers in Rapid, then caught the developing Blitz duplicates.
- The replacement-ID replay failed without the normalizer and passed with it.
- Transactional rehearsal and post-commit replay both passed, rolling back all
  replay writes. All 15 boards accepted a new source ID with a null board number
  as an update to the canonical record. All 37 obsolete IDs remained blocked.
- Fixture checks confirmed that the normalizer leaves other tours, other
  rounds, supplied board numbers, invalid tags and missing PGNs unchanged.
- Production audit after repair: **394 games, zero duplicate pairings, zero
  board-number/PGN mismatches**. Rapid has 199 games; Blitz has 195.
- Comparing surviving Rapid rows with the backup showed only the two intended
  `board_nr` changes. Their PGNs, results, moves and player data were untouched.
- Security advisors completed with no finding referencing the new function or
  trigger. Existing unrelated findings were left outside this repair's scope.

## Artifacts and operation notes

- `szansa-chess-open-2026-repair.sql`: committed Rapid data repair.
- `szansa-chess-open-2026-blitz-repair.sql`: committed Blitz data repair,
  executed in the same transaction as migration
  `20260913122910_normalize_szansa_blitz_round13_board_numbers.sql`.
- `szansa-chess-open-2026-replay.sql`: regression checks; execute only inside
  a transaction ending in ROLLBACK.
- Database changes were applied using the Management API against the explicit
  project ref, not a broad migration push. The local migration records the
  deployed guard; no migration-history row was manually inserted.
- Full before-repair snapshots are stored locally under
  `/Users/berkay/.codex/backups/szansa-chess-open-2026/` with owner-only access.
  Both data repairs are intentionally one-shot and reject changed snapshots.

For on-device confirmation, close and reopen the event, then inspect Rapid
Rounds 1 and 4 and Blitz Round 13. Live-app testing belongs to the user under
the repository rules.

Source rounds:
[Rapid Round 1](https://lichess.org/broadcast/szansa-chess-open-2026-rapid/round-1/KIqLvAKj),
[Rapid Round 4](https://lichess.org/broadcast/szansa-chess-open-2026-rapid/round-4/zne7zskZ),
[Blitz Round 13](https://lichess.org/broadcast/szansa-chess-open-2026-blitz/round-13/5G3B46In).
