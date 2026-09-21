# Olympiad performance audit

Date: 2026-09-21. Scope: tournament Games tab, full-board vertical scrolling,
mini-board hydration, team matchups, classification/NAG rendering, and event video.
Changes are local frontend edits. No backend data, configuration, deployment,
production branch, Sentry settings, or video-quality policy was changed.

## Reproduced bottleneck

Production access and simulator tracing were explicitly authorized by the user.
The reproduction used the public Current events feed without creating an account:
46th FIDE Chess Olympiad 2026, Open, Round 6, Abdusattorov vs Praggnanandhaa.
The board route held **2,456 games**, with **33 available streams** and the
**FIDE Chess - Main Commentary** YouTube stream playing. Device Hub ran an
**iPhone 17 Pro simulator, iOS 26.4.1, Flutter debug mode**.

The CPU trace identified repeated round-metadata refreshes as the leading app
hotspot while vertically scrolling the full board. Supabase round-table ingestion
updates triggered `_GamesAppBarNotifier._load`, round completion/sorting,
`gamesTourGroupedProvider`, team regrouping, and mini-board builds in the covered
tournament route. The video and foreground board competed with work for thousands
of games that the reader could not see.

The repository now compares only fields consumed by `Round.fromJson` across
consecutive Realtime records. Unchanged ingestion bookkeeping no longer causes a
catalog reload. Initial events, real metadata edits, insertions, deletions,
partial records, and reconnects still reconcile. Live moves, clocks, game status,
and live-round subscriptions are unchanged. Failed reconciliations retry with
2-to-30-second backoff; missing rounds finish the existing bounded deletion grace
period without relying on unrelated heartbeats. Those timers stop on disposal.

### Frame evidence

Each 18-second run used ten alternating vertical drags; the 40-second run used
twenty and crossed the video metadata refresh interval. Native playback was
verified in Device Hub and the video session. No unit-test process ran during
capture. Values are from Flutter's `Flutter.Frame` extension events.

| Capture | Frames | Build p95 | Build maximum | Builds >16.667 ms | Raster p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Before metadata filtering, 18 s | 503 | 22.945 ms | 32.128 ms | 26 | 2.179 ms |
| After filtering, 18 s | 443 | 1.361 ms | 2.818 ms | 0 | 2.189 ms |
| Extended verification, 40 s | 922 | 1.774 ms | 9.229 ms | 0 | 2.239 ms |
| Final code including recovery, 18 s | 442 | 2.349 ms | 8.993 ms | 0 | 2.150 ms |

The hidden tournament reload/regroup methods disappeared from the later CPU
samples. The baseline already included the earlier batching/catalog changes below;
this comparison isolates the metadata fix, not the combined benefit of every edit.
These are debug simulator measurements, not a physical-device release FPS promise.
Raster/Dart measurements do not include all native WebView, decoder, or compositor
cost. No controlled memory or long-duration leak improvement is claimed.

[Compact measurements and top sampled functions](olympiad-performance-trace-summary-2026-09-21.json)
retain the event IDs, method, and local raw-trace paths. Raw VM traces remain under
`/tmp/chessever-trace-olympiad-playing-*.json`; they are not checked into the repo.

## Additional resource reductions

| Area | Finding and change | Verification |
| --- | --- | --- |
| Full-PGN hydration | Batch size 16 previously allowed every batch to run concurrently. Cap at two requests, retaining only each batch's requests. Remove unmounted queued cards. | An 800-card fixture previously started 50 requests; now starts two. Cancellation, failures, remounting, pause/resume, and stale replies covered. |
| Scheduler lifetime | A remount could create another scheduler while old requests were running. Retain the scheduler until requests settle. | Remount regression verifies shared capacity; pause observation also survives remount. |
| Board catalog | Each visible game update copied/merged the entire event. Cache merges by immutable source identity and overlay at most three visible rows. | 8,000-game fixture performs 100 visible updates without further source-catalog reads. Snapshot bounds, immutability, and old values covered. |
| Card navigation | Mini-board rebuilds copied the whole event for one updated row. Use a read-only snapshot with a sparse override. | Hydration, nonblocking opens, scoped navigation, far jumps, and return mappings covered. |
| Team matchups | Each matchup rebuilt an event-wide index. Share one lazy immutable index per GamesScreenModel. | Same index reused across 2,000 accesses; team order/navigation tests retained. |
| Hidden tab | Retained Games tab remained active on About/Standings. Gate it with TickerMode, preserving its state. | Tournament widget test verifies the same Games state survives About → Games and is disabled while hidden. |
| Board switcher | Per-card CurvedAnimation instances added undisposed status listeners. Use CurveTween and remove redundant inner opacity; retain the outer fade and slide. | Existing switcher layout and far-navigation tests pass. |
| Stream selector | Repeated language detection compiled regexes and reparsed identical metadata. Compile patterns once and cache each immutable stream's inferred language, including null. | 50-stream fixture's repeated reads fall from 303 title reads per stream to one; existing language/selection behavior retained. |

The request and catalog counts are deterministic test-fixture results, not device
RAM measurements. No games, streams, annotations, result filters, or navigation
range were removed to obtain the improvements.

## Classification and NAG audit

The traced game displayed its notation and classification badges during scrolling.
Neither classification lookup nor NAG/icon rendering was a leading sampled
hotspot. The active-board resolver does work on that game's move tree; it does not
classify all 2,456 games on every scroll frame. Existing provider selections and
badge repaint boundaries remain intact. Classification rules, icon assets, report
precedence, PGN/source annotations, and user NAGs were left unchanged. The focused
suite includes board NAG previews, classification icon assets, and report-verdict
precedence tests.

Local Stockfish remains deliberately disabled for ordinary debug-board evaluation.
This run therefore does not establish physical-device performance with release
Stockfish, MultiPV, and video active together.

## Sentry findings and crash fixes

Production Sentry access to `algorithm-squad-fze/chessever` succeeded after login.
The following concrete Dart failures were traced to source and addressed:

| Issue | Fix and evidence |
| --- | --- |
| [CHESSEVER-1WE](https://algorithm-squad-fze.sentry.io/issues/142653997/) | A pending evaluation debounce read a disposed board notifier. Replace the global page-index-keyed debounce with a notifier-owned timer; cancel it during disposal and check mounted before reading state. The regression fails before the fix and passes afterward, including an index remap. |
| [CHESSEVER-1TQ](https://algorithm-squad-fze.sentry.io/issues/136694411/) | Explorer read `ScrollController.position` during a two-position attachment transition. Read only a single laid-out position, retain the previous evaluation window during the transition, and publish new metrics after layout. The regression recreates the reported call path, fails without the guards, and passes with them. |
| [CHESSEVER-1YD](https://algorithm-squad-fze.sentry.io/issues/146301696/) | Board metrics callbacks looked up View ancestors while deactivated. Cache FlutterView during dependency changes in both board and video host. A widget regression calls the host metrics callback while deactivated. |

Sentry also reports substantial native hangs and crashes. For example,
[CHESSEVER-1YC](https://algorithm-squad-fze.sentry.io/issues/146138938/) had 462 hang
events affecting 85 users in the queried period. Android
[CHESSEVER-1NH](https://algorithm-squad-fze.sentry.io/issues/130380965/) includes a
Flutter platform-view submission abort. Several native stacks are redacted or
unsymbolicated. These are not proven to be fixed by the Dart changes. The project
also contains desktop events, and issue counts do not provide a crash-rate
comparison or prove an Olympiad/video cause for every event.

## Validation

- Focused unit/widget suite: **354 tests passed across 36 files**.
- `flutter analyze --no-pub`: all **26 changed/new Dart files** checked.
- Regression coverage includes metadata filtering, network recovery, bounded
  deletion reconciliation, evaluation disposal, deactivated metrics, Explorer
  scrolling, live cards/clocks, batching, team ordering, retained tabs, board
  navigation, NAGs, and all event-video suites.
- Actual simulator checks: native video playback, vertical scrolling with
  notation/classification badges, video hide/restore and resumed playback.
- `git diff --check` passes. Validation completed before commit/push; no deployment
  was performed as part of this audit.

The relevant UI rules were rechecked against every changed surface: existing
layout, typography, palette, content, and controls are preserved; no decorative
UI was added. The board, notation, video, and controls were inspected in Device
Hub. This is not a claim to have exercised every app control on every device.

## Remaining device acceptance

The catalog still has proportional work when loaded or genuinely replaced. The
open switcher still groups changed input, selected video uses native resources,
and active engine analysis has its own CPU cost. No universal zero-jank or
all-crashes-fixed guarantee is justified by these measurements.

Before release, compare profile/release builds on an affected low-end phone and
the user's iPhone with the same event/stream. Exercise Games compact/grid/team
views, round/search/result filtering, board switching and far jumps, live
moves/clocks, and return navigation. Repeat with video playing, changing stream,
fullscreen, and engine/MultiPV enabled. Run at least ten minutes and compare frame
times, native/total memory, and memory after leaving the board. Record device,
release, event/round, stream, and timestamp for any remaining slowdown so it can
be matched to Sentry. This physical-device acceptance remains outstanding.
