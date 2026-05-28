# Realtime Live-Round & New-Games Fix — Implementation Design Spec (Approach 1)

> Status: draft for review · Date: 2026-05-28 · Trello: card #654 "Phone event refresh should fetch later live rounds"

## Problem Statement

The reported bug — "phone event refresh won't show a newly-started live round without an app restart" — is **frozen round status**, not a missing-rows / row-cap problem.

Round status is a pure function of `startsAt` vs `DateTime.now()` plus membership in `live_round_ids` (`lib/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart:48` `status()`). It is recomputed **only** at discrete events:

- `_GamesAppBarNotifier._load()` (event open / brand-new unknown `round_id` appears / knockout change) — `games_app_bar_provider.dart:646`.
- `_GamesAppBarNotifier._onLiveRoundsChanged()` (the live-rounds stream) — `games_app_bar_provider.dart:1262`.

`live_round_ids` arrives via `subscribeToLiveRoundIds()` (`lib/repository/supabase/settings/settings_repository.dart:26`), surfaced through `liveRoundsIdProvider` (`lib/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart:4`). **But `public.settings` is NOT in the `supabase_realtime` publication** (verified: only `public.games` is). So `.stream()` on `settings` delivers exactly **one snapshot at subscribe time, then goes silent forever**. The backend keeps `settings.live_round_ids` fresh (verified: single row `id=1`, currently 7 live rounds / 7 tours / 7 group broadcasts).

Titled Tuesday = ~100 games/round × 11 rounds, all rounds pre-created with staggered starts and **already fetched into memory at open** by `getGamesByTourId` (`lib/repository/supabase/game/game_repository.dart:268`). Open during R1 → R2 computed `upcoming`. When R2 starts, nothing recomputes: the settings stream is dead, the 10s games poll sees R2's `round_id` already known so it skips `_load()` (`games_app_bar_provider.dart:1245-1251`), and pull-to-refresh only refetches games not statuses. The "hide upcoming while something live/ongoing" filter (`games_app_bar_provider.dart:247`, mirrored in `games_tour_scroll_provider.dart:125`) keeps R2 hidden. Restart reruns `_load()` against a fresh clock → R2 `ongoing` → visible.

Two adjacent defects:
- The only new-row detector today is a wasteful 10s `Timer.periodic` full-tour refetch in `GamesTourNotifier` (`lib/screens/tour_detail/games_tour/providers/games_tour_provider.dart:82`).
- `getGamesByTourId` carries a brute 1000-row pagination `while(true)` loop (`game_repository.dart:278-312`) — a misdiagnosis band-aid to be removed.

## Goals & Non-Goals

**Goals**
1. A newly-started live round becomes visible on phone **without restart**, on all 5 surfaces, driven by real signals (control plane + UPDATE deltas + derived liveness) — **not** by INSERT detection, which does not fix pre-created staggered rounds.
2. Replace the 10s poll with a single per-tour realtime channel (INSERT + UPDATE + DELETE) on the open tour detail screen.
3. Remove the 1000-row pagination loop.
4. New cards/rounds appear **silently at the top** with a smooth streamed entrance, never disrupting scroll position, selection, or focus.
5. Zero polling anywhere after the change. No regressions to existing live-tour-id / For-You / group-broadcast behavior.

**Non-Goals**
- No server-side `postgres_changes` filters on array columns (`player_fide_ids`/`player_feds`) — physically unsupported (single-column scalar equality only).
- No per-tour INSERT channels on For You / favorites / countrymen / player profile (those use the control-plane refetch path).
- No standings/scoring changes (that is a separate in-flight diff; see Risks §R10).
- Not adding `public.rounds` to the realtime publication (no concrete consumer; deferred — see Backend Migration).

## Architecture Overview

A shared realtime backbone with four cooperating layers. **No polling. No 1000-row loop.**

```
                         ┌─────────────────────────────────────────────┐
                         │  public.settings (id=1) → realtime publication │
                         └───────────────────────┬─────────────────────┘
                                                 │ WAL UPDATE (diffed)
                  ┌──────────────────────────────▼───────────────────────────┐
                  │  liveControlPlaneProvider  (NEW, dedicated, diff-guarded)  │
                  │  emits SettingsDelta{liveRoundIds, liveTourIds, liveGBIds} │
                  └───┬───────────────┬──────────────────┬───────────────────┘
        event tab     │   For You      │   array-column     │   (existing liveTour/
   (round-id ∩ guard) │ (list-eq guard)│   surfaces (∩ guard)│    liveGB providers
                      │                │                     │    UNCHANGED)
            ┌─────────▼────────┐  targeted slice refetch (debounced, intersect-gated)
            │ gamesAppBar      │
            │ status recompute │◄──── (a) LOCAL clock tick (30–60s, promote-only)
            └─────────▲────────┘◄──── (b) games delta (status/last_move_time)
                      │
   ┌──────────────────┴─────────────────────────────────────────┐
   │ tourGamesRealtimeProvider(tourId)  (NEW, lifecycle-gated)    │
   │ raw channel.onPostgresChanges INSERT+UPDATE+DELETE           │
   │ filter: tour_id=eq.X  →  delta-merge via freshness ladder    │
   └─────────────────────────────────────────────────────────────┘
   per-card eq-id streams (game_stream_repository.dart) = latency opt for visible cards only
```

1. **Per-tour realtime channel (INSERT + UPDATE + DELETE)** — one long-lived raw `channel.onPostgresChanges` per *open* tour detail screen, `filter: tour_id=eq.X`. Delivers delta rows only. INSERT = late pairings; UPDATE = off-screen status/last_move corrections that feed round aggregation; DELETE = withdrawals. Replaces the poll's full responsibilities. **Not** `.stream().eq('tour_id')` (that re-holds the full row list + re-fetches the initial page).

2. **Settings control plane** — a dedicated, diff-guarded `settings` subscription. `live_round_ids`/`live_tour_ids`/`live_group_broadcast_ids` become a *push signal* ("the live set changed") that each surface listens to with an intersection/equality guard. (`public.settings` is a single **global backend-owned** row `id=1` — NOT user preferences — rewritten by `upsert_live_job_ids()` in `chessever_data_hub_monorepo/supabase_client.py:1043`, called per data-hub main-loop pass at `main_data_hub.py:556`/`:726`.)

3. **Derived liveness (PROMOTE-ONLY safety net)** — correctness does not depend on backend timing. A round/game is treated as live/ongoing if it has a `status='*'` game OR a `last_move_time` within a **time-control-aware** window. This may only *promote* a round into live/ongoing; it may **never demote** a round that backend `live_round_ids` marks live, nor flip a round out of live solely because `last_move_time` aged past a flat threshold.

4. **Local clock tick** — a coarse (30–60s) local `Timer.periodic` (NOT a network call) that re-runs status computation and early-returns when nothing changed.

## Backend Migration

Verified preconditions: `public.settings` and `public.rounds` both have replica identity `default(PK)` (sufficient for INSERT/UPDATE/DELETE deltas since PK is in every row); both have `SELECT` RLS policy `qual=true` for `{public}` (includes the anon role the realtime client connects as); only `public.games` is currently in `supabase_realtime`.

**Migration (additive, reversible) — `settings` only:**

```sql
-- Up: make the live control-plane row push WAL deltas to subscribed clients.
ALTER PUBLICATION supabase_realtime ADD TABLE public.settings;
```

```sql
-- Down (rollback): clients gracefully degrade to one-snapshot-at-subscribe behavior.
ALTER PUBLICATION supabase_realtime DROP TABLE public.settings;
```

**Verification:**

```sql
-- Confirm settings is now published (expect rows for both 'games' and 'settings').
SELECT tablename FROM pg_publication_tables
WHERE pubname = 'supabase_realtime' ORDER BY tablename;
```

**`public.rounds` is intentionally NOT added.** The stated fix (control plane + derived liveness + games-table deltas) does not require round-level realtime; `getRoundsByTourId` is a one-shot fetch in `_load()`. Adding `rounds` is speculative scope and additional WAL fan-out. Defer until a concrete round-delta consumer exists.

**Write cadence (measured 2026-05-29 from `chessever_data_hub_monorepo`):** the writer is `upsert_live_job_ids()` (`supabase_client.py:1043`), called once per data-hub main-loop pass (`main_data_hub.py:556`/`:726`). The main loop is ~145s with faster sub-passes during active events, so the `settings` row is rewritten on the order of every tens-of-seconds during live windows. It is a **full-payload upsert with NO writer-side change detection and `settings` has NO `updated_at`** → identical-value re-writes are common and still emit WAL UPDATEs. WAL volume is trivial (one tiny single-row event), so there is **no storm risk and no separate measurement gate** — but clients MUST diff payloads (`listEquals`) so no-op UPDATEs do no downstream work. This is enforced in the control-plane provider below.

## Shared Primitive: Control Plane + Per-Tour Channel

### A. `liveControlPlaneProvider` (NEW — `lib/repository/supabase/settings/live_control_plane_provider.dart`)

A single dedicated subscription that does **not** reuse the existing `liveRoundsIdProvider` / `liveTourIdProvider` / `liveGroupBroadcastIdsProvider` streams (those drive expensive consumers — see §R1/§R2). Add to `SettingsRepository` a single typed stream (extending `settings_repository.dart:21` `subscribeToSettings`) and expose:

```dart
class SettingsDelta {
  final List<String> liveRoundIds;
  final List<String> liveTourIds;
  final List<String> liveGroupBroadcastIds;
  // value equality on all three lists (listEquals) — REQUIRED for the diff guard.
}

/// Single realtime subscription to public.settings. Emits only when one of the
/// three live-id lists actually changes (settings has no updated_at → no-op
/// writes still arrive on the wire; we diff here so downstream never re-works).
final liveControlPlaneProvider = StreamProvider<SettingsDelta>((ref) { ... });
```

The provider:
- Diffs each emission against the last via `listEquals` (the pattern already used in `tour_detail_screen_provider.dart:80` and `live_group_broadcast_id_provider.dart:57`); suppresses no-op WAL events.
- **Reconnect/transient-empty guard:** if a reconnect snapshot momentarily delivers empty lists while the previous lists were non-empty, do NOT propagate the empty as "nothing is live"; treat empty-after-non-empty as "no information" pending corroboration (see derived liveness, §R12).

### B. `tourGamesRealtimeProvider(tourId)` (NEW — `lib/repository/supabase/game/tour_games_realtime_provider.dart`)

Raw channel, INSERT + UPDATE + DELETE, single eq filter:

```dart
final tourGamesRealtimeProvider =
  StreamProvider.autoDispose.family<GameDelta, String>((ref, tourId) {
    final channel = Supabase.instance.client.channel('tour_games:$tourId');
    for (final ev in [
      PostgresChangeEvent.insert,
      PostgresChangeEvent.update,
      PostgresChangeEvent.delete,
    ]) {
      channel.onPostgresChanges(
        event: ev, schema: 'public', table: 'games',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq, column: 'tour_id', value: tourId),
        callback: (payload) => controller.add(GameDelta.from(payload)),
      );
    }
    // keepAlive timer (cacheTime) so tab switches don't thrash the channel.
    final link = ref.keepAlive(); Timer(const Duration(seconds: 30), link.close);
    ref.onDispose(channel.unsubscribe);
    channel.subscribe();
    return controller.stream;
  });
```

- `GameDelta` carries `eventType` (insert/update/delete) + the row (`Games.fromJson` for insert/update, `id` for delete).
- **Lifecycle-gated by `shouldStreamProvider`** (`games_tour_provider.dart:8`): subscribe when `true`, `channel.unsubscribe()` when `false` (app backgrounded / chessboard open) — preserves the battery behavior the poll-stop currently gives (§R11).
- **Channel budget:** exactly ONE such channel per open tour detail screen. Do NOT replicate per-tour channels on For You / favorites / countrymen / player profile.

### C. Delta merge — reuse the existing freshness ladder

Reuse `GamesTourNotifier._mergeGameSnapshots` (`games_tour_provider.dart:163`) / `_hasGameChanged` (`:154`) and the per-card `_shouldUseIncomingGame` ladder (`live_game_card_provider.dart:417`):

- **INSERT/UPDATE:** merge by `id`; replace a field only when the incoming row is fresher by `(lastMoveTime, then ply, then status-transition)`. A bare INSERT (often null `last_move_time`) **must never clobber** a fresher streamed/cached snapshot. New ids bucket into the correct round (the grouped provider already buckets by `round_id`) — never blind-prepend to the flat list (§R6).
- **DELETE:** remove by `id` (the poll's removed-id check at `games_tour_provider.dart:140-144` moves here).

## Per-Surface Sections

### 1. Event Games tab — primary fix

**Current flow.** `GamesTourNotifier` (`games_tour_provider.dart:27`) loads via `gamesLocalStorage.fetchAndSaveGames` → `getGamesByTourId` (1000-row loop), then polls every 10s (`:82`). `_GamesAppBarNotifier` computes statuses at `_load()` (`:646`) and `_onLiveRoundsChanged()` (`:1262`), seeded from `liveRoundsIdProvider` snapshot (`:50`). Visibility filter hides `upcoming` when anything is live/ongoing (`:247`; mirror at `games_tour_scroll_provider.dart:125`). Scroll is index-based via `ScrollablePositionedList` + `gamesTourScrollProvider`.

**Exact changes by file.**

- `lib/repository/supabase/game/game_repository.dart:268` — replace the `while(true)` paginated `getGamesByTourId` with a single bounded `.select(...).eq('tour_id', tourId).order('id')` (optional `range` only when `limit` passed). Delete `_tourGamesFetchPageSize` / `shouldFetchAnotherTourGamesPage` usages tied to the loop.
- `lib/screens/tour_detail/games_tour/providers/games_tour_provider.dart` — **remove** `_refreshTimer`, `_startPeriodicRefresh`, `_stopPeriodicRefresh`, `_checkForNewGames` (`:48`–`:152`). Keep `_loadInitialGames` (`:50`) and the `_mergeGameSnapshots`/`_hasGameChanged` helpers (now reused by the delta path). Add a listener on `tourGamesRealtimeProvider(tourId)` that applies INSERT/UPDATE/DELETE deltas via the freshness ladder into the in-memory list, gated by `shouldStreamProvider` (reuse the existing `_shouldStreamListener` at `:33`).
- `lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart`:
  - Replace the `liveRoundsIdProvider` listen (`:55`) with a listen on `liveControlPlaneProvider.select((d) => d.liveRoundIds)`, **intersection-guarded**: only call `_onLiveRoundsChanged` when `liveRoundIds ∩ {this tour's round ids}` changes. Keep the constructor seed (`:50`) but source it from `liveControlPlaneProvider`'s current value.
  - Add a **local clock tick** (30–60s `Timer.periodic`) that re-runs `status()` for each model (promote-only) and early-returns if the resulting `List<GamesAppBarModel>` is `Equatable`-equal to the current one (props already defined at `games_app_bar_view_model.dart:95`), so it does NOT trigger `_sortRounds`/`_scrollToRound` unless a status actually transitioned.
  - Make `_onLiveRoundsChanged` (`:1262`) and the clock tick **promote-only**: never demote a round that backend `live_round_ids` still marks live; ignore an empty live set when the previous set was non-empty and no `status='*'`/recent-`last_move_time` corroboration exists (§R12).
- `lib/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart:48` `status()` — make derived liveness time-control-aware and fix the day-boundary classification (`:62` `startsAt.day == now.day`) independently (§R8/§crosscutting): a round started 23:50 must not flip to `completed` at local midnight while still live. Thread `last_move_time` recency and the tour's `time_control` (blitz ~10 min vs classical ~60 min) into the promote rule.

**After-flow.** Open during R1: realtime control-plane push (R2 enters `live_round_ids`) → intersection guard fires → `_onLiveRoundsChanged` recomputes → R2 `live`. Even if the backend push lags, the 30–60s clock tick promotes R2 to `ongoing` via `startsAt`/`last_move_time`. Late-arriving R2 pairings arrive as INSERT deltas; mid-round status corrections for off-screen R2 games arrive as UPDATE deltas feeding `_buildRoundGameCounts` / `hasLiveOrOngoing`. No poll, no full refetch.

**Smooth-silent insertion.** R2's round header + cards animate in at the top; scroll anchor preserved (Cross-cutting UI below).

### 2. For You — `lib/providers/for_you_games_provider.dart`

**Current flow.** Listens to `liveGroupBroadcastIdsProvider` (`:144`) to re-derive categories (already equality-checked at `:182-189`), but also **unconditionally** bumps `forYouEventsRefreshSignal` on every `liveTourIdProvider` (`:168`) and `liveRoundsIdProvider` (`:171`) emit — harmless today only because the streams are dead.

**Exact changes.**
- **Before flipping the publication**, add equality guards to `:168` and `:171`: compare previous vs next list (`listEquals`) and bump only on real change. (Otherwise reviving the stream fans a full slice refetch across every visible For You card on every settings WAL write.)
- Switch the two unconditional listens to `liveControlPlaneProvider` slices (`liveTourIds`, `liveRoundIds`) with the equality guard.
- Keep the existing `_refreshLiveCategories` (`:176`) path for category flips (it already diffs).

**After-flow.** A live-set change re-derives categories and triggers at most one diffed refetch for genuinely affected events. No per-tour INSERT channel here.

**Silent insertion.** For You cards reorder via the existing `_reSortList` (`:194`) / `withLiveIds` machinery; no scroll hijack.

### 3. Player profile (Games tab) — `lib/screens/tour_detail/player_tour/player_tour_screen_provider.dart`

**Current flow.** No live-set listener; visible-card freshness comes from per-card eq-id streams (`game_stream_repository.dart`). Pull-to-refresh `ref.invalidate`s the per-game streams.

**Exact changes.** Array-column query (`player_fide_ids`) → no server-side `postgres_changes`. Add a `liveControlPlaneProvider` listener that triggers a **targeted, debounced (3–5s trailing)** refetch only when changed `liveRoundIds`/`liveTourIds` intersect the tour(s)/round(s) currently rendered in this profile view. Keep per-card eq-id streams as the live mechanism for visible rows.

**After-flow / silent insertion.** New games for the player in a newly-live round appear after the intersect-gated refetch; existing list order preserved, no auto-scroll.

### 4. Countrymen — `lib/screens/countrymen/provider/countrymen_combined_games_provider.dart`

**Current flow.** Date-bucketed: `getDistinctDatesForCountry` (`:334`,`:353`) + `getGamesByCountryAndDate` (`:410`). **No live-set listener at all** — this is net-new work.

**Exact changes.** Add a `liveControlPlaneProvider` listener, **intersection-gated** against the set of `tour_id`/`round_id` currently rendered in the tab, and **debounced (3–5s trailing, coalesced)**. Refetch only the **today bucket** and only when the changed live ids intersect rendered games. A full today-bucket refetch of `getGamesByCountryAndDate` on every settings push (hundreds of games for a popular country on Titled Tuesday) is the chattiness hazard the guard prevents (§R9). Per-card eq-id streams remain the freshness mechanism for visible rows.

### 5. Favorites — `lib/screens/favorites/player_games/provider/favorites_combined_games_provider.dart`

Identical shape to Countrymen: `getDistinctDatesForFavorites` (`:371`,`:390`) + `getGamesByFideIdsAndDate` (`:446`), array column `player_fide_ids`, no live-set listener today. Apply the same intersect-gated, debounced control-plane refetch of the today bucket; keep per-card streams for visible rows.

**Open question for §4/§5/§3:** confirm with the user whether these tabs need live *new-game insertion* at all, or whether visible-card freshness suffices — adding live refetch here is scope beyond the reported event-tab bug.

## Cross-cutting UI

- **Scroll-anchor preservation (event tab).** `ScrollablePositionedList` is index-based; inserting a round/games **above** the viewport shifts every subsequent index, and the controller's offset does not auto-track (the code already fights this via `_anchorTopAfterVisibilityChange` at `games_tour_scroll_provider.dart:224` and `_scrollToRound`'s 10-attempt retry at `games_tour_provider.dart:344`). **Every insert-above mutation MUST be paired with an explicit anchor restore:** capture `_lastVisibleGameId` (already tracked at `games_tour_scroll_provider.dart:59/180`) BEFORE the mutation, then in a `postFrameCallback` re-jump via `_getItemIndexForGameId` (`:236`) to the same game at the same alignment — reuse `_anchorTopAfterVisibilityChange`, do not reinvent. Account for `matchFormatOffset` (`games_list_view.dart:441`) and round/match expansion state in the recompute (they already complicate `_calculateRoundHeaderIndex`). Do not rely on `initialScrollIndex` (first-build only).
- **No-auto-scroll rule.** Gate the anchor restore on `userSelectedRoundProvider` (`games_app_bar_provider.dart:25`) being sticky OR the user not being at the very top. Suppress selection-hijack: new live rounds must NOT steal selection from a sticky pick (`_onLiveRoundsChanged` already respects `hasStickyValid` at `:1289`). Auto-scroll to a new live round only when the user is at top with no sticky selection.
- **Entrance animation.** New round header + cards animate in via `package:motor` (`CupertinoMotion.snappy`) + `flutter_animate` (`fadeIn` + small `slideY`), matching existing card entrance animations. No banners, badges, toasts, or "new!" chrome — silent.
- **No distracting UI.** No layout shift for content the user is reading; insertion happens above the anchor with the anchor held.

## Channel-lifecycle & Scale Considerations

Self-hosted Realtime (`supabase.chessever.com`) has no plan quota but is a single Elixir/WAL process; every published table and every channel = process + WAL filter + fan-out.

- **Channel budget:** ONE per-tour INSERT/UPDATE/DELETE channel per *open* tour detail screen, lifecycle-gated by `shouldStreamProvider`, `keepAlive`-cached so tab switches don't thrash phx_join/phx_leave. No per-tour channels on the other 4 surfaces.
- **Per-card eq-id streams** (`board_game_card_wrapper_widget.dart:34`, `grid_game_card_wrapper_widget.dart:42` → `liveGameUpdateStreamProvider(gameId)` via `live_game_card_provider.dart:143`) are bounded by viewport (~6–12 list rows; more in grid), not 256. A rapid fling can still open/close dozens of eq-id channels. **Mitigation:** add a scroll-velocity/linger debounce before disposing per-card streams, OR migrate the games-tab cards to the existing batch path `subscribeToLiveGameUpdatesBatch` (`game_stream_repository.dart:185`, `.inFilter`) keyed by the visible window, collapsing ~10 channels into 1. The per-card streams become a pure latency optimization; the per-tour channel is the correctness source.
- **Diff discipline everywhere:** `settings` has no `updated_at`; no-op writes still emit WAL. Every consumer diffs (`listEquals`) before expensive work (refetch / `loadTourDetails` / resolver cascade / re-sort / `_scrollToRound`).

## Risks & Mitigations

- **R1 — Control-plane blast radius.** Reviving the *existing* `liveTourIdProvider`/`liveRoundsIdProvider`/`liveGroupBroadcastIdsProvider` streams would, the moment `settings` is published, fire `tour_detail_screen_provider.loadTourDetails()` (`:105`, which recreates `gamesAppBarProvider` per `games_app_bar_provider.dart:32-37`), the unconditional For-You refetch (`for_you_games_provider.dart:168-173`), and the 5-query group-broadcast resolver cascade. **Mitigation:** do NOT blanket-enable. Use the dedicated diff-guarded `liveControlPlaneProvider`; add `listEquals` guards to For-You `:168/:171` *before* flipping the publication; verify `tour_detail_screen_provider`'s `hasNewTours` gate (`:96`) absorbs same-set re-emits (it does) and that a transient empty emit cannot wrongly flip statuses (handled by §R12).
- **R2 — Resolver cascade amplification.** `liveGroupBroadcastIdsProvider` runs a 5-query network cascade (`live_group_broadcast_id_provider.dart:164-219`) on every backing-stream emit. **Mitigation:** keep it on its 1-min `Timer.periodic` (`:137`); do NOT let realtime settings deltas drive `resolve()` directly. If acceleration is wanted, 5s trailing-debounce settings deltas and short-circuit `resolve()` when the `(configuredLiveEntries, liveRoundIds)` *input* tuple is unchanged (today it only de-dups the *output* via `lastResolvedIds` at `:57`).
- **R3 — Channel thrash on fling.** See Scale §. Debounce per-card dispose or migrate to the batch path.
- **R4 — Derived-liveness false flips + battery.** A classical game between moves can exceed 10 min think time; a flat 10-min window would flicker a live round out and back. **Mitigation:** promote-only + time-control-aware threshold; coarse 30–60s tick; early-return on `Equatable`-equal model list so `_sortRounds`/`_scrollToRound` don't run unless a status transitioned.
- **R5 — Removing the poll loses off-screen completions / deletions.** **Mitigation:** the per-tour channel is INSERT+UPDATE+**DELETE**, not INSERT-only. UPDATE keeps off-screen statuses fresh for round aggregation; DELETE removes withdrawals. Optionally drop UPDATEs for games already covered by a live per-card stream, and apply only `status`/`last_move_time` from UPDATEs (not full pgn/fen) to bound volume.
- **R6 — INSERT dedup/precedence.** Pre-created rows are already in memory; a bare INSERT must not clobber a fresher snapshot. **Mitigation:** reuse `_shouldUseIncomingGame`/`_mergeGameSnapshots`; bucket new ids by `round_id`; never blind-prepend.
- **R7 — Scroll jump on insert-above.** **Mitigation:** explicit anchor restore (Cross-cutting UI).
- **R8 — Day-boundary status bug.** Pre-existing latent bug at `games_app_bar_view_model.dart:62`; the clock tick surfaces it more often. **Mitigation:** fix the ongoing-vs-completed classification independently and before relying on the tick.
- **R9 — Array-surface refetch chattiness.** **Mitigation:** intersect-gate + 3–5s trailing debounce + today-bucket-only; optionally a cheap `exists`/count probe before the full bucket refetch.
- **R10 — In-flight standings-rank diff.** Only `games_tour_model.dart` overlaps (it removes `PlayerCard.customPoints`). **Mitigation:** build merge/`copyWith` on the **post-removal** `PlayerCard` shape; do not resurrect `broadcast_custom_scoring.dart` or `customAwareResultLabelForSide`; rebase realtime onto the standings change first.
- **R11 — `shouldStreamProvider` lifecycle.** The new long-lived channel must subscribe/unsubscribe on `shouldStreamProvider` true/false (same gate the poll used at `games_tour_provider.dart:33-42`) so a backgrounded app stops applying deltas.
- **R12 — Reconnect / transient-empty settings emit.** `.stream()` re-emits a snapshot on reconnect; an empty `live_round_ids` would flip every live round to not-live then back. **Mitigation:** in the control plane and `_onLiveRoundsChanged`, treat empty-after-non-empty as "no information" unless corroborated by `status='*'`/recent `last_move_time`; pairs with promote-only liveness.

## Test Plan

**Unit / widget (validated by `flutter analyze`; never `flutter build`/`run`):**
- `SettingsDelta` value-equality + diff suppression (no-op write → no emission).
- Derived-liveness promote-only: backend-live round never demoted; classical 30-min gap not flipped out; empty-after-non-empty not demoted.
- Day-boundary `status()`: round started 23:50 local stays `ongoing`/`live` past midnight.
- Delta merge precedence: bare INSERT does not clobber a fresher cached snapshot; new id buckets to correct round; DELETE removes id.
- Clock-tick early-return: `Equatable`-equal model list ⇒ no `_sortRounds`/`_scrollToRound`.
- For-You `:168/:171` equality guard suppresses no-op bumps.
- Intersection gate on array surfaces: non-intersecting live-id change ⇒ no refetch.
- Anchor restore: `_getItemIndexForGameId` after an above-viewport insert returns the same game; `userSelectedRoundProvider` sticky ⇒ no auto-scroll.
- `getGamesByTourId` returns full set in one query (no loop) — repository test.

**Manual device checks (ask the user):**
- Open Titled Tuesday during R1; when R2 starts, R2 appears as live within the clock-tick interval *without restart*, silently at top, no scroll jump while reading R1.
- Backgrounding app / opening chessboard stops deltas (channel closed); resume re-subscribes.
- Off-screen game finishing updates round counts; withdrawn game disappears.
- Rapid fling does not stutter (channel-count sanity).

## Rollout / PR-staging Order

1. **PR-1 (no behavior change):** add `listEquals` guards to For-You `:168/:171`; verify `tour_detail_screen_provider.hasNewTours` absorbs same-set/empty re-emits. Ships safe even before publication flip.
2. **PR-2:** `liveControlPlaneProvider` + `SettingsDelta` + repository typed stream (still no consumers switched). Add unit tests.
3. **PR-3:** Backend migration (`ALTER PUBLICATION ... ADD TABLE public.settings`) gated behind the measured-cadence pre-flight. Reversible.
4. **PR-4:** Event tab — per-tour `tourGamesRealtimeProvider` (INSERT+UPDATE+DELETE), remove 10s poll, remove 1000-row loop, local clock tick, promote-only liveness, day-boundary fix, anchor-restore on insert. (Rebased onto the standings-rank change.)
5. **PR-5:** Switch event tab + For You to `liveControlPlaneProvider` slices; resolver-cascade debounce/short-circuit.
6. **PR-6 (IN SCOPE — confirmed all-5-surfaces, 2026-05-29):** array-surface intersect-gated debounced refetch (player profile, countrymen, favorites).

## Open Questions

1. ~~Measured external write cadence to `public.settings`~~ — **RESOLVED 2026-05-29:** `upsert_live_job_ids` writes a full payload per data-hub main-loop pass (~tens-of-seconds during live windows), no writer dedup, no `updated_at`. Trivial WAL volume; client `listEquals` diffing is the mitigation. No gate before PR-3.
2. ~~Do player profile / countrymen / favorites need live new-game insertion?~~ — **RESOLVED 2026-05-29:** YES, all 5 surfaces in scope (PR-6 confirmed).
3. Time-control source for the promote threshold: is `time_control` reliably available per tour/round on the client, or must it be inferred (e.g. from `tours.info->>'tc'`)?
4. For per-card scale: debounce per-card eq-id dispose, or migrate the games tab to the existing `subscribeToLiveGameUpdatesBatch` batch path? (Either bounds channel count; batch is the larger refactor.)
5. Should DELETE deltas on the per-tour channel be surfaced as a subtle removal animation or an instantaneous drop? (Default: instantaneous, no chrome.)

Verified file:line anchors used above: `games_app_bar_view_model.dart:48/62/95`; `games_app_bar_provider.dart:25/32-37/50/55/247/646/1245/1262/1289`; `games_tour_provider.dart:8/33-42/48/82/140/154/163`; `games_tour_scroll_provider.dart:59/125/180/224/236`; `settings_repository.dart:21/26`; `live_rounds_id_provider.dart:4`; `live_tour_id_provider.dart:4`; `live_group_broadcast_id_provider.dart:57/137/164-219`; `game_stream_repository.dart:120-203`; `game_repository.dart:268/278-312`; `tour_detail_screen_provider.dart:63/80/96/105`; `for_you_games_provider.dart:144/168/171/176/182`; `games_tour_screen_provider.dart:182`; `games_list_view.dart:441`; `countrymen_combined_games_provider.dart:334/353/410`; `favorites_combined_games_provider.dart:371/390/446`. Backend verified via SQL: `supabase_realtime` publishes only `games`; `settings`/`rounds`/`games` replica identity = `default(PK)`; `settings`/`rounds` SELECT RLS `qual=true` `{public}`; `settings` single row id=1 (7 live rounds/tours/group_broadcasts).