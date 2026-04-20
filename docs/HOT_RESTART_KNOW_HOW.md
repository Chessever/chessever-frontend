# Hot Restart / Hot Reload Know-How

> **TL;DR** — `R` (hot restart) is unreliably slow on this app (60–130 s or appears to hang). This is a known Flutter framework limitation, not our code. Use `r` (hot reload) for iteration; do `q` + `flutter run` if you need a truly fresh start. The sections below document exactly why, which files are involved, and what we've tried.

---

## 🔴 Primary Culprits — Confirmed by Bisection

These are the specific Dart symbols whose removal during bisection made hot restart go from "hangs" → "works". Ranked by confirmed impact:

### 1. `_ForYouEventGamesController` constructor calling `requestRefresh()`

- **File:** [`lib/providers/for_you_games_provider.dart`](../lib/providers/for_you_games_provider.dart) — the class definition at the bottom of the file; the call is in the constructor body.
- **What it does:** Every time an `eventGamesProvider(eventId)` instance is created (once per visible ForYou tournament card — 20+ simultaneously), the constructor immediately fires `requestRefresh()` → `_performRefreshLoop()` → 2× `_computeForYouEventGamesSnapshot()` → many Supabase HTTP queries + `ref.read` of `liveTourIdProvider`/`liveRoundsIdProvider` (which open Supabase Realtime WebSockets).
- **Bisection evidence:** Commenting out the `requestRefresh()` line in the constructor → hot restart completes instantly. Re-enabling it → hot restart hangs 60–130s. This is **the single biggest contributor**.

### 2. `eventGamesProvider` family provider body

- **File:** [`lib/providers/for_you_games_provider.dart`](../lib/providers/for_you_games_provider.dart) — lines ~583–626.
- **What's in the body:**
  - `ref.keepAlive()` (keeps provider alive forever during session)
  - `Timer(Duration(minutes: 5), link.close)` — 5-minute retention timer
  - **9 `ref.listen` subscriptions**: `eventPinRefreshProvider`, `forYouEventsRefreshProvider`, `favoritesVersionProvider`, `countryDropdownProvider`, `autoPinPreferencesProvider`, `currentUserProvider`, `liveTourIdProvider`, `liveRoundsIdProvider`, `currentSelectedTourIdForEventProvider` — each fires `controller.requestRefresh()` on any update.
- **Why it's a culprit:** Multiplies. 20 event controllers × 9 listeners = 180 active listener callbacks. Three of those dependencies (`liveTourIdProvider`, `liveRoundsIdProvider`, `currentSelectedTourIdForEventProvider`) are stream providers backed by Supabase Realtime — any socket blip triggers 20 parallel `requestRefresh()` calls.

### 3. `liveGroupBroadcastIdsProvider` — multi-stream + Timer.periodic combo

- **File:** [`lib/screens/group_event/providers/live_group_broadcast_id_provider.dart`](../lib/screens/group_event/providers/live_group_broadcast_id_provider.dart)
- **What it does in one provider body:**
  - Opens 2 Supabase Realtime streams (`subscribeToLiveGroupBroadcastIds`, `subscribeToLiveRoundIds`)
  - Creates a manual `StreamController<List<String>>`
  - Starts a `Timer.periodic(Duration(minutes: 1))`
  - Has a multi-step `ref.onDispose` cleanup
- **Why it's a culprit:** Hot restart leaks all three at once (Flutter doesn't call `ref.onDispose`). This provider alone accounts for 2 of the lingering Supabase WebSockets + a repeating timer.

### 4. `gameUpdatesStreamProvider` / `gamePgnStreamProvider` — per-game Supabase streams

- **File:** [`lib/screens/chessboard/provider/game_pgn_stream_provider.dart`](../lib/screens/chessboard/provider/game_pgn_stream_provider.dart) (+ the underlying [`lib/repository/supabase/game/game_stream_repository.dart`](../lib/repository/supabase/game/game_stream_repository.dart))
- **What it does:** Opens one Supabase `.from('games').stream()` channel **per live game on screen**. On a busy tournament day that's 15–40 open WebSocket channels.
- **Why it's a culprit:** Each channel gets a Dart callback + native WebSocket that persists across hot restart. `realtime.disconnect()` in reassemble terminates the socket, but the channel metadata in `Supabase.instance.client` still leaks.

### 5. `liveTourIdProvider` + `liveRoundsIdProvider`

- **Files:** [`lib/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart`](../lib/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart), [`lib/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart`](../lib/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart)
- **What they do:** Each is a one-line `AutoDisposeStreamProvider` wrapping `settingsRepositoryProvider.subscribe…()`. Individually tiny — but subscribed to by every `eventGamesProvider` (see culprit #2), which fans the fan-out.

### 6. (Secondary) `StockfishSingleton` eval queue

- **File:** [`lib/screens/chessboard/provider/stockfish_singleton.dart`](../lib/screens/chessboard/provider/stockfish_singleton.dart)
- **Why secondary:** Already has a `prepareForHotRestart()` hook called from `main.dart` reassemble. Still contributes pending FFI + isolate work to the drain time, but not the primary hang source.

### Bisection call graph (what happens when you navigate to ForYou)

```
HomeScreen
 └─ BottomNavBarView
     └─ _buildScreen(tournaments) → GroupEventScreen
         └─ _ForYouGamesWidget (for active tab forYou)
             └─ ListView.builder per event
                 └─ _ForYouEventSection (one per event, 20+ total)
                     └─ ref.watch(forYouEventGamesWithAutoRefreshProvider(eventId))
                         └─ ref.watch(eventGamesProvider(eventId))  ← culprit #2
                             └─ new _ForYouEventGamesController()   ← culprit #1 (constructor starts refresh)
                                 └─ requestRefresh()
                                     └─ _performRefreshLoop()
                                         └─ _refreshOnce() × 2
                                             └─ _computeForYouEventGamesSnapshot()
                                                 └─ _loadForYouResolvedEventData()
                                                     ├─ tourRepository.getTourByGroupId()     ← Supabase HTTP
                                                     ├─ ref.read(liveTourIdProvider)          ← culprit #5 (opens WS)
                                                     ├─ ref.read(liveRoundsIdProvider)        ← culprit #5 (opens WS)
                                                     ├─ gameRepository.getMostRelevantTourId()
                                                     ├─ loadGames() → gamesStorage           ← SQLite + network
                                                     └─ roundRepository.getRoundsByTourId()   ← Supabase HTTP
                         └─ for each live game: ref.watch(gameUpdatesStreamProvider(gameId))  ← culprit #4 (WS per game)
```

Each of the 20+ `_ForYouEventSection` widgets independently walks this chain, resulting in **20+ concurrent async refresh pipelines + 30–80 open Supabase WebSocket connections** at steady state — all of which survive hot restart because Flutter never calls `dispose()`.

---

## 1. Symptom

- Press `R` in `flutter run` while the ForYou tab (or any post-auth screen) is loaded.
- Flutter prints `Performing hot restart...` and the spinner animates.
- 60–130 seconds later it usually prints `Restarted application in Xms.` — but often the developer gives up, force-kills the session, and `simctl` reports `found nothing to terminate` because the app is fine, just slow to reach VM quiescence.
- `r` (hot reload) generally completes in < 1 second. `R` does not.

---

## 2. Root Cause — Flutter Framework Limitation

Upstream issue: **[flutter/flutter#69949 — Hot restart should dispose widgets](https://github.com/flutter/flutter/issues/69949)** (open since 2020, P3, no linked PRs, no progress on master).

On hot restart, Flutter:

1. Pushes the new kernel.
2. Resets Dart-side state (globals, providers, widget tree).
3. **Does NOT call `dispose()`** on any widget or plugin.
4. Re-runs `main()`.

Consequence: anything holding a native resource (WebSockets, HTTP sockets, `Timer.periodic`, FFI engine handles, plugin-native threads) **leaks across hot restart**. The VM has to drain all pending microtasks / async futures from the old run before the new `main()` can settle, which is what makes `R` slow.

Supabase Flutter acknowledges this in [supabase-flutter#1088](https://github.com/supabase/supabase-flutter/issues/1088) and [supabase-flutter#1094](https://github.com/supabase/supabase-flutter/issues/1094):

> "This seems more like a Flutter issue. See flutter/flutter#69949."

Supabase Flutter ships a hot-restart cleanup (`hot_restart_cleanup_web.dart`) that stores a dispose function in a JS global so the NEW client can dispose the OLD one on re-init. **On mobile this is a no-op stub** (`hot_restart_cleanup_stub.dart`) — there's no analog because mobile can't stash state across isolate restart.

---

## 3. Why This App Hits It Hard

Because of the concurrency pattern in the tournaments flow:

| Resource | Count at peak | Why it exists |
|---|---|---|
| `eventGamesProvider` (family) instances | **20+** (one per visible tournament card) | Lazy snapshot for each ForYou event |
| `_ForYouEventGamesController._performRefreshLoop` | 20+ concurrent async chains | Each kicks off in constructor |
| `ref.listen(...)` callbacks per controller | **9** (live ids, favorites, country, pins, etc.) | Re-triggers refresh on any dependency change |
| `liveTourIdProvider` / `liveRoundsIdProvider` | 2 `AutoDisposeStreamProvider`s backed by Supabase `.from('settings').stream()` | Live-round tracking |
| `liveGroupBroadcastIdsProvider` | Custom `AutoDisposeStreamProvider` with 2 Supabase streams + 1-minute `Timer.periodic` + `StreamController` | Resolves live events |
| `gameUpdatesStreamProvider(gameId)` | One per live game card on screen (can be 15–40) | Live board updates |
| `gamePgnStreamProvider(gameId)` | One per open chess board | Live PGN |
| `game_clock_stream_provider` | One per visible clock | Live clocks |
| Stockfish eval queue | Up to 60 pending jobs, each FFI + isolate | Local engine analysis |

So on a single "Performing hot restart..." event, the VM must unwind: **~20 parallel async refresh loops, tens of Supabase WebSocket subscriptions, pending HTTP queries from each refresh, plus Stockfish FFI + isolate work** — none of which get `dispose()` called.

---

## 4. Files Involved (Primary Suspects)

### 4.1 The ForYou refresh machinery

| File | What it does |
|---|---|
| [`lib/providers/for_you_games_provider.dart`](../lib/providers/for_you_games_provider.dart) | Hosts `eventGamesProvider` (per-event family), `forYouEventsProvider`, `forYouEventGamesWithAutoRefreshProvider`, `_ForYouEventGamesController` (the big refresh loop). This is where the 20+ concurrent refresh loops originate. |
| [`lib/screens/group_event/widget/for_you_games_widget.dart`](../lib/screens/group_event/widget/for_you_games_widget.dart) | ListView of events; each event watches `forYouEventGamesWithAutoRefreshProvider` which in turn triggers `eventGamesProvider` creation. |

### 4.2 Supabase realtime stream providers

| File | Streams opened |
|---|---|
| [`lib/repository/supabase/settings/settings_repository.dart`](../lib/repository/supabase/settings/settings_repository.dart) | `subscribeToLiveRoundIds`, `subscribeToLiveTourIds`, `subscribeToLiveGroupBroadcastIds` — each a `.from('settings').stream()` |
| [`lib/screens/group_event/providers/live_group_broadcast_id_provider.dart`](../lib/screens/group_event/providers/live_group_broadcast_id_provider.dart) | Custom `StreamController` + 2 Supabase streams + `Timer.periodic(1 min)` |
| [`lib/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart`](../lib/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart) | `AutoDisposeStreamProvider` |
| [`lib/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart`](../lib/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart) | `AutoDisposeStreamProvider` |
| [`lib/repository/supabase/game/game_stream_repository.dart`](../lib/repository/supabase/game/game_stream_repository.dart) | `subscribeToPgn`, `subscribeToLastMove`, `subscribeToFen`, `subscribeToStatus`, `subscribeToGameUpdates` — one channel per game |
| [`lib/screens/chessboard/provider/game_pgn_stream_provider.dart`](../lib/screens/chessboard/provider/game_pgn_stream_provider.dart) | `gamePgnStreamProvider`, `gameUpdatesStreamProvider` families |
| [`lib/screens/tour_detail/games_tour/providers/game_clock_stream_provider.dart`](../lib/screens/tour_detail/games_tour/providers/game_clock_stream_provider.dart) | Per-game clock streams |
| [`lib/repository/library/library_repository.dart`](../lib/repository/library/library_repository.dart) | `subscribeFolders`, `subscribeAnalyses` — library streams |

### 4.3 FFI / native engine

| File | What it does |
|---|---|
| [`lib/screens/chessboard/provider/stockfish_singleton.dart`](../lib/screens/chessboard/provider/stockfish_singleton.dart) | Stockfish engine with FFI + job queue. Has `prepareForHotRestart()` that we call from reassemble. |
| [`lib/utils/audio_player_service.dart`](../lib/utils/audio_player_service.dart) | `flutter_soloud` native audio engine. Teardown only on lifecycle pause/detach, not reassemble. |

### 4.4 The reassemble hook

[`lib/main.dart`](../lib/main.dart) → `_StartupGateState.reassemble()`:

```dart
@override
void reassemble() {
  StockfishSingleton().prepareForHotRestart();
  try {
    Supabase.instance.client.realtime.disconnect();
  } catch (_) {}
  super.reassemble();
}
```

This is kept **minimal on purpose**. Earlier experiments with more aggressive cleanup (invalidating 9 provider families, flipping a global `kForYouShuttingDown` kill-switch, deferring `requestRefresh()` via microtask / `ensureInitialRefresh()` pattern) all **broke hot reload** — they tore down state that hot reload is supposed to preserve, causing shimmer-forever on the ForYou tab. The fix landed on: do the minimum that's safe for both reload & restart; accept that restart will be slow.

---

## 5. What We Tried (And Why It Didn't Fully Work)

Documented so we don't re-try the same things.

### 5.1 Package upgrades (partial improvement, kept)

All of these are now in `pubspec.yaml`:

- `stockfish` 1.7.2 → 1.8.1
- `flutter_soloud` 3.3.7 → 4.0.2 (changelog calls out: "fix: rebind Dart callbacks after hot restart #444", "possible fix for #333 which caused an ANR on Android when stopping/deinit")
- `sentry_flutter` 9.7.0 → 9.18.0
- `supabase_flutter` 2.12.0 → 2.12.4 (+ `gotrue` → 2.20.0, `postgrest` → 2.7.0, `realtime_client` → 2.7.3, `storage_client` → 2.5.2, `supabase` → 2.10.6)
- `chessground` 7.3.0 → 9.0.0 (required `dartchess` → 0.12.3; `onMove` callback signature changed `NormalMove → Move`, `isDrop/isPremove → viaDragAndDrop`)
- `heroine` 0.5.0 → 0.7.2
- `terminate_restart` 1.0.11 → 1.1.0
- **removed** `flutter_local_notifications` (was never actually used — only `initialize()` called, no `show*` anywhere)

Didn't fix the hang but reduced known FFI-hot-restart bugs.

### 5.2 Disabling SDKs in debug mode (tried, reverted)

Tried gating Sentry / OneSignal / RevenueCat / AppsFlyer init behind `kDebugMode`. Didn't move the needle — the hang isn't in those SDKs, it's in the Supabase-heavy ForYou refresh.

### 5.3 Stockfish Isolate.run in `prepareForHotRestart` (tried, reverted)

Tried removing the `Isolate.run(...)` wrapper in `_rawStockfishStdin` during reassemble (theory: spawning helper isolates during VM quiescence is racey). Didn't change behavior.

### 5.4 Disabling UIScene / Live Activities (tried, reverted)

iOS crash reports (`ExcUserFault_Runner-*.ips`) showed `EXC_GUARD` / `GUARD_TYPE_USER` with `xpc_connection_copy_bundle_id` from `BoardServices`. Theory: UIScene's BoardServices XPC handshake misfires during Flutter hot restart. Commented out `UIApplicationSceneManifest` in `Info.plist` — didn't fix hot restart. The EXC_GUARD is downstream noise, not the root cause; the XPC fault is what iOS does to a process that's been non-quiescent too long, not the thing causing the slowness.

### 5.5 Aggressive reassemble hook (tried, REVERTED because it broke hot reload)

Tried in `StartupGate.reassemble()`:

1. Global `kForYouShuttingDown = true` flag with bail-out checks at every `await` in `_performRefreshLoop` / `_refreshOnce` / `_fetchPage` and in the 9 `ref.listen` callbacks.
2. `container.invalidate(eventGamesProvider)` + 8 more provider families.
3. `StockfishSingleton().cancelAllEvaluations()`.
4. `Supabase.instance.client.removeAllChannels()` + `realtime.disconnect()`.

The reassemble hook fires on **both hot reload and hot restart** — Flutter doesn't distinguish. So the invalidations + kill-switch flag nuked hot reload state: ForYou tab went to shimmer and never came back because:
- `kForYouShuttingDown` was set to `true` during reassemble and never reset (hot reload doesn't re-run `main()`).
- Refresh loops in new controllers saw the flag and bailed out immediately.

**Lesson learned**: you can't add aggressive teardown to `reassemble` because there's no way to tell hot reload from hot restart inside it. Anything you tear down in reassemble hurts hot reload.

### 5.6 Widget-driven `ensureInitialRefresh` (tried, REVERTED)

Moved `requestRefresh()` out of `_ForYouEventGamesController` constructor into a `void ensureInitialRefresh()` method called from `_ForYouEventSection.build`. Idea: tie refresh lifecycle to widget mount so hot restart doesn't find pending work.

Didn't help because the refresh loops were still firing from the 9 `ref.listen` subscriptions (which are wired up in the provider body, not the widget). Reverted to keep the code simpler.

### 5.7 Flutter framework PR status (checked)

Looked at Flutter master & open PRs. No active work on #69949. Priority P3. Won't be fixed soon.

---

## 6. Current State — What's In Main

Minimal and safe for both hot reload & hot restart:

```dart
// lib/main.dart
@override
void reassemble() {
  StockfishSingleton().prepareForHotRestart();
  try {
    Supabase.instance.client.realtime.disconnect();
  } catch (_) {}
  super.reassemble();
}
```

The ForYou refresh machinery is back to the pre-experiment state:
- `_ForYouEventGamesController` kicks `requestRefresh()` from its constructor.
- Provider has its `keepAlive` + 5-min `Timer` + all 9 `ref.listen`s.
- `forYouEventGamesWithAutoRefreshProvider` watches `gameUpdatesStreamProvider` for each live game.

---

## 7. Workarounds for Daily Dev

1. **Use `r` (hot reload) for ~95% of iteration.** It works and is fast.
2. When you actually need `R`, **either wait up to 2 minutes** OR **`q` + `flutter run`** (often quicker).
3. If you're working on the ForYou tab specifically and need frequent `R`, consider temporarily:
   - Navigating OUT of the ForYou tab before hitting `R` (fewer active controllers = faster restart).
   - Adding an `if (kDebugMode) return;` short-circuit at the top of `ForYouNotifier._loadInitial()` — reduces concurrent refresh count during dev.

4. Known-good physical device is generally faster than the simulator for hot restart (simulator `xpc` overhead amplifies the slowness).

---

## 8. If You Want To Actually Fix It

The only real fix paths are architectural:

### Option A: Serialize refreshes

Replace 20+ parallel `_ForYouEventGamesController` refresh loops with a single global queue that drains one event at a time. Changes concurrency from 20 → 1; `R` drain time falls proportionally. Cost: ForYou tab is slower on cold start (events load sequentially instead of in parallel).

### Option B: Mount-lazy controllers

Don't construct `eventGamesProvider` instances until their corresponding `_ForYouEventSection` is actually on-screen (via scroll visibility detection + `autoDispose` without `keepAlive`). Limits concurrent controllers to ~5–8 (visible count) instead of 20+.

### Option C: Contribute upstream

Implement a mobile version of `supabase_flutter/lib/src/hot_restart_cleanup_web.dart` that stashes the dispose function via a platform-channel singleton on the native side. File a PR to supabase/supabase-flutter. This fixes the Supabase side of the problem for every Flutter mobile user.

None of these are trivial; all are out of scope for "make hot restart snappy tomorrow."

---

## 9. Reference Links

- Flutter framework: https://github.com/flutter/flutter/issues/69949 (open, P3)
- Flutter parent: https://github.com/flutter/flutter/issues/10437 (open since 2017)
- Supabase reports: https://github.com/supabase/supabase-flutter/issues/1088, https://github.com/supabase/supabase-flutter/issues/1094
- Supabase mobile-cleanup stub (source of the problem on iOS/Android): `~/.pub-cache/hosted/pub.dev/supabase_flutter-2.12.4/lib/src/hot_restart_cleanup_stub.dart`
- Supabase web-cleanup reference implementation: `~/.pub-cache/hosted/pub.dev/supabase_flutter-2.12.4/lib/src/hot_restart_cleanup_web.dart`

---

_Last updated: 2026-04-20 by joint debugging session. Keep this doc current if you try new approaches — it's the collective memory of "we tried X, it didn't work because Y" for this specific hot-restart problem._
