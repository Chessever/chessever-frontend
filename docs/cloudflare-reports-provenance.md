# Reports using the existing saved PGN format

Reports now reads finished public broadcast games that carry saved ChessEver
report annotations. Cloudflare already writes this format to `games.pgn`
through its existing writeback. The loading fix adds a partial index for the
existing query; it requires no Worker deployment or report-format change.

The unused completion-column migration and its trigger test have been removed.
They were never applied to production. The local Cloudflare documentation and
prewarm SQL were restored to their existing behavior. Report generation,
writeback, prewarm selection, quotas, cache lifetime, and existing clients do
not need to change for this screen.

## Eligibility

An eligible game is finished and has a played mainline move carrying both:

- A ChessEver classification NAG (`$240` through `$247`), or a recognized legacy
  `[%chessever_annotation …]` directive.
- A valid numeric or mate evaluation.

The reader uses the board's existing classification helpers and the existing
PGN parser. Ordinary evaluations and standard quality glyphs alone do not
qualify. NAG codes quoted in comments, annotations in headers or side variations,
multi-game PGNs, and unreadable rows are excluded without failing the entire list.

This recognizes the saved report format, not server provenance. Imported or
locally generated reports can use the same format. The existing schema cannot
distinguish those from Cloudflare output. The Reports UI makes no claim about
which service generated a report.

## Infinite pagination

- Reports has no total-result cap or date cutoff. It reads newest games first,
  then id for equal timestamps, with undated games after dated games.
- Each request reads a page of 30 candidates using the existing columns and
  report filters. The next cursor comes from the last candidate, including
  rejected PGNs, so filtering cannot strand the list on an empty page.
- Timestamp/id cursors avoid progressively larger offsets. Duplicate game ids
  are discarded if a game moves between pages.
- The screen prefetches within 600 logical pixels of the bottom, continuing
  through filtered pages and short content until the viewport is filled or the
  query is exhausted. There is one active page load per list generation.
- A lazy sliver builds only visible rows and the nearby cache. It reuses the
  existing list, grid, and board cards with the complete loaded collection for
  previous/next navigation. Loaded PGNs are retained without per-card requests.
- A failed request preserves loaded cards and exposes Retry for the same page.
  Pull-to-refresh starts from the newest page; late responses from the old
  sequence cannot append stale games or move the new cursor.
- The Discovery tile uses a descriptive caption instead of presenting its
  former capped preview count as the total. Discovery preloads the actual first
  page, sharing that same request and parsed cards with Reports. Only the first
  page is cached for two minutes; leaving Reports releases subsequent pages.
  Expiry and failed requests release the cache. Pull-to-refresh bypasses and
  replaces it. The older preview method remains compatible for other callers.

## Loading failure and fix (2026-09-28)

The exact Reports HTTP request reproduced `500 / 57014` (statement timeout)
against the app's configured test branch, `odmekzlfunfocvedqusl`, in 3.75 seconds.
Even selecting only `id,last_move_time` timed out in 3.36 seconds. EXPLAIN showed
a sequential scan of all 27,385 games: the leading-wildcard PGN predicates had
no usable index. The test archive contains zero matching saved reports, so the
database scanned the whole archive even to return an empty list.

`supabase/manual/20260928152221_saved_reports_index_concurrently.sql` adds only
`games_saved_reports_page_idx`, a partial B-tree of `(last_move_time DESC NULLS
LAST, id ASC)` with the exact existing finished-status and PGN predicates. The
app still validates played-move annotations. The index stores timestamps and
ids; it does not duplicate PGNs or add report metadata, columns, triggers,
functions, policies, or writes to game rows. Existing report writebacks update
index membership automatically through ordinary PostgreSQL index maintenance.

The index was first built concurrently on the test branch. It is valid and
ready. The same public REST query, including all card columns and event joins,
now returns HTTP 200. Across eight first-page/dated-cursor/undated-cursor calls,
latency was 0.292–0.452 seconds (median 0.314). SQL execution was 0.052 ms using
an index scan. These are empty-result timings, not a populated production
benchmark. A separate local fixture validates 138 reports and future writebacks.

The app also bounds each Reports request to ten seconds and cancels a stalled
connection. It disables this request's automatic network/503/520 retries so
unavailability is exposed to the existing Retry control without repeated waits.
The installed SDK already does not retry HTTP 500: the observed statement
timeout was caused by the archive scan, not an HTTP-500 retry loop. Diagnostic
logs record the error code/type and elapsed time, without request credentials
or PGN contents.

Concurrent index creation permits ordinary reads and writes during the build,
but consumes CPU/I/O while scanning. Subsequent writes pay normal predicate/index
maintenance costs; this is not a zero-cost database change. Run the single
reviewed file with autocommit, not all pending migrations and not in a
transaction. Verify `pg_index.indisvalid` and `indisready` afterward. An interrupted
build can leave an invalid index that `IF NOT EXISTS` would skip; remove only
that invalid index concurrently before retrying. Rollback is removal of this
index with `DROP INDEX CONCURRENTLY public.games_saved_reports_page_idx`; no game
data or writer rollback is involved.

After the user identified `supabase_chessever_main` as the intended source, the
MCP confirmed project `oelbsuggrzyqwzmvidju`. Read-only checks found an estimated
1,240,013 games (8,554 MB including indexes) and no report index. The actual
production REST request reproduced `500 / 57014` in 3.43 seconds; its plan was a
parallel sequential scan plus sort. With the user's explicit approval, the same
reviewed index was then applied to this production project. The production app
already reads this main project through its normal Supabase client. Test-flavor
environment boundaries remain unchanged.

The production index is valid, ready, owned by `postgres`, and 392 kB. A verified
TLS session-pooler connection built it concurrently in 168.27 seconds, using a
ten-minute statement timeout and a thirty-second lock timeout in that maintenance
session only. The connection closed after completion; no database-wide or
application role timeout was changed. The initial Management API build had hit
its connection's statement timeout. Its invalid index was removed concurrently
before the successful build. No invalid index or active build remains.

Production verification after the build:

- The first full REST request returned 30 games with HTTP 200 in 0.723 seconds.
- Eight subsequent full REST requests, including dated and undated cursor
  shapes, completed in 0.326–0.680 seconds (median 0.575). Populated responses
  contained 30 games with PGNs and card/event metadata; undated results were empty.
- The actual Dart repository fetched and parsed four consecutive pages of 30
  reports: 0.793, 0.557, 0.515, and 0.555 seconds. All 120 game ids were distinct,
  all parsed games were finished, and every page supplied a continuation cursor.
- EXPLAIN ANALYZE used `games_saved_reports_page_idx`, read 30 rows, and executed
  the report selection in 0.414 ms. This SQL-only timing excludes HTTP, joins,
  transfer, and Dart parsing; the measurements above include those costs.
- Before/after fingerprints for game columns, existing triggers, and access
  policies matched; the table's grants also matched exactly. The deployed SQL
  contained no row mutation or change to report generation, functions, or clients.

These are measured API/repository results from this machine, not device-rendering
timings or a promise that every network request takes the same time. The app's
shared first-page prefetch/cache handles opening and reopening without another
request while that cache is fresh.

## Miniatures appearance

Reports uses the same game-card wrappers and the exact shared day-header widget
as Miniatures. Phone/tablet gutters, row gaps, day spacing, refresh treatment,
and scrolling physics match. Grid view has two columns, or four on landscape
tablets; its loading placeholders use the same column count and gutters.

Days can be collapsed and reopened. Pagination continues through a collapsed
day until it reaches visible older content or the actual end. Headers show the
date only, never the partial number of games loaded so far. Grouping preserves
the server's order so appending a page cannot reorder earlier cards. Each card
still opens the full loaded collection at its original index, using the correct
broadcast player-profile source.

## Validation

- Scoped Flutter analysis: no issues.
- 122 Flutter unit/widget tests passed for pagination, repository filtering,
  Discovery, game cards, and Miniatures regressions. Coverage includes loading
  120 games, cursor ties
  and undated games, legacy/Cloudflare PGNs, empty candidate pages, duplicate
  requests/games, refresh races, disposal, and error recovery.
- Widget checks in all three card layouts confirm prefetch before the bottom,
  lazy construction, stable scroll position on append, complete collection
  navigation, footer Retry, and pull-to-refresh. Day collapse/reopen continues
  pagination; phone and landscape-tablet grids align at enlarged text sizes.
- Schema-free filters and timestamp/id cursor traversal passed on disposable
  local PostgreSQL 16, including equal timestamps, old/undated rows, and a new
  insertion between pages. The local server was stopped afterward.
- The loading regression additionally runs
  `supabase/tests/reports_index.sql` on disposable local PostgreSQL 16. It checks
  the query plan, repeated parameterized reads past the prepared-plan threshold,
  unchanged game data, traversal of 138 reports with ties/old/undated rows, and
  normal PGN/status updates entering and leaving the index. No report trigger
  or classification column is involved.
- `python3 scripts/check_reports_query.py` is a read-only check against the
  explicitly verified `.env.test` target. It checks HTTP success and latency for
  repeated requests and both cursor shapes without printing credentials or PGNs.
- App regressions cover shared in-flight prefetch, cached reopening, page-cache
  expiry, release of later pages, manual-refresh cache replacement, recovery
  after failed prefetch, a single request on server errors, and cancellation of
  stalled connections.
- A separate read-only production smoke test passed through the real Dart
  repository and PGN parser, checking 120 distinct reports across four pages.

Design-law recheck: the requested Miniatures design supplies the card geometry,
gutters, type, palette, icons, and day-header styling. No replacement imagery,
fonts, decorative icons, gradients, glows, or entrance effects were added.
Cards and headings have explicit gutters; paired grid cards share their top
edge, including at enlarged text sizes. Loaded content stays visible during
paging and refresh. The existing loading indicator, collapse controls, and
Retry remain functional. Landing-page, hero, pricing, logo, and footer rules do
not apply to this game-list correction. Device verification remains the user's
responsibility.

Live-app checking is delegated to the user per repository rules. The test and
explicitly approved production databases received only the concurrent index
described above; their game data and report-writing workflows were not modified.

Device check: open Discovery → Reports and scroll near the bottom repeatedly.
More games should append in place. Open a game, return, change the card layout,
collapse/reopen a date, and pull to refresh. Compare card spacing with Miniatures
in the same view mode. With the network interrupted, loaded cards should remain
and Retry should resume paging after reconnection. Ordinary evaluations alone
should not qualify for the list. Return to Reports within two minutes: its first
page should be reused immediately. Pull-to-refresh must fetch fresh results.
The current test database has no matching report PGNs, so its correct response
is the empty state; populated cards require a target with saved reports.
