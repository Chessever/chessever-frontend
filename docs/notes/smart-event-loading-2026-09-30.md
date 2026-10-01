# Smart Event Games loading

The failing saved event was GM + C44 + classical + completed. Production's
old candidate lookup started at 2026-09-29; the newest actually qualifying
game was on 2026-08-29. Eleven intervening candidate days contained no matching
games, requiring repeated day, roster, metadata and history requests.

The repository also waited for an older-day query before returning a loaded
day. A separate thirteen-day skip limit could return a false empty result.
An 8,000-row cap could silently truncate an unusually large day.

## Changes

- A new invoker RPC resolves the newest day using the exact two-player average,
  status, format and exact ECO set. Search, result, year, rating ceiling,
  online/OTB and exclusive date cursors travel with the query.
- ECO families use one indexed ordered lookup per exact code. Bound dynamic
  queries avoid reusing a broad generic plan for a rare combination.
- Smart Events opt into deferred older-day resolution. Existing resolved-day
  callers retain their default behavior and cursor shape.
- Thin game candidates embed event time control without a broadcast predicate,
  avoiding global round rosters and separate tour/broadcast requests.
- Complete days paginate with a stable ID tiebreaker until the final short
  page. Sparse history no longer stops at thirteen candidate days.
- Older databases fall back when the new RPC is absent; real query failures
  propagate rather than becoming a false empty result.

## Production rollout

The explicitly authorized production app project was oelbsuggrzyqwzmvidju.
Smart Event Games uses that Supabase games table, so no Gamebase or broadcasting
service change was needed.

Both new indexes were built concurrently and verified ready/valid. The new
RPC and pure rating helper are invoker functions with fixed empty search paths.
No existing endpoint, table row, RLS policy, trigger or writer workflow was
changed. The pure helper is executable by existing writer roles for index
maintenance. The additive migration is recorded as 20260930143102.

## Validation

- Production matrix: all 4 status selections × 8 format selections × 5
  levels × 5 opening shapes, 800 combinations, zero differences from an
  independent oracle over existing production data. Verification uses only
  temporary tables and rolls them back.
- Final matrix timing: 9.1 ms at the 95th percentile; 31 ms slowest lookup.
  These are database execution timings, not device paint measurements.
- Anonymous production API replay: failing C44 event's complete first day
  took 0.857 and 0.808 seconds over three requests. GM Rapid took 0.760 and
  0.748 seconds; Najdorf GM 0.526 and 0.537 seconds; All Games 0.857 and
  0.779 seconds. Empty selection returned in 0.223 and 0.213 seconds.
- Regression coverage exercises the real repository/provider with pending
  history, resolved legacy cursors, fifteen sparse candidate days, a complete
  8,001-game day, midnight spillover, and the actual RPC parameter matrix.
- Scoped Flutter analysis is clean. Existing builder/layout, filter parity,
  provider and route-state checks pass. No app or Flutter build was run.

The UI review found no new visual treatment to audit: this change only alters
data loading. Existing route state, large text, contrast and builder control
tests cover the applicable UI rules.

## Device check on the production build

1. Open the saved GM Scotch Gambit event and verify Games appears promptly.
2. Scroll into older days; confirm games remain visible while history loads.
3. Open a board, return, switch About/Events/Games and reopen the event.
4. Change level, format and opening; verify empty combinations settle and
   restoring the original filters restores their games.

Run the read-only API timing script with python3 scripts/check_smart_event_loading.py.
The SQL matrix check lives in scripts/verify_smart_event_day_matrix.sql;
explicitly select the production database before executing it.
