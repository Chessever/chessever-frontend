# Realtime Live-Rounds & New-Games Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a newly-started live round (and new boards / withdrawals) appear on phone across all 5 live-games surfaces without an app restart or pull-to-refresh, by replacing polling + the frozen round-status path with realtime signals.

**Architecture:** Revive `public.settings` as a diff-guarded realtime "live control plane"; drive the open event tab with one per-tour `games` realtime channel (INSERT/UPDATE/DELETE, delta-only) plus a promote-only derived-liveness rule and a local 30-60s clock tick; the array-column surfaces (player profile / countrymen / favorites) react to the control plane with intersection-gated, debounced today-bucket refetches. No polling, no 1000-row pagination loop.

**Tech Stack:** hooks_riverpod, supabase_flutter (Realtime `postgres_changes`), package:motor, flutter_animate, flutter_scrollable_positioned_list, flutter_test. Validation: `flutter analyze` / `flutter test` ONLY — never `flutter build`/`run` (project rule).

Spec: `docs/superpowers/specs/2026-05-28-realtime-live-rounds-design.md` · Trello card #654.

---

## Dependency order

PR-1 (For-You equality guards — safe, no behavior change) → PR-2 (`liveControlPlaneProvider` + `SettingsDelta`; no consumers switched) → PR-3 (backend migration: publish `public.settings`) → **PR-4 (event-tab core: per-tour realtime channel, remove poll + 1000-loop, reactive round status, anchor-preserving insert) — ASSUMES the in-flight standings-`rank` diff is already landed (no `PlayerCard.customPoints`)** → PR-5 (switch event tab + For You to the control plane; resolver-cascade debounce) → PR-6 (array surfaces: player profile, countrymen, favorites).

PR-1 and PR-2 are independent and may land in either order. PR-3 must precede the control-plane consumers doing real work (PR-4/5/6), but the Dart degrades gracefully (one-shot snapshot) if PR-3 is delayed, so PR-2 can merge first safely.

---

### PR-1: Guard For You / Tour-Detail live-id re-emits against no-op refreshes
Goal: stop `bumpForYouEventsRefreshSignal` from firing (and stop tour-detail state from churning) when `liveTourIdProvider` / `liveRoundsIdProvider` re-emit the *same* (or an empty same) set of IDs, so the realtime publication flip in later PRs doesn't trigger a refresh storm.

**Files:**
- Modify: `lib/providers/for_you_games_provider.dart` (lines 168-173 — the two `ref.listen(liveTourIdProvider, …)` / `ref.listen(liveRoundsIdProvider, …)` blocks inside `_setupListeners`)
- Modify: `lib/screens/tour_detail/provider/tour_detail_screen_provider.dart` (lines 88-107 — the `updateStateWithNewLiveTourIds` `hasNewTours` gate; assertion/guard only, see Step 6)
- Create (test): `test/for_you_live_id_refresh_guard_test.dart`
- Test: `test/for_you_live_id_refresh_guard_test.dart`

Numbered steps:

- [ ] **Step 1: Write the FAILING unit test for the For You live-id guard.** Create `test/for_you_live_id_refresh_guard_test.dart`. This test overrides `liveTourIdProvider` and `liveRoundsIdProvider` with controllable `StreamController`s, reads `forYouEventsRefreshProvider` before/after re-emitting an *equal* list, and asserts the signal value is unchanged. Today the listeners bump unconditionally, so the equal-emission case will increment the counter and the test will FAIL.

```dart
import 'dart:async';

import 'package:chessever2/providers/event_pin_refresh_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Pure replica of the equality-guarded listener wiring used by
/// `ForYouNotifier._setupListeners`. We exercise it in isolation so the test
/// does not have to construct the full notifier (which performs network IO).
void wireLiveIdGuards(Ref ref) {
  List<String>? lastTourIds;
  List<String>? lastRoundIds;

  ref.listen<AsyncValue<List<String>>>(liveTourIdProvider, (_, next) {
    final ids = next.valueOrNull;
    if (ids == null) return;
    if (listEquals(lastTourIds, ids)) return;
    lastTourIds = List<String>.from(ids);
    bumpForYouEventsRefreshSignal(ref);
  });

  ref.listen<AsyncValue<List<String>>>(liveRoundsIdProvider, (_, next) {
    final ids = next.valueOrNull;
    if (ids == null) return;
    if (listEquals(lastRoundIds, ids)) return;
    lastRoundIds = List<String>.from(ids);
    bumpForYouEventsRefreshSignal(ref);
  });
}

void main() {
  late StreamController<List<String>> tourController;
  late StreamController<List<String>> roundController;
  late ProviderContainer container;

  setUp(() {
    tourController = StreamController<List<String>>.broadcast();
    roundController = StreamController<List<String>>.broadcast();
    container = ProviderContainer(
      overrides: [
        liveTourIdProvider.overrideWith((ref) => tourController.stream),
        liveRoundsIdProvider.overrideWith((ref) => roundController.stream),
      ],
    );
    // Keep both stream providers alive so listeners stay subscribed.
    container.listen(liveTourIdProvider, (_, __) {});
    container.listen(liveRoundsIdProvider, (_, __) {});
    wireLiveIdGuards(container.read(Provider((ref) => ref)));
  });

  tearDown(() {
    container.dispose();
    tourController.close();
    roundController.close();
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('equal live-tour-id re-emit does NOT bump the refresh signal', () async {
    tourController.add(['t1', 't2']);
    await pump();
    final afterFirst = container.read(forYouEventsRefreshProvider);

    tourController.add(['t1', 't2']);
    await pump();
    final afterSecond = container.read(forYouEventsRefreshProvider);

    expect(afterSecond, afterFirst);
  });

  test('changed live-tour-id emit DOES bump the refresh signal', () async {
    tourController.add(['t1']);
    await pump();
    final afterFirst = container.read(forYouEventsRefreshProvider);

    tourController.add(['t1', 't2']);
    await pump();
    final afterSecond = container.read(forYouEventsRefreshProvider);

    expect(afterSecond, greaterThan(afterFirst));
  });

  test('empty -> empty live-round re-emit does NOT bump', () async {
    roundController.add(const <String>[]);
    await pump();
    final afterFirst = container.read(forYouEventsRefreshProvider);

    roundController.add(const <String>[]);
    await pump();
    final afterSecond = container.read(forYouEventsRefreshProvider);

    expect(afterSecond, afterFirst);
  });
}
```

- [ ] **Step 2: Run the test, expect FAIL.** Command: `flutter test test/for_you_live_id_refresh_guard_test.dart`. Expected: the first test (`equal live-tour-id re-emit does NOT bump`) and the third (`empty -> empty`) FAIL — `afterSecond` is `afterFirst + 1` because `wireLiveIdGuards` does not yet exist in production and the test's local copy is what we are validating. Note: at this step `wireLiveIdGuards` is defined inside the test, so it should actually PASS for the guarded copy. To prove the guard is the load-bearing change, temporarily delete the two `if (listEquals(...)) return;` lines from the test's `wireLiveIdGuards`, run `flutter test test/for_you_live_id_refresh_guard_test.dart` and confirm tests 1 and 3 FAIL, then restore the two lines and confirm all three PASS. This proves the guard logic — which we now port verbatim into the provider in Step 3.

- [ ] **Step 3: Add the equality guards to the production provider.** In `lib/providers/for_you_games_provider.dart`, the `_setupListeners` method currently ends with two unconditional listeners (lines 168-173):

```dart
    ref.listen(liveTourIdProvider, (_, __) {
      bumpForYouEventsRefreshSignal(ref);
    });
    ref.listen(liveRoundsIdProvider, (_, __) {
      bumpForYouEventsRefreshSignal(ref);
    });
```

First add two fields to track the last-seen id sets. Insert them immediately after the existing fields near the top of `ForYouNotifier` (right after `DateTime? _lastRefreshAt;` at line 116):

```dart
  DateTime? _lastRefreshAt;
  List<String>? _lastLiveTourIds;
  List<String>? _lastLiveRoundIds;
```

Then replace the two unconditional listeners (lines 168-173) with equality-guarded ones:

```dart
    ref.listen<AsyncValue<List<String>>>(liveTourIdProvider, (_, next) {
      final ids = next.valueOrNull;
      if (ids == null) return;
      if (listEquals(_lastLiveTourIds, ids)) return;
      _lastLiveTourIds = List<String>.from(ids);
      bumpForYouEventsRefreshSignal(ref);
    });
    ref.listen<AsyncValue<List<String>>>(liveRoundsIdProvider, (_, next) {
      final ids = next.valueOrNull;
      if (ids == null) return;
      if (listEquals(_lastLiveRoundIds, ids)) return;
      _lastLiveRoundIds = List<String>.from(ids);
      bumpForYouEventsRefreshSignal(ref);
    });
```

`listEquals` is already in scope: `lib/providers/for_you_games_provider.dart:42` imports `package:flutter/foundation.dart`. No new import is required.

- [ ] **Step 4: Run analyze on the changed provider, expect PASS.** Command: `flutter analyze --no-pub lib/providers/for_you_games_provider.dart`. Expected: `No issues found!` (or only pre-existing unrelated infos; zero new errors/warnings on the two listener blocks). In practice prefer the dart MCP `analyze_files` tool on the same path; the CLI command above is the canonical written form.

- [ ] **Step 5: Run the guard test against the now-real wiring, expect PASS.** Command: `flutter test test/for_you_live_id_refresh_guard_test.dart`. Expected: all three tests PASS. The test's `wireLiveIdGuards` is a faithful replica of the production listeners added in Step 3 (same `valueOrNull` null-skip, same `listEquals` guard, same `List<String>.from` capture, same `bumpForYouEventsRefreshSignal(ref)` call), so green here verifies the exact logic shipped in the provider.

- [ ] **Step 6: Verify (do NOT change behavior of) the tour-detail `hasNewTours` gate.** Open `lib/screens/tour_detail/provider/tour_detail_screen_provider.dart`. Confirm the existing flow already absorbs same-set AND empty re-emits without flipping state, in two layers:
  1. `setupLiveTourIdListener` (lines 63-76) calls `if (listsAreEqual(_currentLiveTourIds, newLiveTourIds)) return;` *before* doing anything — an identical or empty-vs-empty re-emit returns early and never touches state. `listsAreEqual` (lines 80-86) is order-sensitive length+element equality, which is correct here because `liveTourIdProvider` emits a stable-ordered list.
  2. The `hasNewTours` gate inside `updateStateWithNewLiveTourIds` (lines 96-98):
```dart
      final currentTourIds = currentState.tours.map((t) => t.tour.id).toSet();
      final hasNewTours = newLiveTourIds.any(
        (id) => !currentTourIds.contains(id),
      );
```
     For an empty `newLiveTourIds`, `.any(...)` over an empty iterable returns `false`, so `hasNewTours` is `false` and `loadTourDetails()` is NOT called — confirming the empty re-emit does not trigger a refetch. For a same-set re-emit, the outer `listsAreEqual` guard already returned before reaching this code.

  No production edit is required in this file for PR-1. Add one regression-locking assertion in the test file from Step 1 so a future change to either guard breaks CI. Append this to `test/for_you_live_id_refresh_guard_test.dart` inside `main()`:

```dart
  test('hasNewTours gate logic: empty live-tour-ids yields no new tours', () {
    final currentTourIds = {'t1', 't2'};
    const newLiveTourIds = <String>[];
    final hasNewTours = newLiveTourIds.any(
      (id) => !currentTourIds.contains(id),
    );
    expect(hasNewTours, isFalse);
  });

  test('hasNewTours gate logic: same-set live-tour-ids yields no new tours', () {
    final currentTourIds = {'t1', 't2'};
    const newLiveTourIds = ['t1', 't2'];
    final hasNewTours = newLiveTourIds.any(
      (id) => !currentTourIds.contains(id),
    );
    expect(hasNewTours, isFalse);
  });

  test('hasNewTours gate logic: a genuinely new id flags new tours', () {
    final currentTourIds = {'t1'};
    const newLiveTourIds = ['t1', 't2'];
    final hasNewTours = newLiveTourIds.any(
      (id) => !currentTourIds.contains(id),
    );
    expect(hasNewTours, isTrue);
  });
```
These three tests pin the exact boolean semantics of the `:96` gate so a later realtime PR cannot silently regress empty/same-set absorption.

- [ ] **Step 7: Run the full new test file, expect PASS.** Command: `flutter test test/for_you_live_id_refresh_guard_test.dart`. Expected: all six tests PASS (three live-id guard tests + three `hasNewTours` gate-logic tests).

- [ ] **Step 8: Analyze the touched paths together, expect PASS.** Command: `flutter analyze --no-pub lib/providers/for_you_games_provider.dart lib/screens/tour_detail/provider/tour_detail_screen_provider.dart test/for_you_live_id_refresh_guard_test.dart`. Expected: no new issues. Manual device-check note: this PR is behavior-neutral by design (it only suppresses redundant refresh bumps that were previously no-ops in effect), so no on-device verification is required; if the user wants confirmation, ask them to open the For You tab while a live event is running and confirm cards still flip to "LIVE" and game lists still refresh when a real status change arrives.

- [ ] **Step 9: Commit.** Command:
```bash
git add lib/providers/for_you_games_provider.dart test/for_you_live_id_refresh_guard_test.dart && git commit -m "$(cat <<'EOF'
Guard For You live-id listeners against no-op refresh bumps

liveTourIdProvider / liveRoundsIdProvider previously bumped
forYouEventsRefreshSignal on every emit, including identical and
empty-vs-empty re-emits. Add listEquals equality guards so only a
real change to the live-id set triggers a For You snapshot refresh,
and lock the tour-detail hasNewTours empty/same-set absorption with
regression tests. No behavior change; ships safe before the realtime
publication flip.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

Notes for the implementer: `bumpForYouEventsRefreshSignal` is defined in `lib/providers/event_pin_refresh_provider.dart:21` and takes a single `Ref` argument — do not pass an event id. `forYouEventsRefreshProvider` is the `StateProvider<int>` (same file, line 19) the test reads to assert the bump count. The in-flight standings-rank diff (PlayerCard/Player `customPoints` removal, `TournamentPlayer.rank` add) does not touch either file in this PR, so there is no merge interaction here.

---

### PR-2: `SettingsDelta` value type + diff-guarded `liveControlPlaneProvider` (no consumers switched)

**Goal:** Add a typed `subscribeToSettingsDelta()` stream to `SettingsRepository` and a dedicated, diff-guarded `liveControlPlaneProvider` that emits a `SettingsDelta` only when one of the three live-id lists actually changes, suppressing no-op WAL writes and the reconnect/transient-empty case. Pure plumbing — nothing consumes it yet.

**Files:**
- Create: `lib/repository/supabase/settings/live_control_plane_provider.dart`
- Modify: `lib/repository/supabase/settings/settings_repository.dart` (add `subscribeToSettingsDelta()` after the existing `subscribeToSettings()` at lines 21–24; add `import 'package:flutter/foundation.dart';` for nothing — equality lives in the new file)
- Test: `test/live_control_plane_provider_test.dart`

Notes for the implementer:
- `SettingsDelta` value equality uses `listEquals` from `package:flutter/foundation.dart` (same source the rest of the codebase imports it from).
- The provider must be testable without a live Supabase socket. We achieve that by sourcing its raw stream from a new repository method (`subscribeToSettingsDelta`) that a fake `SettingsRepository` can override via `noSuchMethod`, exactly like `test/live_group_broadcast_id_provider_test.dart` does. The diff/guard logic lives in the provider (not the repository) so it is unit-testable against a controllable `StreamController`.
- The existing `Settings` model (`lib/repository/supabase/settings/settings.dart`) already exposes `liveRoundIds` / `liveTourIds` / `liveGroupBroadcastIds`, so the repository stream maps `Settings` → `SettingsDelta`.

---

- [ ] **Step 1: Write the FAILING test for `SettingsDelta` value equality.**

Create `test/live_control_plane_provider_test.dart` with the first test only:

```dart
import 'dart:async';

import 'package:chessever2/repository/supabase/settings/live_control_plane_provider.dart';
import 'package:chessever2/repository/supabase/settings/settings.dart';
import 'package:chessever2/repository/supabase/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A SettingsRepository whose delta stream we drive by hand.
class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this._stream);

  final Stream<SettingsDelta> _stream;

  @override
  Stream<SettingsDelta> subscribeToSettingsDelta() => _stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('SettingsDelta', () {
    test('value equality holds when all three lists are element-equal', () {
      const a = SettingsDelta(
        liveRoundIds: ['r1', 'r2'],
        liveTourIds: ['t1'],
        liveGroupBroadcastIds: ['g1'],
      );
      const b = SettingsDelta(
        liveRoundIds: ['r1', 'r2'],
        liveTourIds: ['t1'],
        liveGroupBroadcastIds: ['g1'],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('value equality fails when any list differs', () {
      const base = SettingsDelta(
        liveRoundIds: ['r1'],
        liveTourIds: ['t1'],
        liveGroupBroadcastIds: ['g1'],
      );
      const diffRound = SettingsDelta(
        liveRoundIds: ['r2'],
        liveTourIds: ['t1'],
        liveGroupBroadcastIds: ['g1'],
      );
      const diffTour = SettingsDelta(
        liveRoundIds: ['r1'],
        liveTourIds: ['t2'],
        liveGroupBroadcastIds: ['g1'],
      );
      const diffGb = SettingsDelta(
        liveRoundIds: ['r1'],
        liveTourIds: ['t1'],
        liveGroupBroadcastIds: ['g2'],
      );
      expect(base, isNot(equals(diffRound)));
      expect(base, isNot(equals(diffTour)));
      expect(base, isNot(equals(diffGb)));
    });

    test('order matters within a list (no set semantics)', () {
      const a = SettingsDelta(
        liveRoundIds: ['r1', 'r2'],
        liveTourIds: [],
        liveGroupBroadcastIds: [],
      );
      const b = SettingsDelta(
        liveRoundIds: ['r2', 'r1'],
        liveTourIds: [],
        liveGroupBroadcastIds: [],
      );
      expect(a, isNot(equals(b)));
    });
  });
}
```

- [ ] **Step 2: Run the test, expect FAIL (compile error — type does not exist yet).**

Command: `flutter test test/live_control_plane_provider_test.dart`

Expected: FAIL — `Error: Couldn't find constructor 'SettingsDelta'` / `Type 'SettingsDelta' not found` and `The method 'subscribeToSettingsDelta' isn't defined`. (Compile failure counts as red.)

- [ ] **Step 3: Create the file with `SettingsDelta` only (value equality), minimal.**

Create `lib/repository/supabase/settings/live_control_plane_provider.dart`:

```dart
import 'package:flutter/foundation.dart';

/// Immutable snapshot of the three backend-owned live-id lists from
/// `public.settings` (single global row id=1). Carries value equality via
/// [listEquals] on all three lists so the control-plane provider can suppress
/// no-op WAL re-writes (`settings` has no `updated_at`, so identical-value
/// upserts still emit WAL UPDATEs).
@immutable
class SettingsDelta {
  const SettingsDelta({
    required this.liveRoundIds,
    required this.liveTourIds,
    required this.liveGroupBroadcastIds,
  });

  final List<String> liveRoundIds;
  final List<String> liveTourIds;
  final List<String> liveGroupBroadcastIds;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SettingsDelta &&
        listEquals(other.liveRoundIds, liveRoundIds) &&
        listEquals(other.liveTourIds, liveTourIds) &&
        listEquals(other.liveGroupBroadcastIds, liveGroupBroadcastIds);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(liveRoundIds),
        Object.hashAll(liveTourIds),
        Object.hashAll(liveGroupBroadcastIds),
      );

  @override
  String toString() =>
      'SettingsDelta(rounds: $liveRoundIds, tours: $liveTourIds, '
      'groupBroadcasts: $liveGroupBroadcastIds)';
}
```

- [ ] **Step 4: Add the `subscribeToSettingsDelta()` method to `SettingsRepository`.**

In `lib/repository/supabase/settings/settings_repository.dart`, add the import at the top (after line 3):

```dart
import 'package:chessever2/repository/supabase/settings/live_control_plane_provider.dart';
```

Then insert the new method immediately after `subscribeToSettings()` (after line 24, before `subscribeToLiveRoundIds()` at line 26):

```dart
  /// Typed single-row stream of [SettingsDelta] for the live control plane.
  /// Mirrors [subscribeToSettings] but projects the backend-owned live-id
  /// lists into a value-equatable delta. The diff/no-op suppression and the
  /// reconnect/transient-empty guard live in `liveControlPlaneProvider`, not
  /// here — this stream is a faithful 1:1 mapping of each WAL snapshot.
  Stream<SettingsDelta> subscribeToSettingsDelta() => supabase
      .from('settings')
      .stream(primaryKey: ['id'])
      .map((data) {
        if (data.isEmpty) {
          return const SettingsDelta(
            liveRoundIds: <String>[],
            liveTourIds: <String>[],
            liveGroupBroadcastIds: <String>[],
          );
        }
        final row = data.first;
        return SettingsDelta(
          liveRoundIds: List<String>.from(row['live_round_ids'] ?? const []),
          liveTourIds: List<String>.from(row['live_tour_ids'] ?? const []),
          liveGroupBroadcastIds:
              List<String>.from(row['live_group_broadcast_ids'] ?? const []),
        );
      });
```

- [ ] **Step 5: Run the equality tests, expect PASS.**

Command: `flutter test test/live_control_plane_provider_test.dart`

Expected: PASS — all three `SettingsDelta` tests green (`+3`). The provider does not exist yet, but no test references it.

- [ ] **Step 6: Commit the value type + repository stream.**

```
git add lib/repository/supabase/settings/live_control_plane_provider.dart lib/repository/supabase/settings/settings_repository.dart test/live_control_plane_provider_test.dart
git commit -m "$(cat <<'EOF'
PR-2 step 1: SettingsDelta value type + repository delta stream

Add SettingsDelta (listEquals value equality on all three live-id lists)
and SettingsRepository.subscribeToSettingsDelta(), mirroring
subscribeToSettings. No diff/guard logic yet; no consumers.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 7: Write the FAILING test for no-op suppression in `liveControlPlaneProvider`.**

Append a new group to `test/live_control_plane_provider_test.dart` (inside `main()`, after the `SettingsDelta` group). This drives the repository's delta stream by hand through a `StreamController` and asserts the provider collapses identical-value emissions:

```dart
  group('liveControlPlaneProvider', () {
    test('suppresses no-op emissions (identical SettingsDelta not re-emitted)',
        () async {
      final source = StreamController<SettingsDelta>();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _FakeSettingsRepository(source.stream),
          ),
        ],
      );
      addTearDown(container.dispose);

      final emitted = <SettingsDelta>[];
      final sub = container.listen<AsyncValue<SettingsDelta>>(
        liveControlPlaneProvider,
        (_, next) {
          final value = next.valueOrNull;
          if (value != null) emitted.add(value);
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // Same logical value pushed three times (back-end re-writes the row with
      // no change because settings has no updated_at).
      source.add(const SettingsDelta(
        liveRoundIds: ['r1'],
        liveTourIds: ['t1'],
        liveGroupBroadcastIds: ['g1'],
      ));
      source.add(const SettingsDelta(
        liveRoundIds: ['r1'],
        liveTourIds: ['t1'],
        liveGroupBroadcastIds: ['g1'],
      ));
      source.add(const SettingsDelta(
        liveRoundIds: ['r1', 'r2'],
        liveTourIds: ['t1'],
        liveGroupBroadcastIds: ['g1'],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(2));
      expect(emitted.first.liveRoundIds, ['r1']);
      expect(emitted.last.liveRoundIds, ['r1', 'r2']);
    });
  });
```

- [ ] **Step 8: Run the no-op test, expect FAIL.**

Command: `flutter test test/live_control_plane_provider_test.dart`

Expected: FAIL — `Error: Undefined name 'liveControlPlaneProvider'` and `Undefined name 'settingsRepositoryProvider'` (the latter is already exported from `settings_repository.dart`, but `liveControlPlaneProvider` does not exist yet). Compile failure = red.

- [ ] **Step 9: Implement `liveControlPlaneProvider` with the no-op diff guard.**

Append to `lib/repository/supabase/settings/live_control_plane_provider.dart`. First add the imports at the top of the file (above the existing `package:flutter/foundation.dart` import):

```dart
import 'dart:async';

import 'package:chessever2/repository/supabase/settings/settings_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
```

Then add the provider at the bottom of the file:

```dart
/// Dedicated, diff-guarded subscription to `public.settings` (the single
/// backend-owned global row id=1). Emits a [SettingsDelta] ONLY when one of the
/// three live-id lists actually changes.
///
/// Two guards:
///  1. No-op suppression — `settings` has no `updated_at`, so identical-value
///     upserts still arrive on the wire; we diff against the last emitted delta
///     ([SettingsDelta] value equality via listEquals) and drop no-ops so no
///     downstream consumer re-works.
///  2. Reconnect/transient-empty guard — `.stream()` re-emits a snapshot on
///     reconnect; an all-empty payload arriving while the previous delta was
///     non-empty is treated as "no information", NOT as "nothing is live", and
///     is suppressed (it must never flip every live round to not-live). The
///     first emission is always forwarded, even if empty (genuine cold start).
///
/// This intentionally does NOT reuse liveRoundsIdProvider / liveTourIdProvider /
/// liveGroupBroadcastIdsProvider — those drive expensive consumers.
final liveControlPlaneProvider = StreamProvider<SettingsDelta>((ref) {
  final repository = ref.watch(settingsRepositoryProvider);
  final controller = StreamController<SettingsDelta>();

  SettingsDelta? last;

  bool isEmptyDelta(SettingsDelta d) =>
      d.liveRoundIds.isEmpty &&
      d.liveTourIds.isEmpty &&
      d.liveGroupBroadcastIds.isEmpty;

  final sub = repository.subscribeToSettingsDelta().listen(
    (incoming) {
      if (controller.isClosed) return;

      // Guard 1: no-op suppression.
      if (last != null && incoming == last) return;

      // Guard 2: reconnect/transient-empty. An all-empty payload after a
      // non-empty one is "no info", not "nothing live" — suppress it.
      if (last != null && !isEmptyDelta(last!) && isEmptyDelta(incoming)) {
        return;
      }

      last = incoming;
      controller.add(incoming);
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!controller.isClosed) controller.addError(error, stackTrace);
    },
  );

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});
```

Note `settingsRepositoryProvider` is already declared in `settings_repository.dart` (line 7) and is in scope via the import added above; do not redeclare it.

- [ ] **Step 10: Run the no-op test, expect PASS.**

Command: `flutter test test/live_control_plane_provider_test.dart`

Expected: PASS — `+4` (three `SettingsDelta` tests plus the no-op suppression test).

- [ ] **Step 11: Write the FAILING test for the reconnect/transient-empty guard.**

Append a second test inside the `liveControlPlaneProvider` group:

```dart
    test('empty-after-non-empty is suppressed (reconnect snapshot is "no info")',
        () async {
      final source = StreamController<SettingsDelta>();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _FakeSettingsRepository(source.stream),
          ),
        ],
      );
      addTearDown(container.dispose);

      final emitted = <SettingsDelta>[];
      final sub = container.listen<AsyncValue<SettingsDelta>>(
        liveControlPlaneProvider,
        (_, next) {
          final value = next.valueOrNull;
          if (value != null) emitted.add(value);
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // Live set established.
      source.add(const SettingsDelta(
        liveRoundIds: ['r1', 'r2'],
        liveTourIds: ['t1'],
        liveGroupBroadcastIds: ['g1'],
      ));
      // Reconnect delivers an all-empty snapshot — must be ignored as "no info".
      source.add(const SettingsDelta(
        liveRoundIds: [],
        liveTourIds: [],
        liveGroupBroadcastIds: [],
      ));
      // Real follow-up after corroboration is forwarded normally.
      source.add(const SettingsDelta(
        liveRoundIds: ['r1', 'r2', 'r3'],
        liveTourIds: ['t1'],
        liveGroupBroadcastIds: ['g1'],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(2));
      expect(emitted.first.liveRoundIds, ['r1', 'r2']);
      expect(emitted.last.liveRoundIds, ['r1', 'r2', 'r3']);
    });

    test('first emission is forwarded even when empty (genuine cold start)',
        () async {
      final source = StreamController<SettingsDelta>();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _FakeSettingsRepository(source.stream),
          ),
        ],
      );
      addTearDown(container.dispose);

      final emitted = <SettingsDelta>[];
      final sub = container.listen<AsyncValue<SettingsDelta>>(
        liveControlPlaneProvider,
        (_, next) {
          final value = next.valueOrNull;
          if (value != null) emitted.add(value);
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      source.add(const SettingsDelta(
        liveRoundIds: [],
        liveTourIds: [],
        liveGroupBroadcastIds: [],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1));
      expect(emitted.first.liveRoundIds, isEmpty);
    });
```

- [ ] **Step 12: Run the guard tests, expect PASS.**

Command: `flutter test test/live_control_plane_provider_test.dart`

Expected: PASS — `+6` total. (The guard implementation from Step 9 already covers both cases: the `last != null` condition lets the first emission through even when empty; the `!isEmptyDelta(last!) && isEmptyDelta(incoming)` condition suppresses the reconnect empty.)

- [ ] **Step 13: Analyze the touched files.**

Command: `flutter analyze --no-pub lib/repository/supabase/settings/live_control_plane_provider.dart lib/repository/supabase/settings/settings_repository.dart test/live_control_plane_provider_test.dart`

Expected: `No issues found!` (In practice prefer the dart MCP `analyze_files` on the same three paths.) If `dart:async` is flagged unused in the provider file, it is used by `StreamController`/`Timer`-free code here — `StreamController` lives in `dart:async`, so the import is required; keep it.

- [ ] **Step 14: Commit the provider + guard tests.**

```
git add lib/repository/supabase/settings/live_control_plane_provider.dart test/live_control_plane_provider_test.dart
git commit -m "$(cat <<'EOF'
PR-2 step 2: liveControlPlaneProvider with no-op + transient-empty guards

Dedicated diff-guarded settings subscription emitting SettingsDelta only on
real change. Suppresses identical-value WAL re-writes (no updated_at) and
treats empty-after-non-empty reconnect snapshots as "no info" (never flips
live rounds to not-live). First emission always forwarded. No consumers yet.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

**Manual device check:** None required for PR-2 — the provider has no consumers and the backend publication flip is PR-3. Correctness is fully covered by the six unit tests above (`flutter test test/live_control_plane_provider_test.dart` ⇒ `+6`).

**Carry-forward note for PR-4/PR-5:** `liveControlPlaneProvider` is a top-level `StreamProvider<SettingsDelta>` (not `autoDispose`, matching the long-lived control-plane role); consumers in later PRs listen via `liveControlPlaneProvider.select((d) => d.liveRoundIds)` etc. The repository stream `subscribeToSettingsDelta()` is the only place that maps raw `settings` rows; all diff/guard logic stays in the provider so it remains the single suppression point.

---

### PR-3: Backend Supabase migration — publish `public.settings` to realtime
Goal: add `public.settings` to the `supabase_realtime` publication so the dead `.stream()` on `settings` starts pushing WAL UPDATE deltas, which is the precondition that makes `subscribeToLiveRoundIds()` (and PR-2's `liveControlPlaneProvider`) actually emit on live-round changes. This PR contains **no Dart code**; its "test" is a SQL verification query plus a manual device check.

**Files:**
- Create (executed at run-time via the supabase MCP `apply_migration` tool — no migration file is written to this repo; the self-hosted project tracks it in `supabase_migrations.schema_migrations`): migration name `add_settings_to_realtime_publication`
- Modify: none
- Test: none (Dart). Verification is the SQL `SELECT` query in Step 3 plus the manual device check in Step 6.

Prerequisites (already verified by the spec — do NOT re-run these as gates, just be aware):
- `public.settings` replica identity is `default(PK)` — sufficient for UPDATE deltas because the PK (`id`) is in every WAL row. No `REPLICA IDENTITY FULL` needed.
- `public.settings` has a `SELECT` RLS policy with `qual=true` for `{public}`, which includes the anon role the realtime client connects as — so the published deltas are visible to the app without auth changes.
- Only `public.games` is currently in `supabase_realtime`; after this PR both `games` and `settings` are published.
- Write cadence is fine: `upsert_live_job_ids()` rewrites the single `settings` row (id=1) every tens-of-seconds during live windows with no writer-side dedup and no `updated_at`, so identical-value re-writes still emit WAL UPDATEs. WAL volume is one tiny single-row event — no storm risk. The client-side `listEquals` diff in PR-2's `liveControlPlaneProvider` is what suppresses no-op downstream work; that guard is a PR-2 concern, not a migration gate.

Steps:

- [ ] **Step 1: Confirm the pre-migration publication state (baseline).**
  Run, via the supabase MCP `execute_sql` tool against project `supabase_chessever_main`, the read-only query:
  ```sql
  SELECT tablename FROM pg_publication_tables
  WHERE pubname = 'supabase_realtime' ORDER BY tablename;
  ```
  Expected result BEFORE the migration: exactly one row, `games`. (If `settings` is already present, the migration is a no-op — see Step 4 idempotency note; record this and skip Step 2's apply but still run Step 3's verification.)

- [ ] **Step 2: Apply the migration.**
  Call the supabase MCP `apply_migration` tool against project `supabase_chessever_main` with:
  - `name`: `add_settings_to_realtime_publication`
  - `query`:
  ```sql
  -- Up: make the live control-plane row push WAL deltas to subscribed clients.
  ALTER PUBLICATION supabase_realtime ADD TABLE public.settings;
  ```
  Expected: the tool returns success with no rows. `apply_migration` runs the statement and records the migration name in `supabase_migrations.schema_migrations` on the remote project.

- [ ] **Step 3: Verify the table is now published (this is the PR's automated "test").**
  Run, via the supabase MCP `execute_sql` tool against project `supabase_chessever_main`:
  ```sql
  -- Confirm settings is now published (expect rows for both 'games' and 'settings').
  SELECT tablename FROM pg_publication_tables
  WHERE pubname = 'supabase_realtime' ORDER BY tablename;
  ```
  Expected result AFTER the migration: exactly two rows in this order — `games`, then `settings`. If `settings` is missing, the migration did not take; do not proceed to the device check.

- [ ] **Step 4: Idempotency note (handle already-present).**
  `ALTER PUBLICATION ... ADD TABLE` is NOT idempotent: re-running it when `public.settings` is already a member raises `ERROR: relation "settings" is already member of publication "supabase_realtime"`. This is harmless (the desired end-state already holds) and must be treated as success, not failure. If you need a re-runnable form (e.g. applying across environments where state may differ), guard it:
  ```sql
  -- Idempotent variant: add settings to the publication only if not already a member.
  DO $$
  BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'settings'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.settings;
    END IF;
  END $$;
  ```
  Either form is acceptable for this single-environment apply; the plain `ALTER` in Step 2 is preferred for the recorded migration because Step 1 already established the baseline. The DO-block is the fallback if Step 1 showed `settings` already present.

- [ ] **Step 5: Record the rollback (do NOT run unless reverting).**
  The migration is additive and fully reversible. To revert, run via the supabase MCP `execute_sql` (or a new `apply_migration` named `drop_settings_from_realtime_publication`):
  ```sql
  -- Down (rollback): clients gracefully degrade to one-snapshot-at-subscribe behavior.
  ALTER PUBLICATION supabase_realtime DROP TABLE public.settings;
  ```
  After rollback, `subscribeToSettings` / `subscribeToLiveRoundIds` revert to delivering exactly one snapshot at subscribe time then going silent — the pre-PR behavior. No app crash, no schema damage: the only observable effect is that live-round status stops updating without a restart again. Re-verify with the Step 3 query (expected: only `games` remains).

- [ ] **Step 6: `public.rounds` is intentionally NOT added — explicit non-action.**
  Do NOT add `public.rounds` to the publication in this PR (or any PR in this plan). The fix (control plane + derived liveness + games-table deltas) does not require round-level realtime: `getRoundsByTourId` is a one-shot fetch inside `_GamesAppBarNotifier._load()`. There is no concrete round-delta consumer, and publishing `rounds` adds speculative WAL fan-out on the single-process self-hosted Realtime instance. Leave `rounds` unpublished; defer until a real consumer exists. (For the record: `public.rounds` already satisfies the publish preconditions — replica identity `default(PK)`, SELECT RLS `qual=true` for `{public}` — so adding it later is a one-line additive migration if ever justified.)

- [ ] **Step 7: Manual device check (the runtime "test" — ask the user; do NOT run `flutter build`/`flutter run`).**
  Because this PR ships no Dart code, there is nothing for `flutter analyze` to check and no `flutter test` to run. The behavioral validation is on-device, exercising that `subscribeToLiveRoundIds()` now emits on a live-round change. Ask the user to verify against a tour that has a not-yet-started round about to go live (e.g. Titled Tuesday during an early round, with a later round about to start). Confirm the wire is now live by either:
  - **App-side:** open the event Games tab during round R1 and, when the backend brings round R2 into `live_round_ids` (or use the SQL nudge below), confirm the `settings` stream now pushes a second emission rather than staying silent — observable via existing log/debug output on the `liveRoundsIdProvider` / `liveSettingsProvider` path (PR-2's `liveControlPlaneProvider` is not yet wired into consumers, so the visible behavior here is just that a fresh emission arrives; full UI promotion of R2 lands in PR-4).
  - **Controlled SQL nudge (optional, to force an emission without waiting for the data hub):** with the app subscribed, run via the supabase MCP `execute_sql` against `supabase_chessever_main` a no-schema touch of the single row, e.g.
    ```sql
    -- Force a WAL UPDATE on settings (id=1) to confirm the stream wakes the client.
    UPDATE public.settings SET live_round_ids = live_round_ids WHERE id = 1;
    ```
    Even though the value is unchanged (no `updated_at`, no writer dedup), this emits a WAL UPDATE; the client `.stream()` should receive a new event (the PR-2 `listEquals` diff would suppress downstream work for a value-identical write, but the raw emission arriving at all is the proof the publication flip worked). Pre-PR, this `UPDATE` produces no client emission at all.
  Expected pass: the subscribed client receives a fresh stream emission on the live-round change / SQL nudge. Pre-PR there was exactly one emission at subscribe time and then silence. This validates the precondition for PR-4/PR-5 and is the sole verification this PR can perform.

No commit step in this PR: the change lives entirely in the remote Postgres publication and is recorded in the project's `supabase_migrations.schema_migrations` by `apply_migration` (Step 2). There is no repo file to `git add`/`git commit`. If your team mirrors applied migrations into the backend monorepo (`/Users/berkay/projects/chessever_data_hub_monorepo`) for auditability, add the Step 2 `ALTER PUBLICATION` statement there under that repo's migration directory in a separate commit owned by the backend repo, not this Flutter repo.

---

### PR-4: Event Games tab — per-tour realtime channel, poll/loop removal, reactive round status, anchor-preserving inserts

Goal: replace the 10s poll and the 1000-row pagination loop with a single lifecycle-gated `tourGamesRealtimeProvider(tourId)` channel that applies INSERT/UPDATE/DELETE deltas through the existing freshness ladder, make round status reactive (local clock tick + control-plane intersection guard + day-boundary/time-control-aware promote-only liveness), and preserve scroll position on insert-above. Rebased onto the landed standings-rank diff (no `customPoints`).

**Files:**
- Modify: `lib/repository/supabase/game/game_repository.dart` (lines 107–115 helper + 268–318 `getGamesByTourId`) — collapse the loop to one bounded query; drop `_tourGamesFetchPageSize`/`shouldFetchAnotherTourGamesPage`.
- Modify: `lib/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart` (lines 48–72 `status()`) — day-boundary fix + time-control-aware promote-only derived liveness.
- Create: `lib/repository/supabase/game/tour_games_realtime_provider.dart` — `GameDelta` + `tourGamesRealtimeProvider`.
- Modify: `lib/screens/tour_detail/games_tour/providers/games_tour_provider.dart` (full file) — remove poll, add delta listener.
- Modify: `lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart` (constructor seed 50–60, control-plane listen replacing 55–60, add clock tick, promote-only `_onLiveRoundsChanged` 1262–1337).
- Modify: `lib/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart` (add anchor-on-insert API near 224–267 + at-top/sticky gate).
- Test: `test/game_repository_tour_games_pagination_test.dart` (replace), `test/games_app_bar_status_test.dart` (new), `test/tour_games_delta_merge_test.dart` (new), `test/games_app_bar_clock_tick_test.dart` (new).

Assumes PR-2 has landed `liveControlPlaneProvider` (`lib/repository/supabase/settings/live_control_plane_provider.dart`) emitting `SettingsDelta{liveRoundIds, liveTourIds, liveGroupBroadcastIds}`.

---

- [ ] **Step 1: Replace the obsolete pagination test with a single-query expectation (FAILING).**
  The old test asserts a `shouldFetchAnotherTourGamesPage` helper we are deleting. Replace its contents with a test of a new pure helper `tourGamesQueryRange` that encodes the single-bounded-query semantics (null limit ⇒ no range; positive limit ⇒ `[offset, offset+limit-1]`).
  Overwrite `test/game_repository_tour_games_pagination_test.dart`:

  ```dart
  import 'package:chessever2/repository/supabase/game/game_repository.dart';
  import 'package:flutter_test/flutter_test.dart';

  void main() {
    group('tourGamesQueryRange', () {
      test('returns null when no limit is requested (single unbounded select)', () {
        expect(tourGamesQueryRange(limit: null, offset: 0), isNull);
      });

      test('returns an inclusive [from, to] range when a limit is given', () {
        expect(tourGamesQueryRange(limit: 50, offset: 0), const (0, 49));
        expect(tourGamesQueryRange(limit: 50, offset: 100), const (100, 149));
      });

      test('returns null for a non-positive limit', () {
        expect(tourGamesQueryRange(limit: 0, offset: 0), isNull);
        expect(tourGamesQueryRange(limit: -5, offset: 0), isNull);
      });
    });
  }
  ```

- [ ] **Step 2: Run the test, expect FAIL (helper does not exist yet).**
  ```
  flutter test test/game_repository_tour_games_pagination_test.dart
  ```
  Expected: compile error / `tourGamesQueryRange isn't defined` — FAIL.

- [ ] **Step 3: Add the pure helper and remove the loop helpers in `game_repository.dart`.**
  Delete lines 107–115 (`_tourGamesFetchPageSize` const and the `shouldFetchAnotherTourGamesPage` function) and replace them with:

  ```dart
  /// Inclusive Supabase `.range(from, to)` bounds for a bounded tour-games
  /// fetch. Returns `null` when the whole tour should be fetched in one
  /// unbounded `.select()` (the default for the event Games tab).
  @visibleForTesting
  (int, int)? tourGamesQueryRange({required int? limit, int offset = 0}) {
    if (limit == null || limit <= 0) return null;
    return (offset, offset + limit - 1);
  }
  ```

- [ ] **Step 4: Run the test, expect PASS.**
  ```
  flutter test test/game_repository_tour_games_pagination_test.dart
  ```
  Expected: all 3 tests PASS.

- [ ] **Step 5: Rewrite `getGamesByTourId` as a single bounded query.**
  Replace the body of `getGamesByTourId` (lines 268–318) with:

  ```dart
  // Fetch games by tour ID — single bounded query (no pagination loop).
  Future<List<Games>> getGamesByTourId(
    String tourId, {
    int? limit,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      final base = supabase
          .from('games')
          .select(_gameListSelectColumns)
          .eq('tour_id', tourId)
          .order('id', ascending: true);

      final range = tourGamesQueryRange(limit: limit, offset: offset);
      final response =
          range == null
              ? await base
              : await base.range(range.$1, range.$2);

      final jsonList =
          (response as List).map((item) => json.encode(item)).toList();
      final games = await compute(_decodeGamesInIsolate, jsonList);
      return games;
    });
  }
  ```

- [ ] **Step 6: Analyze the repository file.**
  ```
  flutter analyze --no-pub lib/repository/supabase/game/game_repository.dart test/game_repository_tour_games_pagination_test.dart
  ```
  Expected: no errors (the only previous referents of the deleted helper were the loop and that test).

- [ ] **Step 7: Commit the repository change.**
  ```
  git add lib/repository/supabase/game/game_repository.dart test/game_repository_tour_games_pagination_test.dart
  git commit -m "PR-4: collapse getGamesByTourId 1000-row loop to a single bounded query

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

- [ ] **Step 8: Write the day-boundary + promote-only `status()` test (FAILING).**
  Create `test/games_app_bar_status_test.dart`. These pin the §R8/§R4/§R12 contracts: a 23:50-start round stays `ongoing` past midnight; backend-live always wins (promote); a recent `last_move_time` promotes to `ongoing` even on a prior calendar day; a stale classical gap does NOT demote a backend-live round; a flat-aged `last_move_time` alone (no backend-live, no recency) does not promote.

  ```dart
  import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
  import 'package:flutter_test/flutter_test.dart';

  void main() {
    group('GamesAppBarModel.status — day boundary & promote-only liveness', () {
      test('round started 23:50 yesterday stays ongoing just after midnight', () {
        final now = DateTime(2026, 5, 29, 0, 5); // 00:05 local
        final startedYesterday = DateTime(2026, 5, 28, 23, 50);
        expect(
          GamesAppBarModel.status(
            startsAt: startedYesterday,
            currentId: 'r1',
            liveRound: const [],
            now: now,
            lastMoveTime: DateTime(2026, 5, 29, 0, 4), // a move 1 min ago
            timeControl: 'standard',
          ),
          RoundStatus.ongoing,
        );
      });

      test('backend live_round_ids always promotes to live (never demoted)', () {
        final now = DateTime(2026, 5, 29, 12, 0);
        expect(
          GamesAppBarModel.status(
            startsAt: DateTime(2026, 5, 25, 9, 0), // 4 days ago
            currentId: 'r2',
            liveRound: const ['r2'],
            now: now,
            lastMoveTime: DateTime(2026, 5, 25, 9, 0), // ancient last move
            timeControl: 'blitz',
          ),
          RoundStatus.live,
        );
      });

      test('recent last_move_time on a prior calendar day promotes to ongoing', () {
        final now = DateTime(2026, 5, 29, 0, 20);
        expect(
          GamesAppBarModel.status(
            startsAt: DateTime(2026, 5, 28, 22, 0),
            currentId: 'r3',
            liveRound: const [],
            now: now,
            lastMoveTime: DateTime(2026, 5, 29, 0, 18), // 2 min ago
            timeControl: 'rapid',
          ),
          RoundStatus.ongoing,
        );
      });

      test('classical 30-min think gap is within window — stays ongoing, not completed', () {
        final now = DateTime(2026, 5, 29, 15, 0);
        expect(
          GamesAppBarModel.status(
            startsAt: DateTime(2026, 5, 29, 13, 0),
            currentId: 'r4',
            liveRound: const [],
            now: now,
            lastMoveTime: DateTime(2026, 5, 29, 14, 30), // 30 min ago, classical
            timeControl: 'standard',
          ),
          RoundStatus.ongoing,
        );
      });

      test('aged last_move_time with no backend-live and no recency does not promote', () {
        final now = DateTime(2026, 5, 29, 15, 0);
        expect(
          GamesAppBarModel.status(
            startsAt: DateTime(2026, 5, 27, 13, 0), // 2 days ago
            currentId: 'r5',
            liveRound: const [],
            now: now,
            lastMoveTime: DateTime(2026, 5, 27, 14, 0), // 2 days ago
            timeControl: 'blitz',
          ),
          RoundStatus.completed,
        );
      });

      test('future start with no signals is upcoming', () {
        final now = DateTime(2026, 5, 29, 10, 0);
        expect(
          GamesAppBarModel.status(
            startsAt: DateTime(2026, 5, 29, 18, 0),
            currentId: 'r6',
            liveRound: const [],
            now: now,
            lastMoveTime: null,
            timeControl: 'standard',
          ),
          RoundStatus.upcoming,
        );
      });
    });
  }
  ```

- [ ] **Step 9: Run the status test, expect FAIL.**
  ```
  flutter test test/games_app_bar_status_test.dart
  ```
  Expected: compile error — `status` has no `now`/`lastMoveTime`/`timeControl` named params yet. FAIL.

- [ ] **Step 10: Rewrite `status()` in `games_app_bar_view_model.dart` (day-boundary fix + time-control-aware promote-only).**
  Replace lines 48–72 with the following. The classification no longer uses the buggy `startsAt.day == now.day` calendar compare; instead a started round is `ongoing` while a move happened within a time-control window OR while it is the same continuous day-window, else `completed`. Backend `liveRound` is checked first and always wins (promote-only). A recent `lastMoveTime` promotes a past-start round to `ongoing` regardless of calendar day.

  ```dart
  /// Time-control-aware "recent activity" window. A move within this window
  /// promotes a started round to `ongoing` (derived-liveness, §R4). Generous
  /// upper bounds so a long classical think never flickers the round out.
  static Duration _liveWindowFor(String? timeControl) {
    switch (timeControl?.toLowerCase()) {
      case 'blitz':
        return const Duration(minutes: 20);
      case 'rapid':
        return const Duration(minutes: 40);
      case 'standard':
      case 'classical':
        return const Duration(minutes: 90);
      default:
        return const Duration(minutes: 90);
    }
  }

  static RoundStatus status({
    required DateTime? startsAt,
    required String currentId,
    required List<String> liveRound,
    DateTime? now,
    DateTime? lastMoveTime,
    String? timeControl,
  }) {
    final clock = now ?? DateTime.now();

    if (startsAt == null) return RoundStatus.upcoming;

    // (1) Backend control-plane is authoritative and promote-only.
    if (liveRound.isNotEmpty && liveRound.contains(currentId)) {
      return RoundStatus.live;
    }

    final hasStarted =
        startsAt.isBefore(clock) || startsAt.isAtSameMomentAs(clock);
    if (!hasStarted) return RoundStatus.upcoming;

    // (2) Derived liveness: a recent move keeps the round ongoing across the
    //     local-midnight boundary (fixes the 23:50-start bug, §R8).
    if (lastMoveTime != null) {
      final sinceMove = clock.difference(lastMoveTime);
      if (!sinceMove.isNegative && sinceMove <= _liveWindowFor(timeControl)) {
        return RoundStatus.ongoing;
      }
    }

    // (3) No recent activity: a round is ongoing only within its own
    //     same-day continuous window from start; older starts are completed.
    final sinceStart = clock.difference(startsAt);
    if (!sinceStart.isNegative && sinceStart < const Duration(hours: 24)) {
      return RoundStatus.ongoing;
    }
    return RoundStatus.completed;
  }
  ```

  Then update `GamesAppBarModel.fromRound` (lines 32–46) to thread the new optional params (callers that do not pass them keep prior behavior via `DateTime.now()`):

  ```dart
  factory GamesAppBarModel.fromRound(
    Round round,
    List<String> liveRound, {
    DateTime? lastMoveTime,
    String? timeControl,
  }) {
    final utcStart = round.startsAt;
    final startsAt = TimeUtils.toLocal(utcStart);

    return GamesAppBarModel(
      id: round.id,
      name: round.name,
      startsAt: startsAt,
      roundStatus: status(
        currentId: round.id,
        startsAt: startsAt,
        liveRound: liveRound,
        lastMoveTime: lastMoveTime,
        timeControl: timeControl,
      ),
    );
  }
  ```

- [ ] **Step 11: Run the status test, expect PASS.**
  ```
  flutter test test/games_app_bar_status_test.dart
  ```
  Expected: all 6 tests PASS.

- [ ] **Step 12: Analyze and commit the status change.**
  ```
  flutter analyze --no-pub lib/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart test/games_app_bar_status_test.dart
  git add lib/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart test/games_app_bar_status_test.dart
  git commit -m "PR-4: fix day-boundary round status; time-control-aware promote-only liveness

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

- [ ] **Step 13: Write the delta-merge precedence test (FAILING).**
  Create `test/tour_games_delta_merge_test.dart`. Tests the pure merge logic that the notifier will reuse: a bare INSERT (null `lastMoveTime`) must NOT clobber a fresher cached snapshot; an UPDATE with a newer `lastMoveTime` must win; a new id buckets in (appended); DELETE removes by id. These exercise `applyGameDelta`, a pure top-level function we add next to `GameDelta`.

  ```dart
  import 'package:chessever2/repository/supabase/game/games.dart';
  import 'package:chessever2/repository/supabase/game/tour_games_realtime_provider.dart';
  import 'package:flutter_test/flutter_test.dart';

  Games _game(
    String id, {
    String roundId = 'r1',
    String? fen,
    String? status,
    DateTime? lastMoveTime,
  }) {
    return Games(
      id: id,
      roundId: roundId,
      roundSlug: 'rs',
      tourId: 't1',
      tourSlug: 'ts',
      fen: fen,
      status: status,
      lastMoveTime: lastMoveTime,
    );
  }

  void main() {
    group('applyGameDelta', () {
      test('UPDATE with newer lastMoveTime replaces the cached fen/status', () {
        final current = [
          _game('g1', fen: 'OLD', status: '*',
              lastMoveTime: DateTime(2026, 5, 29, 10, 0)),
        ];
        final delta = GameDelta(
          eventType: GameDeltaType.update,
          game: _game('g1', fen: 'NEW', status: '1-0',
              lastMoveTime: DateTime(2026, 5, 29, 10, 1)),
          id: 'g1',
        );
        final result = applyGameDelta(current, delta);
        expect(result.single.fen, 'NEW');
        expect(result.single.status, '1-0');
      });

      test('bare INSERT (null lastMoveTime) does not clobber a fresher cached row', () {
        final current = [
          _game('g1', fen: 'FRESH', status: '*',
              lastMoveTime: DateTime(2026, 5, 29, 10, 0)),
        ];
        final delta = GameDelta(
          eventType: GameDeltaType.insert,
          game: _game('g1', fen: null, status: null, lastMoveTime: null),
          id: 'g1',
        );
        final result = applyGameDelta(current, delta);
        expect(result.single.fen, 'FRESH');
        expect(result.single.status, '*');
      });

      test('INSERT of an unknown id is appended (new id buckets in)', () {
        final current = [_game('g1', roundId: 'r1')];
        final delta = GameDelta(
          eventType: GameDeltaType.insert,
          game: _game('g2', roundId: 'r2'),
          id: 'g2',
        );
        final result = applyGameDelta(current, delta);
        expect(result.map((g) => g.id), ['g1', 'g2']);
        expect(result.last.roundId, 'r2');
      });

      test('DELETE removes the row by id', () {
        final current = [_game('g1'), _game('g2')];
        final delta = GameDelta(
          eventType: GameDeltaType.delete,
          game: null,
          id: 'g1',
        );
        final result = applyGameDelta(current, delta);
        expect(result.map((g) => g.id), ['g2']);
      });

      test('UPDATE of an unknown id is ignored (no insert, no crash)', () {
        final current = [_game('g1')];
        final delta = GameDelta(
          eventType: GameDeltaType.update,
          game: _game('g9'),
          id: 'g9',
        );
        final result = applyGameDelta(current, delta);
        expect(result.map((g) => g.id), ['g1']);
      });
    });
  }
  ```

- [ ] **Step 14: Run the delta-merge test, expect FAIL.**
  ```
  flutter test test/tour_games_delta_merge_test.dart
  ```
  Expected: compile error — `tour_games_realtime_provider.dart` and its symbols do not exist yet. FAIL.

- [ ] **Step 15: Create `tour_games_realtime_provider.dart` with `GameDelta`, `applyGameDelta`, and the channel provider.**
  Create `lib/repository/supabase/game/tour_games_realtime_provider.dart`:

  ```dart
  import 'dart:async';

  import 'package:chessever2/repository/supabase/game/games.dart';
  import 'package:hooks_riverpod/hooks_riverpod.dart';
  import 'package:supabase_flutter/supabase_flutter.dart';

  enum GameDeltaType { insert, update, delete }

  /// A single realtime row change on `public.games`, scoped to one tour.
  class GameDelta {
    const GameDelta({
      required this.eventType,
      required this.game,
      required this.id,
    });

    final GameDeltaType eventType;

    /// The row for insert/update (parsed via [Games.fromJson]); null for delete.
    final Games? game;

    /// Primary key of the affected row (present for every event type).
    final String id;

    factory GameDelta.fromPayload(PostgresChangePayload payload) {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
          return GameDelta(
            eventType: GameDeltaType.insert,
            game: Games.fromJson(payload.newRecord),
            id: payload.newRecord['id'] as String,
          );
        case PostgresChangeEvent.update:
          return GameDelta(
            eventType: GameDeltaType.update,
            game: Games.fromJson(payload.newRecord),
            id: payload.newRecord['id'] as String,
          );
        case PostgresChangeEvent.delete:
          return GameDelta(
            eventType: GameDeltaType.delete,
            game: null,
            id: payload.oldRecord['id'] as String,
          );
        default:
          return GameDelta(
            eventType: GameDeltaType.update,
            game: Games.fromJson(payload.newRecord),
            id: payload.newRecord['id'] as String,
          );
      }
    }
  }

  /// Pure delta application onto an in-memory game list, reusing the freshness
  /// ladder semantics of GamesTourNotifier._mergeGameSnapshots. A bare INSERT
  /// (null last_move_time) must never clobber a fresher cached snapshot; a new
  /// id is appended (bucketed by round_id downstream); DELETE removes by id;
  /// an UPDATE for an unknown id is ignored.
  List<Games> applyGameDelta(List<Games> current, GameDelta delta) {
    switch (delta.eventType) {
      case GameDeltaType.delete:
        return current.where((g) => g.id != delta.id).toList();
      case GameDeltaType.insert:
      case GameDeltaType.update:
        final incoming = delta.game;
        if (incoming == null) return current;
        final index = current.indexWhere((g) => g.id == incoming.id);
        if (index == -1) {
          if (delta.eventType == GameDeltaType.update) return current;
          return [...current, incoming];
        }
        final merged = mergeGameSnapshots(current[index], incoming);
        final next = List<Games>.from(current);
        next[index] = merged;
        return next;
    }
  }

  /// Freshness ladder: replace a field only when the incoming row is fresher
  /// by lastMoveTime. Shared with GamesTourNotifier so the poll and the delta
  /// path apply identical precedence (§C / §R6).
  Games mergeGameSnapshots(Games current, Games fresh) {
    final currentMoveTime = current.lastMoveTime;
    final freshMoveTime = fresh.lastMoveTime;
    final useFreshMove =
        currentMoveTime == null ||
        (freshMoveTime != null && freshMoveTime.isAfter(currentMoveTime));

    return fresh.copyWith(
      fen: useFreshMove ? fresh.fen : current.fen,
      lastMove: useFreshMove ? fresh.lastMove : current.lastMove,
      lastMoveTime: useFreshMove ? freshMoveTime : currentMoveTime,
      lastClockWhite:
          useFreshMove ? fresh.lastClockWhite : current.lastClockWhite,
      lastClockBlack:
          useFreshMove ? fresh.lastClockBlack : current.lastClockBlack,
      pgn: useFreshMove ? fresh.pgn : current.pgn,
      status: fresh.status ?? current.status,
    );
  }

  /// One long-lived raw realtime channel per OPEN tour detail screen.
  /// INSERT + UPDATE + DELETE, single `tour_id=eq.X` scalar filter.
  /// autoDispose + a short keepAlive so tab switches don't thrash phx_join.
  /// Lifecycle-gating (subscribe/unsubscribe on app background / chessboard
  /// open) is handled by the consumer via shouldStreamProvider.
  final tourGamesRealtimeProvider =
      StreamProvider.autoDispose.family<GameDelta, String>((ref, tourId) {
    final controller = StreamController<GameDelta>();
    final channel = Supabase.instance.client.channel('tour_games:$tourId');

    for (final event in const [
      PostgresChangeEvent.insert,
      PostgresChangeEvent.update,
      PostgresChangeEvent.delete,
    ]) {
      channel.onPostgresChanges(
        event: event,
        schema: 'public',
        table: 'games',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'tour_id',
          value: tourId,
        ),
        callback: (payload) {
          if (!controller.isClosed) {
            controller.add(GameDelta.fromPayload(payload));
          }
        },
      );
    }

    final link = ref.keepAlive();
    final keepAliveTimer = Timer(const Duration(seconds: 30), link.close);

    ref.onDispose(() {
      keepAliveTimer.cancel();
      channel.unsubscribe();
      controller.close();
    });

    channel.subscribe();
    return controller.stream;
  });
  ```

- [ ] **Step 16: Run the delta-merge test, expect PASS.**
  ```
  flutter test test/tour_games_delta_merge_test.dart
  ```
  Expected: all 5 tests PASS.

- [ ] **Step 17: Analyze the new provider file.**
  ```
  flutter analyze --no-pub lib/repository/supabase/game/tour_games_realtime_provider.dart test/tour_games_delta_merge_test.dart
  ```
  Expected: no errors. (If `PostgresChangePayload`/`PostgresChangeFilterType` resolve under a different name in the installed `supabase_flutter`, confirm via Context7 for the pinned version before editing — the names above match the realtime API surface that already backs `game_stream_repository.dart`.)

- [ ] **Step 18: Commit the realtime provider.**
  ```
  git add lib/repository/supabase/game/tour_games_realtime_provider.dart test/tour_games_delta_merge_test.dart
  git commit -m "PR-4: add GameDelta + tourGamesRealtimeProvider (INSERT/UPDATE/DELETE, tour_id filter)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

- [ ] **Step 19: Rewrite `GamesTourNotifier` to drop the poll and apply realtime deltas.**
  Overwrite `lib/screens/tour_detail/games_tour/providers/games_tour_provider.dart` entirely. The notifier still does the initial load, still respects `shouldStreamProvider` (now subscribe/unsubscribe of the channel listener rather than start/stop a timer), and applies deltas via the shared `applyGameDelta` (which routes through the freshness ladder). No `Timer.periodic`, no `_checkForNewGames`, no full refetch.

  ```dart
  import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
  import 'package:chessever2/repository/supabase/game/games.dart';
  import 'package:chessever2/repository/supabase/game/tour_games_realtime_provider.dart';
  import 'package:hooks_riverpod/hooks_riverpod.dart';

  /// Lifecycle gate: true while the tour detail screen is foregrounded and the
  /// chessboard is not open. Flipped false on app background / chessboard open
  /// to stop applying realtime deltas (battery, §R11).
  final shouldStreamProvider = StateProvider((ref) => true);

  final gamesTourProvider = AutoDisposeStateNotifierProvider.family<
    GamesTourNotifier,
    AsyncValue<List<Games>>,
    String
  >((ref, tourId) => GamesTourNotifier(ref: ref, tourId: tourId));

  /// Holds ALL games for a tour in memory. Freshness comes from a single
  /// per-tour realtime channel (tourGamesRealtimeProvider) applied via the
  /// freshness ladder — NOT from polling. Visible cards additionally use
  /// per-card eq-id streams as a latency optimization.
  class GamesTourNotifier extends StateNotifier<AsyncValue<List<Games>>> {
    GamesTourNotifier({required this.ref, required this.tourId})
      : super(const AsyncValue.loading()) {
      _loadInitialGames();

      _shouldStreamListener = ref.listen<bool>(shouldStreamProvider, (
        previous,
        next,
      ) {
        if (next) {
          _attachDeltaListener();
        } else {
          _detachDeltaListener();
        }
      });
    }

    final Ref ref;
    final String tourId;
    ProviderSubscription? _shouldStreamListener;
    ProviderSubscription? _deltaListener;

    Future<void> _loadInitialGames() async {
      try {
        final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
        final games = await gamesLocalStorageProvider.fetchAndSaveGames(tourId);

        if (mounted) {
          state = AsyncValue.data(games);
          if (ref.read(shouldStreamProvider)) {
            _attachDeltaListener();
          }
        }
      } catch (error, stackTrace) {
        if (mounted) {
          state = AsyncValue.error(error, stackTrace);
        }
      }
    }

    void _attachDeltaListener() {
      // Idempotent: never double-subscribe.
      _deltaListener?.close();
      _deltaListener = ref.listen<AsyncValue<GameDelta>>(
        tourGamesRealtimeProvider(tourId),
        (previous, next) {
          final delta = next.valueOrNull;
          if (delta == null) return;
          _applyDelta(delta);
        },
      );
    }

    void _detachDeltaListener() {
      _deltaListener?.close();
      _deltaListener = null;
    }

    void _applyDelta(GameDelta delta) {
      final current = state.valueOrNull;
      if (current == null || !mounted) return;
      final updated = applyGameDelta(current, delta);
      // Reference-identity check: applyGameDelta returns `current` unchanged
      // when an UPDATE targets an unknown id, so this avoids a no-op republish.
      if (!identical(updated, current)) {
        state = AsyncValue.data(updated);
      }
    }

    Future<void> refreshGames() async {
      await _loadInitialGames();
    }

    @override
    void dispose() {
      _detachDeltaListener();
      _shouldStreamListener?.close();
      super.dispose();
    }
  }
  ```

- [ ] **Step 20: Analyze the notifier and its dependents.**
  ```
  flutter analyze --no-pub lib/screens/tour_detail/games_tour/providers/games_tour_provider.dart lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart lib/screens/tour_detail/games_tour/widgets/games_tour_content_body.dart
  ```
  Expected: no errors. `_mergeGameSnapshots`/`_hasGameChanged` were removed from this file; confirm via the analyzer that nothing outside the file referenced them — `games_app_bar_provider.dart` listens to `gamesTourProvider`'s value only (lines 63–75) and uses `_roundCountSignature`, not the removed helpers. If any external referent surfaces, it must be repointed to `mergeGameSnapshots` in `tour_games_realtime_provider.dart`.

- [ ] **Step 21: Commit the notifier rewrite.**
  ```
  git add lib/screens/tour_detail/games_tour/providers/games_tour_provider.dart
  git commit -m "PR-4: remove 10s poll in GamesTourNotifier; apply realtime deltas via freshness ladder

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

- [ ] **Step 22: Write the clock-tick early-return test (FAILING).**
  Create `test/games_app_bar_clock_tick_test.dart`. Tests the pure promote-only recompute helper `recomputeStatusesPromoteOnly` that the clock tick and `_onLiveRoundsChanged` will both call: it returns the SAME list instance (so callers can `identical`-skip `_sortRounds`/`_scrollToRound`) when no status transitioned, never demotes a backend-live round, and ignores an empty live set when the previous set was non-empty and there is no corroboration (§R12).

  ```dart
  import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
  import 'package:flutter_test/flutter_test.dart';

  void main() {
    group('recomputeStatusesPromoteOnly', () {
      final now = DateTime(2026, 5, 29, 12, 0);

      GamesAppBarModel model(String id, RoundStatus s, {DateTime? startsAt}) =>
          GamesAppBarModel(
            id: id,
            name: id,
            startsAt: startsAt ?? DateTime(2026, 5, 29, 11, 0),
            roundStatus: s,
          );

      test('returns the same instance when nothing transitions', () {
        final current = [model('r1', RoundStatus.ongoing)];
        final result = recomputeStatusesPromoteOnly(
          current: current,
          liveRound: const [],
          lastMoveTimeByRound: const {},
          timeControl: 'standard',
          now: now,
        );
        expect(identical(result, current), isTrue);
      });

      test('promotes an upcoming round to live when backend marks it live', () {
        final current = [model('r2', RoundStatus.upcoming)];
        final result = recomputeStatusesPromoteOnly(
          current: current,
          liveRound: const ['r2'],
          lastMoveTimeByRound: const {},
          timeControl: 'blitz',
          now: now,
        );
        expect(identical(result, current), isFalse);
        expect(result.single.roundStatus, RoundStatus.live);
      });

      test('never demotes a backend-live round when live set still contains it', () {
        final current = [model('r3', RoundStatus.live)];
        final result = recomputeStatusesPromoteOnly(
          current: current,
          liveRound: const ['r3'],
          lastMoveTimeByRound: const {},
          timeControl: 'standard',
          now: now,
        );
        expect(identical(result, current), isTrue);
        expect(result.single.roundStatus, RoundStatus.live);
      });

      test('empty-after-non-empty live set does not demote without corroboration', () {
        final current = [model('r4', RoundStatus.live)];
        final result = recomputeStatusesPromoteOnly(
          current: current,
          liveRound: const [], // reconnect / transient-empty
          previousLiveWasNonEmpty: true,
          lastMoveTimeByRound: const {}, // no recent move corroboration
          timeControl: 'standard',
          now: now,
        );
        expect(result.single.roundStatus, RoundStatus.live);
      });
    });
  }
  ```

- [ ] **Step 23: Run the clock-tick test, expect FAIL.**
  ```
  flutter test test/games_app_bar_clock_tick_test.dart
  ```
  Expected: compile error — `recomputeStatusesPromoteOnly` is undefined. FAIL.

- [ ] **Step 24: Add `recomputeStatusesPromoteOnly` to `games_app_bar_view_model.dart`.**
  Append this top-level function at the end of `games_app_bar_view_model.dart` (after the `GamesAppBarModel` class, before EOF). It computes a candidate status per model, applies the promote-only / transient-empty guards, and returns the identical input list when nothing changed.

  ```dart
  /// Promote-only status recompute shared by the local clock tick and the
  /// control-plane listener. Returns the SAME list instance when no status
  /// transitions, so callers can `identical`-skip _sortRounds/_scrollToRound.
  /// Never demotes a round that backend [liveRound] still marks live, and
  /// ignores an empty live set that arrives after a non-empty one unless a
  /// recent move corroborates (§R4/§R12).
  List<GamesAppBarModel> recomputeStatusesPromoteOnly({
    required List<GamesAppBarModel> current,
    required List<String> liveRound,
    required Map<String, DateTime?> lastMoveTimeByRound,
    required String? timeControl,
    bool previousLiveWasNonEmpty = false,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final treatLiveAsNoInfo = liveRound.isEmpty && previousLiveWasNonEmpty;

    var changed = false;
    final next = <GamesAppBarModel>[];
    for (final m in current) {
      final candidate = GamesAppBarModel.status(
        currentId: m.id,
        startsAt: m.startsAt,
        liveRound: treatLiveAsNoInfo ? const <String>[] : liveRound,
        now: clock,
        lastMoveTime: lastMoveTimeByRound[m.id],
        timeControl: timeControl,
      );

      // Promote-only: never let a recompute move a round backwards from
      // live → anything, or ongoing → upcoming. Only forward promotions
      // (upcoming → ongoing/live, ongoing → live, completed → live/ongoing)
      // are allowed to take effect.
      final resolved = _isPromotion(m.roundStatus, candidate)
          ? candidate
          : m.roundStatus;

      if (resolved != m.roundStatus) {
        changed = true;
        next.add(m.copyWith(roundStatus: resolved));
      } else {
        next.add(m);
      }
    }

    return changed ? next : current;
  }

  /// Rank used for the promote-only guard. Higher = "more live".
  int _statusRank(RoundStatus s) {
    switch (s) {
      case RoundStatus.upcoming:
        return 0;
      case RoundStatus.completed:
        return 1;
      case RoundStatus.ongoing:
        return 2;
      case RoundStatus.live:
        return 3;
    }
  }

  bool _isPromotion(RoundStatus from, RoundStatus to) =>
      _statusRank(to) > _statusRank(from);
  ```

- [ ] **Step 25: Run the clock-tick test, expect PASS.**
  ```
  flutter test test/games_app_bar_clock_tick_test.dart
  ```
  Expected: all 4 tests PASS.

- [ ] **Step 26: Analyze and commit the recompute helper.**
  ```
  flutter analyze --no-pub lib/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart test/games_app_bar_clock_tick_test.dart
  git add lib/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart test/games_app_bar_clock_tick_test.dart
  git commit -m "PR-4: add promote-only status recompute helper (clock-tick / control-plane shared)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

- [ ] **Step 27: Wire the control-plane listener + clock tick into `_GamesAppBarNotifier` (not unit-testable; exact edits).**
  In `games_app_bar_provider.dart`, add imports after line 19:

  ```dart
  import 'dart:async';
  import 'package:flutter/foundation.dart';
  import 'package:chessever2/repository/supabase/settings/live_control_plane_provider.dart';
  ```

  Add fields to the notifier (after `_roundSortMeta`/`_liveRounds` declarations near the constructor body) — add a `_clockTimer`, `_previousLiveWasNonEmpty` flag, and a `_tourTimeControl` cache:

  ```dart
  Timer? _clockTimer;
  bool _previousLiveWasNonEmpty = false;
  ```

  Replace the constructor seed + listen block (lines 50–60) with a control-plane-sourced seed and an intersection-guarded listen:

  ```dart
      // Seed from the control plane's current value before subscribing.
      final initialDelta = ref.read(liveControlPlaneProvider).valueOrNull;
      final initialLiveRounds = initialDelta?.liveRoundIds;
      if (initialLiveRounds != null && initialLiveRounds.isNotEmpty) {
        _liveRounds = List.unmodifiable(initialLiveRounds);
        _previousLiveWasNonEmpty = true;
      }

      ref.listen<List<String>?>(
        liveControlPlaneProvider.select((a) => a.valueOrNull?.liveRoundIds),
        (previous, next) {
          if (next == null) return;
          // Intersection guard: only react when this tour's rounds' membership
          // in the live set actually changed (avoids settings no-op WAL fanout).
          final myIds = _myRoundIds();
          final prevIntersect =
              (previous ?? const <String>[]).where(myIds.contains).toSet();
          final nextIntersect = next.where(myIds.contains).toSet();
          final unchanged = prevIntersect.length == nextIntersect.length &&
              prevIntersect.containsAll(nextIntersect);
          if (unchanged) {
            // Still track non-empty history for the §R12 transient-empty guard.
            if (next.isNotEmpty) _previousLiveWasNonEmpty = true;
            return;
          }
          _onLiveRoundsChanged(next);
        },
      );

      _startClockTick();
  ```

  Add the helper + clock tick methods (place near `_onLiveRoundsChanged`, ~line 1262):

  ```dart
    Set<String> _myRoundIds() {
      final models = state.valueOrNull?.gamesAppBarModels;
      if (models == null) return const <String>{};
      return models.map((m) => m.id).toSet();
    }

    Map<String, DateTime?> _latestMoveTimeByRound() {
      final result = <String, DateTime?>{};
      if (tourId == null) return result;
      final games = ref.read(gamesTourProvider(tourId!)).valueOrNull;
      if (games == null) return result;
      for (final g in games) {
        final existing = result[g.roundId];
        final t = g.lastMoveTime;
        if (t == null) continue;
        if (existing == null || t.isAfter(existing)) {
          result[g.roundId] = t;
        }
      }
      return result;
    }

    String? _tourTimeControlValue() {
      if (tourId == null) return null;
      final games = ref.read(gamesTourProvider(tourId!)).valueOrNull;
      if (games == null || games.isEmpty) return null;
      return games.first.timeControl;
    }

    void _startClockTick() {
      _clockTimer?.cancel();
      // Coarse 45s local tick (NOT a network call): re-runs promote-only status
      // and early-returns when the model list is unchanged (§R4).
      _clockTimer = Timer.periodic(const Duration(seconds: 45), (_) {
        final current = state.valueOrNull;
        if (current == null || current.gamesAppBarModels.isEmpty) return;

        final recomputed = recomputeStatusesPromoteOnly(
          current: current.gamesAppBarModels,
          liveRound: _liveRounds,
          previousLiveWasNonEmpty: _previousLiveWasNonEmpty,
          lastMoveTimeByRound: _latestMoveTimeByRound(),
          timeControl: _tourTimeControlValue(),
        );

        // Early return: Equatable-equal list ⇒ no _sortRounds/_scrollToRound.
        if (identical(recomputed, current.gamesAppBarModels)) return;

        _sortRounds(recomputed);
        state = AsyncValue.data(
          GamesAppBarViewModel(
            gamesAppBarModels: recomputed,
            selectedId: current.selectedId,
            userSelectedId: current.userSelectedId,
          ),
        );
      });
    }
  ```

  Add `_clockTimer?.cancel();` to the notifier's `dispose()` (find the existing `@override void dispose()` and prepend the cancel before `super.dispose()`).

- [ ] **Step 28: Make `_onLiveRoundsChanged` promote-only and track the non-empty history (exact edits).**
  Replace the body of `_onLiveRoundsChanged` (lines 1262–1337) so that the recompute uses the shared promote-only helper instead of the raw `GamesAppBarModel.status(...)` map (lines 1268–1282). Keep the existing sticky/auto-selection block (lines 1286–1336) unchanged below the recompute. Replace lines 1262–1284 with:

  ```dart
    void _onLiveRoundsChanged(List<String> newLive) {
      if (newLive.isNotEmpty) _previousLiveWasNonEmpty = true;
      _liveRounds = List.unmodifiable(newLive);

      final current = state.valueOrNull;
      if (current == null) return;

      final updated = recomputeStatusesPromoteOnly(
        current: current.gamesAppBarModels,
        liveRound: _liveRounds,
        previousLiveWasNonEmpty: _previousLiveWasNonEmpty,
        lastMoveTimeByRound: _latestMoveTimeByRound(),
        timeControl: _tourTimeControlValue(),
      );

      _sortRounds(updated);
  ```

  Leave the remaining lines (`final sticky = ref.read(userSelectedRoundProvider);` through the end of the method) intact — they already operate on the local `updated` variable and respect `hasStickyValid` (§ no-auto-scroll). Because `recomputeStatusesPromoteOnly` can return the identical list, `_sortRounds` on an unchanged list is a no-op cost-wise; the sticky/selection block must still run so a same-set re-emit re-anchors selection consistently.

- [ ] **Step 29: Analyze the app-bar provider.**
  ```
  flutter analyze --no-pub lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart
  ```
  Expected: no errors. If `liveControlPlaneProvider`/`SettingsDelta` are flagged unresolved, PR-2 has not landed in the working tree — rebase onto it before continuing. The old `liveRoundsIdProvider` import (line 19) is now unused; remove it if the analyzer warns `unused_import`.

- [ ] **Step 30: Commit the app-bar reactive wiring.**
  ```
  git add lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart
  git commit -m "PR-4: reactive round status via control-plane intersection guard + local clock tick

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

- [ ] **Step 31: Add anchor-on-insert + at-top/sticky gate to the scroll provider (exact edits).**
  In `games_tour_scroll_provider.dart`, add a public method that the content body calls whenever the visible-rounds list grows above the current anchor. It captures `_lastVisibleGameId` before the rebuild has shifted indices, then re-jumps to that same game in a `postFrameCallback`, reusing `_getItemIndexForGameId` exactly like `_anchorTopAfterVisibilityChange`. It is gated so it never hijacks: only restores when the user is NOT at the very top OR has a sticky selection that must stay put; when the user is at top with no sticky pick, it leaves the natural top-anchored insert (auto-reveal of the new live round).

  Add an at-top helper and the gated restore (insert after `_anchorTopAfterVisibilityChange`, ~line 234):

  ```dart
    /// True when the topmost visible item is the first row of the list.
    bool _isAtTop() {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return true;
      final minIndex = positions
          .map((p) => p.index)
          .reduce((a, b) => a < b ? a : b);
      return minIndex == 0;
    }

    /// Preserve scroll position when rounds/games are inserted ABOVE the
    /// viewport (a new live round streaming in at the top shifts every
    /// subsequent index). Capture the anchored game BEFORE the mutation by
    /// reading `_lastVisibleGameId`, then re-jump to the same game/alignment
    /// after the rebuilt frame. Gated to avoid auto-jump:
    ///  - if the user has a sticky selection, always hold the anchor;
    ///  - else if the user is at the very top, allow the natural top insert
    ///    (reveal the new round) and do nothing;
    ///  - else (scrolled into the body) hold the anchor on the read item.
    void preserveAnchorOnInsertAbove() {
      final anchorGameId = _lastVisibleGameId;
      if (anchorGameId == null) return;

      final sticky = _ref.read(userSelectedRoundProvider);
      final hasSticky = sticky?.userSelected == true;

      if (!hasSticky && _isAtTop()) {
        // User is at top with no sticky pick: let the new round reveal itself.
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!state.isAttached) return;
        final targetIndex = _getItemIndexForGameId(anchorGameId);
        if (targetIndex == null) return;
        _isProgrammaticScroll = true;
        state.jumpTo(index: targetIndex, alignment: 0.1);
        endProgrammaticScroll();
      });
    }
  ```

- [ ] **Step 32: Call `preserveAnchorOnInsertAbove()` when the visible game list grows (exact edit in `games_tour_content_body.dart`).**
  In `games_tour_content_body.dart`, the body already reads `gamesTourScrollProvider(scopeId)` (line 192–195) and watches `gamesAppBarProvider` (line 43). Add a `ref.listen` on the games list length so an insert triggers the anchor restore. Insert this inside the widget's build, immediately after the existing `final gamesAppBar = ref.watch(gamesAppBarProvider);` (line 43):

  ```dart
      ref.listen<AsyncValue<GamesAppBarViewModel>>(gamesAppBarProvider, (
        previous,
        next,
      ) {
        final prevCount = previous?.valueOrNull?.gamesAppBarModels.length ?? 0;
        final nextCount = next.valueOrNull?.gamesAppBarModels.length ?? 0;
        if (nextCount > prevCount) {
          ref
              .read(gamesTourScrollProvider(scopeId).notifier)
              .preserveAnchorOnInsertAbove();
        }
      });
  ```

  Ensure `GamesAppBarViewModel` is imported in this file (it is referenced transitively via `gamesAppBarProvider`; if the analyzer flags it, add `import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';`). `scopeId` is already in scope at this point (it is read at line 192); if it is computed later in the method, hoist the `final scopeId = ref.watch(gamesTourScrollScopeProvider);` line above this listener.

- [ ] **Step 33: Analyze the scroll + content body changes.**
  ```
  flutter analyze --no-pub lib/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart lib/screens/tour_detail/games_tour/widgets/games_tour_content_body.dart
  ```
  Expected: no errors. Confirm `userSelectedRoundProvider` is imported in the scroll provider (it imports `games_app_bar_provider.dart` at line 3, which exports it — no new import needed).

- [ ] **Step 34: Whole-feature analyze pass.**
  ```
  flutter analyze --no-pub lib/repository/supabase/game/game_repository.dart lib/repository/supabase/game/tour_games_realtime_provider.dart lib/screens/tour_detail/games_tour/providers/games_tour_provider.dart lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart lib/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart lib/screens/tour_detail/games_tour/widgets/games_tour_content_body.dart lib/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart
  ```
  Expected: no errors across all touched files.

- [ ] **Step 35: Run the full PR-4 test suite.**
  ```
  flutter test test/game_repository_tour_games_pagination_test.dart test/games_app_bar_status_test.dart test/tour_games_delta_merge_test.dart test/games_app_bar_clock_tick_test.dart
  ```
  Expected: all green.

- [ ] **Step 36: Commit the scroll-anchor wiring.**
  ```
  git add lib/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart lib/screens/tour_detail/games_tour/widgets/games_tour_content_body.dart
  git commit -m "PR-4: preserve scroll anchor on insert-above, gated by at-top/sticky selection

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

- [ ] **Step 37: Manual device checks (ask the user — do NOT run `flutter run`/`flutter build`).** Request the user verify on a real device:
  - Open Titled Tuesday during R1; when R2 starts, R2 appears as `live`/`ongoing` within ~45s (the clock-tick interval) without an app restart, and silently — no banner/toast/badge.
  - While reading R1's games (scrolled into the body), the new R2 round inserting above does NOT jump the viewport; the game being read stays put. At the very top with no sticky pick, R2 reveals naturally.
  - Background the app (or open the chessboard) → `shouldStreamProvider` flips false → the per-tour channel detaches (no further deltas applied); resume re-attaches and catches up.
  - An off-screen game finishing updates round counts (UPDATE delta), and a withdrawn game disappears (DELETE delta) without a poll.
  - Rapid fling through a long round does not stutter (per-card eq-id channel count sanity).
  - Cross-check no regression to standings/rank tab (the in-flight rank diff is independent; this PR touches no `PlayerCard`/`TournamentPlayer` code).

Notes for the implementer: this PR depends on PR-2's `liveControlPlaneProvider` + `SettingsDelta` being present and on PR-3's `ALTER PUBLICATION ... ADD TABLE public.settings` having shipped for the control-plane push to actually fire — the local clock tick (Steps 24/27) is the correctness floor that promotes R2 even if the backend push lags or the publication flip is not yet live. The `mergeGameSnapshots` logic now lives canonically in `lib/repository/supabase/game/tour_games_realtime_provider.dart`; the old in-notifier copies were deleted in Step 19.

---

### PR-5: Switch live-rounds listeners to `liveControlPlaneProvider` slices + resolver-cascade short-circuit
Goal: replace the dead `settings` streams driving the event tab's `gamesAppBarProvider` and For You's two unconditional bumps with intersection/equality-guarded `liveControlPlaneProvider` slices, and add an input-tuple short-circuit to `liveGroupBroadcastIdsProvider.resolve()` so reviving the publication cannot fan a 5-query network cascade on every no-op WAL write — without touching the existing `tour_detail_screen_provider` live-tour-id path.

**Files:**
- Modify: `lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart` (imports ~19-20; constructor seed + listen block 50-60)
- Modify: `lib/providers/for_you_games_provider.dart` (imports 34-35; `_setupListeners` block 168-173)
- Modify: `lib/screens/group_event/providers/live_group_broadcast_id_provider.dart` (closure-local state ~44-49; `resolve()` 65-80; `emitResolvedIds()` 82-98; keep `refreshTimer` at 137 untouched)
- Create: `test/live_group_broadcast_resolver_short_circuit_test.dart`
- Test: `test/live_group_broadcast_resolver_short_circuit_test.dart`

> Assumes PR-2 already landed `SettingsDelta` (value-equality on `liveRoundIds`, `liveTourIds`, `liveGroupBroadcastIds` via `listEquals`) and `final liveControlPlaneProvider = StreamProvider<SettingsDelta>(...)` in `lib/repository/supabase/settings/live_control_plane_provider.dart`. Assumes PR-1's `listEquals` guards on For-You `:168/:171` and PR-3's publication flip are also landed. Assumes the PR-4 standings-rank diff is landed (do not reference `customPoints`/`broadcast_custom_scoring.dart`).

---

**Part A — Resolver-cascade input-tuple short-circuit (TDD).**

The short-circuit is a pure function over the `(configuredLiveEntries, liveRoundIds)` input tuple: if the tuple is unchanged since the last `resolve()` call, skip the 5-query cascade entirely. Today `liveGroupBroadcastIdsProvider` only de-dups the *output* (`lastResolvedIds`/`listEquals` at :57); reviving the `settings` publication would call `resolver.resolve()` (5 network queries) on every no-op WAL UPDATE. We extract the comparison into a testable top-level helper and wire it into the closure.

- [ ] **Step 1: Write the FAILING test for the input-tuple comparison helper.**

Create `test/live_group_broadcast_resolver_short_circuit_test.dart`:

```dart
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('liveResolverInputUnchanged', () {
    test('returns false when there is no prior input (first call)', () {
      expect(
        liveResolverInputUnchanged(
          previousConfigured: null,
          previousLiveRoundIds: null,
          nextConfigured: const ['gb-1'],
          nextLiveRoundIds: const ['r-1'],
        ),
        isFalse,
      );
    });

    test('returns true when both lists are identical', () {
      expect(
        liveResolverInputUnchanged(
          previousConfigured: const ['gb-1', 'gb-2'],
          previousLiveRoundIds: const ['r-1', 'r-2'],
          nextConfigured: const ['gb-1', 'gb-2'],
          nextLiveRoundIds: const ['r-1', 'r-2'],
        ),
        isTrue,
      );
    });

    test('returns false when configured entries change', () {
      expect(
        liveResolverInputUnchanged(
          previousConfigured: const ['gb-1'],
          previousLiveRoundIds: const ['r-1'],
          nextConfigured: const ['gb-1', 'gb-2'],
          nextLiveRoundIds: const ['r-1'],
        ),
        isFalse,
      );
    });

    test('returns false when live round ids change', () {
      expect(
        liveResolverInputUnchanged(
          previousConfigured: const ['gb-1'],
          previousLiveRoundIds: const ['r-1'],
          nextConfigured: const ['gb-1'],
          nextLiveRoundIds: const ['r-1', 'r-2'],
        ),
        isFalse,
      );
    });

    test('order-sensitive: a reorder counts as changed (listEquals semantics)', () {
      expect(
        liveResolverInputUnchanged(
          previousConfigured: const ['gb-1', 'gb-2'],
          previousLiveRoundIds: const ['r-1'],
          nextConfigured: const ['gb-2', 'gb-1'],
          nextLiveRoundIds: const ['r-1'],
        ),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run the test — expect FAIL (undefined `liveResolverInputUnchanged`).**

```bash
flutter test test/live_group_broadcast_resolver_short_circuit_test.dart
```

Expected: compile failure — `The function 'liveResolverInputUnchanged' isn't defined`.

- [ ] **Step 3: Add the helper to `live_group_broadcast_id_provider.dart`.** Insert this top-level function immediately above `class _StrictLiveGroupBroadcastResolver {` (currently line 151):

```dart
/// Returns true when the `(configuredLiveEntries, liveRoundIds)` input tuple
/// is identical to the previous resolve() input, so the 5-query resolver
/// cascade can be skipped. `null` previous values (first call) => not unchanged.
@visibleForTesting
bool liveResolverInputUnchanged({
  required List<String>? previousConfigured,
  required List<String>? previousLiveRoundIds,
  required List<String> nextConfigured,
  required List<String> nextLiveRoundIds,
}) {
  if (previousConfigured == null || previousLiveRoundIds == null) {
    return false;
  }
  return listEquals(previousConfigured, nextConfigured) &&
      listEquals(previousLiveRoundIds, nextLiveRoundIds);
}
```

(`listEquals` and `@visibleForTesting` are already imported via `package:flutter/foundation.dart` at line 11.)

- [ ] **Step 4: Run the test — expect PASS.**

```bash
flutter test test/live_group_broadcast_resolver_short_circuit_test.dart
```

Expected: `All tests passed!` (5 tests).

- [ ] **Step 5: Wire the short-circuit into `emitResolvedIds()`.** First add two closure-local memo fields. After line 49 (`List<String>? lastResolvedIds;`) insert:

```dart
  List<String>? lastResolvedConfigured;
  List<String>? lastResolvedLiveRoundIds;
```

Then replace the body of `emitResolvedIds()` (lines 82-98). The current body is:

```dart
  Future<void> emitResolvedIds() async {
    if (!hasConfiguredSnapshot || !hasLiveRoundsSnapshot) {
      return;
    }

    final currentRequestId = ++resolveRequestId;
    final resolvedIds = await resolve(
      configuredLiveEntries: List<String>.of(configuredLiveEntries),
      liveRoundIds: List<String>.of(liveRoundIds),
    );

    if (controller.isClosed || currentRequestId != resolveRequestId) {
      return;
    }

    emit(resolvedIds);
  }
```

Replace it with:

```dart
  Future<void> emitResolvedIds() async {
    if (!hasConfiguredSnapshot || !hasLiveRoundsSnapshot) {
      return;
    }

    final nextConfigured = List<String>.of(configuredLiveEntries);
    final nextLiveRoundIds = List<String>.of(liveRoundIds);

    // Short-circuit the 5-query cascade when neither resolver input changed.
    // The periodic refresh timer (1 min) still calls through with the same
    // tuple — but reviving the settings publication means no-op WAL UPDATEs
    // would otherwise re-run resolve() on the order of every few seconds.
    // The timer's purpose (re-evaluating freshness staleness) is preserved
    // by bypassing the short-circuit on timer-driven calls (see below).
    if (liveResolverInputUnchanged(
      previousConfigured: lastResolvedConfigured,
      previousLiveRoundIds: lastResolvedLiveRoundIds,
      nextConfigured: nextConfigured,
      nextLiveRoundIds: nextLiveRoundIds,
    )) {
      return;
    }

    lastResolvedConfigured = nextConfigured;
    lastResolvedLiveRoundIds = nextLiveRoundIds;

    final currentRequestId = ++resolveRequestId;
    final resolvedIds = await resolve(
      configuredLiveEntries: nextConfigured,
      liveRoundIds: nextLiveRoundIds,
    );

    if (controller.isClosed || currentRequestId != resolveRequestId) {
      return;
    }

    emit(resolvedIds);
  }
```

- [ ] **Step 6: Preserve the 1-min timer's freshness-recompute role.** The resolver's liveness uses `isFreshLiveRoundActivity` (time-relative to `now`), so a round can age out of "live" with the *same* input tuple — the periodic timer must still re-run the cascade even when the tuple is unchanged. Keep `refreshTimer` (line 137) but make its tick bypass the short-circuit. Replace the timer block (lines 137-139):

```dart
  final refreshTimer = Timer.periodic(_liveIndicatorRefreshInterval, (_) {
    unawaited(emitResolvedIds());
  });
```

with:

```dart
  final refreshTimer = Timer.periodic(_liveIndicatorRefreshInterval, (_) {
    // The timer re-evaluates freshness (isFreshLiveRoundActivity is time-
    // relative), so it must run even when the input tuple is unchanged.
    // Force the next emitResolvedIds() past the input short-circuit.
    lastResolvedConfigured = null;
    lastResolvedLiveRoundIds = null;
    unawaited(emitResolvedIds());
  });
```

This keeps the 1-min staleness sweep intact (a round whose last move aged past `liveIndicatorStaleAfter` still drops on the next timer tick via `emit`'s output `listEquals`), while the input short-circuit absorbs the high-frequency no-op settings WAL UPDATEs between ticks.

- [ ] **Step 7: Re-run the short-circuit test + analyze the file.**

```bash
flutter test test/live_group_broadcast_resolver_short_circuit_test.dart
flutter analyze --no-pub lib/screens/group_event/providers/live_group_broadcast_id_provider.dart
```

Expected: tests still `All tests passed!`; analyze reports `No issues found!` for that file.

- [ ] **Step 8: Commit.**

```bash
git commit -am "PR-5a: short-circuit live group broadcast resolver on unchanged input tuple

Reviving the settings realtime publication makes no-op WAL UPDATEs arrive
on liveGroupBroadcastIdsProvider's backing streams. Skip the 5-query resolver
cascade when the (configuredLiveEntries, liveRoundIds) input tuple is
unchanged; the 1-min freshness timer still bypasses the short-circuit so
staleness-based drops are unaffected.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

**Part B — Event tab: switch `gamesAppBarProvider` to `liveControlPlaneProvider.liveRoundIds` (intersection-guarded).**

This is realtime/Riverpod wiring (not unit-testable in isolation) — exact edits + `flutter analyze` + a manual device note. The constructor seed (line 50) and the live-rounds listen (lines 55-60) currently source from `liveRoundsIdProvider`. Re-source both from `liveControlPlaneProvider`'s `liveRoundIds` slice, and add an intersection guard so `_onLiveRoundsChanged` fires only when the live set's intersection with *this tour's round ids* actually changes.

- [ ] **Step 9: Add the import.** In `games_app_bar_provider.dart`, after line 19 (`import '.../live_rounds_id_provider.dart';`) add:

```dart
import 'package:chessever2/repository/supabase/settings/live_control_plane_provider.dart';
```

Leave the existing `live_rounds_id_provider.dart` import in place only if it is still referenced elsewhere in the file; if Step 11 removes its last use, also delete line 19. Verify with:

```bash
grep -n "liveRoundsIdProvider" lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart
```

If that grep returns no matches after Step 11, delete the `live_rounds_id_provider.dart` import (line 19).

- [ ] **Step 10: Add a field to track the last applied round-id intersection.** After line 105 (`bool _selectionRefreshScheduled = false;`) add:

```dart
  // The subset of live_round_ids that intersect THIS tour's rounds, as last
  // applied to _onLiveRoundsChanged. Used to suppress no-op control-plane
  // emissions (settings has no updated_at → identical re-writes arrive).
  List<String>? _lastAppliedLiveRoundIntersection;
```

- [ ] **Step 11: Replace the seed (line 50) and the listen block (lines 55-60).** Current:

```dart
    final initialLiveRounds = ref.read(liveRoundsIdProvider).valueOrNull;
    if (initialLiveRounds != null && initialLiveRounds.isNotEmpty) {
      _liveRounds = List.unmodifiable(initialLiveRounds);
    }

    ref.listen<List<String>?>(
      liveRoundsIdProvider.select((a) => a.valueOrNull),
      (_, next) {
        if (next != null) _onLiveRoundsChanged(next);
      },
    );
```

Replace with:

```dart
    final initialLiveRounds =
        ref.read(liveControlPlaneProvider).valueOrNull?.liveRoundIds;
    if (initialLiveRounds != null && initialLiveRounds.isNotEmpty) {
      _liveRounds = List.unmodifiable(initialLiveRounds);
    }

    ref.listen<List<String>?>(
      liveControlPlaneProvider.select((d) => d.valueOrNull?.liveRoundIds),
      (_, next) {
        if (next == null) return;
        // Intersection guard: only recompute when the live ids that belong to
        // THIS tour's rounds actually change. A control-plane push for an
        // unrelated tour, or an identical re-write, must not trigger
        // _sortRounds/_scrollToRound. Empty-after-non-empty is left to
        // _onLiveRoundsChanged's promote-only handling (PR-4, §R12).
        final current = state.valueOrNull;
        if (current == null) {
          // Not loaded yet — keep _liveRounds seeded so the pending _load()
          // computes correct statuses.
          _liveRounds = List.unmodifiable(next);
          return;
        }
        final tourRoundIds =
            current.gamesAppBarModels.map((m) => m.id).toSet();
        final intersection = next
            .where(tourRoundIds.contains)
            .toList(growable: false);
        if (_lastAppliedLiveRoundIntersection != null &&
            listEquals(_lastAppliedLiveRoundIntersection, intersection)) {
          return;
        }
        _lastAppliedLiveRoundIntersection = intersection;
        _onLiveRoundsChanged(next);
      },
    );
```

> Pass the full `next` (not the intersection) into `_onLiveRoundsChanged` — `_liveRounds` must hold the complete live set so `GamesAppBarModel.status()` matches by id across all rounds; the intersection is only the *trigger* gate.

- [ ] **Step 12: Add the `listEquals` import dependency.** `listEquals` lives in `package:flutter/foundation.dart`. Confirm it is importable here:

```bash
grep -n "package:flutter/foundation.dart\|package:collection/collection.dart" lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart
```

The file imports `package:collection/collection.dart` (line 1) and `package:flutter/animation.dart` (line 14) but not `foundation.dart`. Add the import after line 14:

```dart
import 'package:flutter/foundation.dart';
```

(`package:flutter/animation.dart` does not re-export `listEquals`; `foundation.dart` does. The `collection` package's `ListEquality` is an alternative but `listEquals` keeps the codebase pattern from `tour_detail_screen_provider.dart:80` and `live_group_broadcast_id_provider.dart:57`.)

- [ ] **Step 13: Analyze the event-tab files.**

```bash
flutter analyze --no-pub lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart
```

Expected: `No issues found!`. (If it reports an unused `liveRoundsIdProvider` import, delete line 19 per Step 9.)

- [ ] **Step 14: Manual device check (note for reviewer; do NOT run `flutter run`/`build`).** With the publication live, open Titled Tuesday during R1. When R2 enters `live_round_ids`, the control-plane push should fire the intersection guard once and `_onLiveRoundsChanged` flips R2 to live without restart and without scroll jump. A control-plane push affecting only an *unrelated* tour (or an identical re-write) must produce no log/recompute. Confirm a sticky user round selection is not stolen (the `hasStickyValid` path at line 1289 already guards this; verify it still holds).

- [ ] **Step 15: Commit.**

```bash
git commit -am "PR-5b: drive gamesAppBar live-rounds from liveControlPlaneProvider slice

Re-source the event tab's seed and live-rounds listen from
liveControlPlaneProvider.liveRoundIds instead of the (dead) liveRoundsIdProvider
stream, intersection-guarded against this tour's round ids so unrelated-tour
pushes and identical settings re-writes do not trigger _sortRounds/_scrollToRound.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

**Part C — For You: switch the two unconditional listens to `liveControlPlaneProvider` slices.**

PR-1 already added `listEquals` guards to the `liveTourIdProvider` (line 168) and `liveRoundsIdProvider` (line 171) listens. PR-5 now re-points those two guarded listens at `liveControlPlaneProvider.liveTourIds` / `liveControlPlaneProvider.liveRoundIds`. The `liveGroupBroadcastIdsProvider` listen (line 144 → `_refreshLiveCategories`) stays as-is (it already diffs categories and now benefits from Part A's short-circuit upstream).

- [ ] **Step 16: Add the import.** In `for_you_games_provider.dart`, after line 35 (`import '.../live_tour_id_provider.dart';`) add:

```dart
import 'package:chessever2/repository/supabase/settings/live_control_plane_provider.dart';
```

- [ ] **Step 17: Add two fields to `ForYouNotifier` for the diff guards.** After line 116 (`DateTime? _lastRefreshAt;`) add:

```dart
  List<String>? _lastForYouLiveTourIds;
  List<String>? _lastForYouLiveRoundIds;
```

- [ ] **Step 18: Replace the two listens (lines 168-173).** PR-1 left these as guarded `liveTourIdProvider` / `liveRoundsIdProvider` listens. Current (post-PR-1) shape:

```dart
    ref.listen(liveTourIdProvider, (_, __) {
      bumpForYouEventsRefreshSignal(ref);
    });
    ref.listen(liveRoundsIdProvider, (_, __) {
      bumpForYouEventsRefreshSignal(ref);
    });
```

Replace with the control-plane-sliced, equality-guarded version:

```dart
    ref.listen<List<String>?>(
      liveControlPlaneProvider.select((d) => d.valueOrNull?.liveTourIds),
      (_, next) {
        if (next == null) return;
        if (_lastForYouLiveTourIds != null &&
            listEquals(_lastForYouLiveTourIds, next)) {
          return;
        }
        _lastForYouLiveTourIds = List<String>.unmodifiable(next);
        bumpForYouEventsRefreshSignal(ref);
      },
    );
    ref.listen<List<String>?>(
      liveControlPlaneProvider.select((d) => d.valueOrNull?.liveRoundIds),
      (_, next) {
        if (next == null) return;
        if (_lastForYouLiveRoundIds != null &&
            listEquals(_lastForYouLiveRoundIds, next)) {
          return;
        }
        _lastForYouLiveRoundIds = List<String>.unmodifiable(next);
        bumpForYouEventsRefreshSignal(ref);
      },
    );
```

> `listEquals` is already available — `for_you_games_provider.dart` imports `package:flutter/foundation.dart` (line 42). Do not touch the `liveGroupBroadcastIdsProvider` listen (line 144) or `_refreshLiveCategories` (line 176): they stay on the existing strict-resolver stream and already diff via `tourEventCategory` comparison.

- [ ] **Step 19: Remove now-dead imports if unused.** If `liveTourIdProvider` / `liveRoundsIdProvider` are no longer referenced in `for_you_games_provider.dart` after Step 18, delete their imports (lines 34-35). Verify:

```bash
grep -n "liveTourIdProvider\|liveRoundsIdProvider" lib/providers/for_you_games_provider.dart
```

Delete each import whose symbol returns no remaining matches.

- [ ] **Step 20: Analyze For You.**

```bash
flutter analyze --no-pub lib/providers/for_you_games_provider.dart
```

Expected: `No issues found!`.

- [ ] **Step 21: Manual device check (note for reviewer).** With the publication live: on the For You tab during an event, a genuine `live_tour_ids`/`live_round_ids` change should trigger at most one diffed `forYouEventsRefreshSignal` bump (and cards re-derive via the existing `eventGamesProvider` listen on `forYouEventsRefreshProvider` at line 789). Identical settings re-writes must produce zero bumps. Category flips (ongoing→LIVE label) still come through the untouched `liveGroupBroadcastIdsProvider` listen.

- [ ] **Step 22: Commit.**

```bash
git commit -am "PR-5c: switch For You live listens to liveControlPlaneProvider slices

Re-point the (PR-1-guarded) liveTourIdProvider/liveRoundsIdProvider listens at
liveControlPlaneProvider.liveTourIds/liveRoundIds, keeping per-list listEquals
guards so no-op settings WAL writes never fan a refresh-signal bump across
visible For You cards. The strict group-broadcast category listener is unchanged.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

**Part D — No-regression verification for existing live-tour-id behavior.**

`tour_detail_screen_provider.setupLiveTourIdListener` (`lib/screens/tour_detail/provider/tour_detail_screen_provider.dart:63`) listens to `liveTourIdProvider` and reloads tours when `hasNewTours` (`:96`) detects an unknown live tour id. PR-5 intentionally does **not** migrate this listener to the control plane — its `listsAreEqual` guard (`:80-86`) already absorbs same-set/empty re-emits, and the spec scopes the control-plane switch to the event-tab `gamesAppBar` + For You only. Confirm it is untouched and still compiles.

- [ ] **Step 23: Confirm the live-tour-id path is unchanged and compiles.**

```bash
git diff --stat lib/screens/tour_detail/provider/tour_detail_screen_provider.dart
flutter analyze --no-pub lib/screens/tour_detail/provider/tour_detail_screen_provider.dart
```

Expected: `git diff --stat` shows **no** PR-5 changes to that file (only the pre-existing uncommitted standings diff, if any); analyze reports `No issues found!`. If the diff shows any PR-5 edits to `setupLiveTourIdListener` / `liveTourIdProvider` here, revert them — the live-tour-id reload path must keep using `liveTourIdProvider`.

- [ ] **Step 24: Whole-PR analyze sweep + full short-circuit test.**

```bash
flutter analyze --no-pub lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart lib/providers/for_you_games_provider.dart lib/screens/group_event/providers/live_group_broadcast_id_provider.dart lib/screens/tour_detail/provider/tour_detail_screen_provider.dart
flutter test test/live_group_broadcast_resolver_short_circuit_test.dart
```

Expected: `No issues found!` across all four files; `All tests passed!`.

**Files (absolute) touched by PR-5:**
- `/Users/berkay/projects/chessever-frontend/lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart`
- `/Users/berkay/projects/chessever-frontend/lib/providers/for_you_games_provider.dart`
- `/Users/berkay/projects/chessever-frontend/lib/screens/group_event/providers/live_group_broadcast_id_provider.dart`
- `/Users/berkay/projects/chessever-frontend/test/live_group_broadcast_resolver_short_circuit_test.dart` (new)
- Verified-unchanged: `/Users/berkay/projects/chessever-frontend/lib/screens/tour_detail/provider/tour_detail_screen_provider.dart`

---

### PR-6: Array-surface live-set refetch — player profile, countrymen, favorites
Goal: when the backend live set changes (`liveControlPlaneProvider`), refetch only the TODAY bucket on the three array-column surfaces, but only when the changed live round/tour ids intersect what is currently rendered, and only at most once per debounce window — keeping per-card eq-id streams as the freshness mechanism for visible rows.

**Files:**
- Create: `lib/repository/supabase/settings/live_slice_refetch_trigger.dart` (new pure helper + debounce coalescer — `LiveSliceRefetchTrigger`)
- Create: `test/repository/live_slice_refetch_trigger_test.dart` (unit tests for the intersection gate + debounce coalescing)
- Modify: `lib/screens/player_profile/provider/player_profile_provider.dart` (`PlayerProfileGamesNotifier` ctor `2581-2584`; add a `dispose()` override; `refresh()` at `3314-3316`)
- Modify: `lib/screens/countrymen/provider/countrymen_combined_games_provider.dart` (`CountrymenCombinedGamesNotifier` ctor `99-115`; add a today-bucket refetch method and `dispose()`)
- Modify: `lib/screens/favorites/player_games/provider/favorites_combined_games_provider.dart` (`FavoritesCombinedGamesNotifier` ctor `94-97`; add a today-bucket refetch method and `dispose()`)

Assumptions carried in from earlier PRs (do NOT re-implement them here):
- PR-2 already landed `lib/repository/supabase/settings/live_control_plane_provider.dart` exposing `final liveControlPlaneProvider = StreamProvider<SettingsDelta>(...)` and the class `SettingsDelta { final List<String> liveRoundIds; final List<String> liveTourIds; final List<String> liveGroupBroadcastIds; ... }` with `listEquals`-based value equality. PR-6 only consumes it.
- The standings-rank diff (PlayerCard.customPoints removal / TournamentPlayer.rank) is already landed; PR-6 touches none of that code.

---

- [ ] **Step 1: Write the FAILING test for `LiveSliceRefetchTrigger.intersects` (pure intersection gate).**

Create `test/repository/live_slice_refetch_trigger_test.dart`:

```dart
import 'package:chessever2/repository/supabase/settings/live_slice_refetch_trigger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LiveSliceRefetchTrigger.intersects', () {
    test('returns false when the changed live ids do not intersect rendered ids', () {
      final result = LiveSliceRefetchTrigger.intersects(
        changedLiveRoundIds: const {'round-99'},
        changedLiveTourIds: const {'tour-99'},
        renderedRoundIds: const {'round-1', 'round-2'},
        renderedTourIds: const {'tour-1', 'tour-2'},
      );
      expect(result, isFalse);
    });

    test('returns true when a changed round id intersects rendered rounds', () {
      final result = LiveSliceRefetchTrigger.intersects(
        changedLiveRoundIds: const {'round-2', 'round-99'},
        changedLiveTourIds: const {'tour-99'},
        renderedRoundIds: const {'round-1', 'round-2'},
        renderedTourIds: const {'tour-1'},
      );
      expect(result, isTrue);
    });

    test('returns true when a changed tour id intersects rendered tours', () {
      final result = LiveSliceRefetchTrigger.intersects(
        changedLiveRoundIds: const <String>{},
        changedLiveTourIds: const {'tour-1'},
        renderedRoundIds: const {'round-5'},
        renderedTourIds: const {'tour-1', 'tour-3'},
      );
      expect(result, isTrue);
    });

    test('returns false when nothing changed (empty changed sets)', () {
      final result = LiveSliceRefetchTrigger.intersects(
        changedLiveRoundIds: const <String>{},
        changedLiveTourIds: const <String>{},
        renderedRoundIds: const {'round-1'},
        renderedTourIds: const {'tour-1'},
      );
      expect(result, isFalse);
    });
  });

  group('LiveSliceRefetchTrigger.diffChangedIds', () {
    test('returns the symmetric difference of previous and next id lists', () {
      final changed = LiveSliceRefetchTrigger.diffChangedIds(
        previous: const ['a', 'b', 'c'],
        next: const ['b', 'c', 'd'],
      );
      expect(changed, equals(<String>{'a', 'd'}));
    });

    test('returns empty when previous and next are equal regardless of order', () {
      final changed = LiveSliceRefetchTrigger.diffChangedIds(
        previous: const ['a', 'b'],
        next: const ['b', 'a'],
      );
      expect(changed, isEmpty);
    });

    test('treats null previous as "all next ids changed"', () {
      final changed = LiveSliceRefetchTrigger.diffChangedIds(
        previous: null,
        next: const ['a', 'b'],
      );
      expect(changed, equals(<String>{'a', 'b'}));
    });
  });
}
```

- [ ] **Step 2: Run the test, expect FAIL (compile error — file does not exist).**

```bash
flutter test test/repository/live_slice_refetch_trigger_test.dart
```

Expected: FAIL — `Error: Couldn't resolve the package 'chessever2/repository/supabase/settings/live_slice_refetch_trigger.dart'`.

- [ ] **Step 3: Implement the pure helpers (intersection gate + diff) to make Step 1 pass.**

Create `lib/repository/supabase/settings/live_slice_refetch_trigger.dart`:

```dart
import 'dart:async';

/// Reusable primitive for the array-column surfaces (player profile,
/// countrymen, favorites). These surfaces cannot use server-side
/// `postgres_changes` (their queries filter on array columns such as
/// `player_fide_ids`), so they react to the global live-set control plane
/// instead. To stay cheap, a refetch fires only when the *changed* live
/// round/tour ids intersect what the surface currently renders, and at most
/// once per trailing debounce window (coalescing a burst of no-op-ish settings
/// WAL writes into a single refetch).
class LiveSliceRefetchTrigger {
  LiveSliceRefetchTrigger({
    required Duration debounce,
    required Future<void> Function() onRefetch,
  })  : _debounce = debounce,
        _onRefetch = onRefetch;

  final Duration _debounce;
  final Future<void> Function() _onRefetch;
  Timer? _timer;
  bool _disposed = false;

  /// Pure: returns the set of ids present in exactly one of [previous]/[next]
  /// (order-independent symmetric difference). A null [previous] (first
  /// observation) treats every id in [next] as changed.
  static Set<String> diffChangedIds({
    required List<String>? previous,
    required List<String> next,
  }) {
    final nextSet = next.toSet();
    if (previous == null) return nextSet;
    final prevSet = previous.toSet();
    return {
      ...nextSet.difference(prevSet),
      ...prevSet.difference(nextSet),
    };
  }

  /// Pure: does any changed live round/tour id intersect the rendered set?
  static bool intersects({
    required Set<String> changedLiveRoundIds,
    required Set<String> changedLiveTourIds,
    required Set<String> renderedRoundIds,
    required Set<String> renderedTourIds,
  }) {
    if (changedLiveRoundIds.any(renderedRoundIds.contains)) return true;
    if (changedLiveTourIds.any(renderedTourIds.contains)) return true;
    return false;
  }

  /// Schedules a single trailing refetch. Repeated calls inside the debounce
  /// window are coalesced — the timer is reset and only the last one fires.
  void schedule() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (_disposed) return;
      _onRefetch();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
```

- [ ] **Step 4: Run the test, expect PASS.**

```bash
flutter test test/repository/live_slice_refetch_trigger_test.dart
```

Expected: PASS — all 7 tests in the two groups green.

- [ ] **Step 5: Write the FAILING test for debounce coalescing (`schedule()` trailing + coalesce).**

Append to `test/repository/live_slice_refetch_trigger_test.dart` inside `main()`:

```dart
  group('LiveSliceRefetchTrigger.schedule (debounce coalescing)', () {
    test('coalesces a burst of schedule() calls into one refetch', () {
      fakeAsync((async) {
        var refetchCount = 0;
        final trigger = LiveSliceRefetchTrigger(
          debounce: const Duration(seconds: 4),
          onRefetch: () async {
            refetchCount++;
          },
        );

        // Burst of 5 schedules within the window.
        for (var i = 0; i < 5; i++) {
          trigger.schedule();
          async.elapse(const Duration(milliseconds: 500));
        }
        // Only 2.5s have passed; nothing fired yet.
        expect(refetchCount, 0);

        // Let the trailing window expire.
        async.elapse(const Duration(seconds: 4));
        expect(refetchCount, 1);

        trigger.dispose();
      });
    });

    test('does not fire after dispose', () {
      fakeAsync((async) {
        var refetchCount = 0;
        final trigger = LiveSliceRefetchTrigger(
          debounce: const Duration(seconds: 4),
          onRefetch: () async {
            refetchCount++;
          },
        );
        trigger.schedule();
        trigger.dispose();
        async.elapse(const Duration(seconds: 10));
        expect(refetchCount, 0);
      });
    });

    test('a second burst after the first fires schedules a second refetch', () {
      fakeAsync((async) {
        var refetchCount = 0;
        final trigger = LiveSliceRefetchTrigger(
          debounce: const Duration(seconds: 4),
          onRefetch: () async {
            refetchCount++;
          },
        );
        trigger.schedule();
        async.elapse(const Duration(seconds: 5));
        expect(refetchCount, 1);

        trigger.schedule();
        async.elapse(const Duration(seconds: 5));
        expect(refetchCount, 2);

        trigger.dispose();
      });
    });
  });
```

Add the `fake_async` import at the top of the test file:

```dart
import 'package:fake_async/fake_async.dart';
```

- [ ] **Step 6: Run the test, expect PASS (the `schedule()` implementation from Step 3 already satisfies it).**

```bash
flutter test test/repository/live_slice_refetch_trigger_test.dart
```

Expected: PASS — all 10 tests green. (`fake_async` is already a transitive dev dependency via `flutter_test`/`test`; if the import fails to resolve, run `flutter pub add --dev fake_async` first, then re-run.)

- [ ] **Step 7: Commit the reusable primitive + tests.**

```bash
git add lib/repository/supabase/settings/live_slice_refetch_trigger.dart test/repository/live_slice_refetch_trigger_test.dart
git commit -m "$(cat <<'EOF'
Add LiveSliceRefetchTrigger: intersection-gated, debounced refetch primitive

Pure helpers (diffChangedIds, intersects) + a trailing-debounce coalescer for
the array-column surfaces that cannot use server-side postgres_changes.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

- [ ] **Step 8: Wire the control-plane listener into Countrymen (`countrymen_combined_games_provider.dart`).**

Add the import at the top of the file (after the existing `game_repository.dart` import on line 2):

```dart
import 'package:chessever2/repository/supabase/settings/live_control_plane_provider.dart';
import 'package:chessever2/repository/supabase/settings/live_slice_refetch_trigger.dart';
```

In the class body, add fields just below `bool _hasMoreDates = true;` (line 97):

```dart
  List<String>? _lastLiveRoundIds;
  List<String>? _lastLiveTourIds;
  late final LiveSliceRefetchTrigger _liveTrigger = LiveSliceRefetchTrigger(
    debounce: const Duration(seconds: 4),
    onRefetch: _refetchTodayBucketForLiveSet,
  );
```

Replace the constructor body (lines 99-115) so it also subscribes to the control plane. The existing constructor is:

```dart
  CountrymenCombinedGamesNotifier(this._ref)
    : super(CountrymenCombinedGamesState(isLoading: true)) {
    _loadInitialGames();

    // Listen for country changes (temporary or persisted)
    _ref.listen<AsyncValue<Country>>(effectiveCountryProvider, (
      previous,
      next,
    ) {
      final prevCode = previous?.valueOrNull?.countryCode;
      final nextCode = next.valueOrNull?.countryCode;
      if (prevCode != null && nextCode != null && prevCode != nextCode) {
        debugPrint('[CountrymenGames] Country changed: $prevCode -> $nextCode');
        refreshGames();
      }
    });
  }
```

Replace it with:

```dart
  CountrymenCombinedGamesNotifier(this._ref)
    : super(CountrymenCombinedGamesState(isLoading: true)) {
    _loadInitialGames();

    // Listen for country changes (temporary or persisted)
    _ref.listen<AsyncValue<Country>>(effectiveCountryProvider, (
      previous,
      next,
    ) {
      final prevCode = previous?.valueOrNull?.countryCode;
      final nextCode = next.valueOrNull?.countryCode;
      if (prevCode != null && nextCode != null && prevCode != nextCode) {
        debugPrint('[CountrymenGames] Country changed: $prevCode -> $nextCode');
        refreshGames();
      }
    });

    // Live control plane: when the backend live set changes AND the changed
    // round/tour ids intersect what we currently render, schedule a debounced
    // refetch of TODAY's bucket only. Per-card eq-id streams keep visible rows
    // fresh; this only pulls in *new* games for a newly-live round.
    _ref.listen<AsyncValue<SettingsDelta>>(liveControlPlaneProvider, (
      previous,
      next,
    ) {
      final delta = next.valueOrNull;
      if (delta == null) return;
      _onLiveControlPlaneDelta(delta);
    });
  }

  void _onLiveControlPlaneDelta(SettingsDelta delta) {
    final changedRoundIds = LiveSliceRefetchTrigger.diffChangedIds(
      previous: _lastLiveRoundIds,
      next: delta.liveRoundIds,
    );
    final changedTourIds = LiveSliceRefetchTrigger.diffChangedIds(
      previous: _lastLiveTourIds,
      next: delta.liveTourIds,
    );
    _lastLiveRoundIds = delta.liveRoundIds;
    _lastLiveTourIds = delta.liveTourIds;

    if (changedRoundIds.isEmpty && changedTourIds.isEmpty) return;

    final renderedRoundIds = <String>{};
    final renderedTourIds = <String>{};
    for (final game in state.games) {
      renderedRoundIds.add(game.roundId);
      renderedTourIds.add(game.tourId);
    }

    final hit = LiveSliceRefetchTrigger.intersects(
      changedLiveRoundIds: changedRoundIds,
      changedLiveTourIds: changedTourIds,
      renderedRoundIds: renderedRoundIds,
      renderedTourIds: renderedTourIds,
    );
    if (!hit) return;

    debugPrint('[CountrymenGames] Live-set intersect → schedule today refetch');
    _liveTrigger.schedule();
  }
```

- [ ] **Step 9: Add the today-bucket-only refetch method to Countrymen.**

Insert this method into `CountrymenCombinedGamesNotifier` directly above `_generateDedupeKey` (line 455-456). It merges fresh today-bucket rows into the in-memory list by dedupe key without disturbing scroll/order beyond the existing sort, and is a no-op while searching (search has its own fresh path):

```dart
  /// Refetch ONLY today's bucket and merge new games into the list. Triggered
  /// (debounced, intersect-gated) when a newly-live round adds games for this
  /// country. Does not touch pagination state or the date cache.
  Future<void> _refetchTodayBucketForLiveSet() async {
    if (!mounted) return;
    if (state.isSearching) return; // search path is independently fresh
    final countryCode = state.countryCode;
    if (countryCode == null || countryCode.isEmpty) return;

    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      final fideCode = CountryUtils.toFideCode(countryCode);
      final today = DateTime.now();

      debugPrint('[CountrymenGames] Live refetch: today bucket only');
      final dayGames = await gameRepo.getGamesByCountryAndDate(
        countryCode: fideCode,
        date: today,
        filter: state.filter,
      );

      if (!mounted) return;
      if (dayGames.isEmpty) return;

      final mergedByKey = <String, GamesTourModel>{};
      final keptIds = Set<String>.from(state.seenGameIds);
      for (final game in state.games) {
        mergedByKey[_generateDedupeKey(game)] = game;
      }
      var added = false;
      for (final game in dayGames) {
        final model = GamesTourModel.fromGame(game);
        final key = _generateDedupeKey(model);
        if (!mergedByKey.containsKey(key)) added = true;
        mergedByKey[key] = model; // refresh existing or add new
        keptIds.add(key);
      }
      if (!added && mergedByKey.length == state.games.length) {
        // No new ids and nothing replaced size-wise; still apply to refresh
        // statuses, but the list shape is unchanged.
      }

      final merged = mergedByKey.values.toList()..sort(_compareByDateDesc);
      state = state.copyWith(games: merged, seenGameIds: keptIds);
    } catch (e) {
      debugPrint('[CountrymenGames] Live refetch error: $e');
    }
  }
```

- [ ] **Step 10: Add a `dispose()` override to Countrymen to clean up the trigger timer.**

Insert at the end of `CountrymenCombinedGamesNotifier`, after `clearFilter()` (the closing `}` of `clearFilter` is at line 577):

```dart
  @override
  void dispose() {
    _liveTrigger.dispose();
    super.dispose();
  }
```

- [ ] **Step 11: Analyze the Countrymen change.**

```bash
flutter analyze --no-pub lib/screens/countrymen/provider/countrymen_combined_games_provider.dart
```

Expected: no new errors. (Resolve any unused-import warning only if `CountryUtils`/`GamesTourModel` were not already imported — they are: `country_utils.dart` and `games_tour_model.dart` are imported at lines 5 and 4.)

Manual device check note: open Countrymen for a country active on Titled Tuesday during R1; when R2 starts and produces games for that country, the new games appear within ~4s after the live-set push, with no scroll jump and existing order preserved. Backgrounding (autoDispose) tears down the notifier and trigger.

- [ ] **Step 12: Commit the Countrymen wiring.**

```bash
git add lib/screens/countrymen/provider/countrymen_combined_games_provider.dart
git commit -m "$(cat <<'EOF'
Countrymen: intersect-gated, debounced today-bucket refetch on live-set change

Subscribes to liveControlPlaneProvider; refetches only today's bucket and only
when changed live round/tour ids intersect rendered games. Per-card eq-id
streams remain the freshness path for visible rows.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

- [ ] **Step 13: Wire the control-plane listener into Favorites (`favorites_combined_games_provider.dart`).**

Add imports after the existing `game_repository.dart` import (line 2):

```dart
import 'package:chessever2/repository/supabase/settings/live_control_plane_provider.dart';
import 'package:chessever2/repository/supabase/settings/live_slice_refetch_trigger.dart';
```

Add fields below `bool _hasMoreDates = true;` (line 92):

```dart
  List<String>? _lastLiveRoundIds;
  List<String>? _lastLiveTourIds;
  late final LiveSliceRefetchTrigger _liveTrigger = LiveSliceRefetchTrigger(
    debounce: const Duration(seconds: 4),
    onRefetch: _refetchTodayBucketForLiveSet,
  );
```

Replace the constructor (lines 94-97):

```dart
  FavoritesCombinedGamesNotifier(this._ref)
    : super(FavoritesCombinedGamesState(isLoading: true)) {
    _loadInitialGames();
  }
```

with:

```dart
  FavoritesCombinedGamesNotifier(this._ref)
    : super(FavoritesCombinedGamesState(isLoading: true)) {
    _loadInitialGames();

    // Live control plane: debounced, intersect-gated today-bucket refetch when
    // a newly-live round adds games for a favorite player. Per-card eq-id
    // streams keep visible rows fresh; this only pulls in *new* games.
    _ref.listen<AsyncValue<SettingsDelta>>(liveControlPlaneProvider, (
      previous,
      next,
    ) {
      final delta = next.valueOrNull;
      if (delta == null) return;
      _onLiveControlPlaneDelta(delta);
    });
  }

  void _onLiveControlPlaneDelta(SettingsDelta delta) {
    final changedRoundIds = LiveSliceRefetchTrigger.diffChangedIds(
      previous: _lastLiveRoundIds,
      next: delta.liveRoundIds,
    );
    final changedTourIds = LiveSliceRefetchTrigger.diffChangedIds(
      previous: _lastLiveTourIds,
      next: delta.liveTourIds,
    );
    _lastLiveRoundIds = delta.liveRoundIds;
    _lastLiveTourIds = delta.liveTourIds;

    if (changedRoundIds.isEmpty && changedTourIds.isEmpty) return;

    final renderedRoundIds = <String>{};
    final renderedTourIds = <String>{};
    for (final game in state.games) {
      renderedRoundIds.add(game.roundId);
      renderedTourIds.add(game.tourId);
    }

    final hit = LiveSliceRefetchTrigger.intersects(
      changedLiveRoundIds: changedRoundIds,
      changedLiveTourIds: changedTourIds,
      renderedRoundIds: renderedRoundIds,
      renderedTourIds: renderedTourIds,
    );
    if (!hit) return;

    debugPrint('[FavoritesGames] Live-set intersect → schedule today refetch');
    _liveTrigger.schedule();
  }
```

- [ ] **Step 14: Add the today-bucket-only refetch method to Favorites.**

Insert directly above `_generateDedupeKey` (line 491). Favorites resolves its fide-id set from `favoritePlayersNotifierProvider` (mirroring `_fetchNextDates` at lines 341-360), applies the active `selectedFideIds` filter, and dedupes by `game.gameId` (the existing dedupe key):

```dart
  /// Refetch ONLY today's bucket for the active favorite/selected fide ids and
  /// merge new games in. Debounced + intersect-gated upstream. No pagination or
  /// date-cache mutation. No-op while searching (search path is fresh).
  Future<void> _refetchTodayBucketForLiveSet() async {
    if (!mounted) return;
    if (state.isSearching) return;

    final favoritesAsync = _ref.read(favoritePlayersNotifierProvider);
    final favorites = favoritesAsync.valueOrNull?.players ?? [];
    if (favorites.isEmpty) return;

    var fideIds = favorites
        .where((f) => f.fideId != null)
        .map((f) => f.fideId!.toString())
        .toList();
    final selectedFilters = state.selectedFideIds;
    if (selectedFilters.isNotEmpty) {
      fideIds = fideIds.where((id) => selectedFilters.contains(id)).toList();
    }
    if (fideIds.isEmpty) return;

    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      final today = DateTime.now();

      debugPrint('[FavoritesGames] Live refetch: today bucket only');
      final dayGames = await gameRepo.getGamesByFideIdsAndDate(
        fideIds: fideIds,
        date: today,
        filter: state.filter,
      );

      if (!mounted) return;
      if (dayGames.isEmpty) return;

      final mergedByKey = <String, GamesTourModel>{};
      final keptIds = Set<String>.from(state.seenGameIds);
      for (final game in state.games) {
        mergedByKey[_generateDedupeKey(game)] = game;
      }
      for (final game in dayGames) {
        final model = GamesTourModel.fromGame(game);
        final key = _generateDedupeKey(model);
        mergedByKey[key] = model; // refresh existing or add new
        keptIds.add(key);
      }

      final merged = mergedByKey.values.toList()..sort(_compareByDateDesc);
      state = state.copyWith(games: merged, seenGameIds: keptIds);
    } catch (e) {
      debugPrint('[FavoritesGames] Live refetch error: $e');
    }
  }
```

- [ ] **Step 15: Add a `dispose()` override to Favorites.**

Insert after `_extractRoundNumber` (the method ending at line 553, before the final class-closing `}` at line 554):

```dart
  @override
  void dispose() {
    _liveTrigger.dispose();
    super.dispose();
  }
```

- [ ] **Step 16: Analyze the Favorites change.**

```bash
flutter analyze --no-pub lib/screens/favorites/player_games/provider/favorites_combined_games_provider.dart
```

Expected: no new errors. (`favoritePlayersNotifierProvider`, `GamesTourModel`, and `gameRepositoryProvider` are already imported at lines 3, 4, and 2.)

Manual device check note: favorite a player active in a later live round; when that round starts, their new games appear within ~4s, list order preserved, no scroll jump. A live-set change for an unrelated tour/round causes no refetch (verify via the `[FavoritesGames] Live-set intersect` debug log only firing on a real hit).

- [ ] **Step 17: Commit the Favorites wiring.**

```bash
git add lib/screens/favorites/player_games/provider/favorites_combined_games_provider.dart
git commit -m "$(cat <<'EOF'
Favorites: intersect-gated, debounced today-bucket refetch on live-set change

Subscribes to liveControlPlaneProvider; refetches today's getGamesByFideIdsAndDate
bucket only when changed live ids intersect rendered games. Visible-row freshness
stays on the per-card eq-id streams.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

- [ ] **Step 18: Wire the control-plane listener into the player-profile games notifier (`player_profile_provider.dart`).**

Add imports near the other repository imports at the top of the file (the file already imports `games.dart`; add these two below it):

```dart
import 'package:chessever2/repository/supabase/settings/live_control_plane_provider.dart';
import 'package:chessever2/repository/supabase/settings/live_slice_refetch_trigger.dart';
```

Add fields to `PlayerProfileGamesNotifier` directly below `List<GamesTourModel>? _globalSearchFallbackCache;` (line 2591):

```dart
  List<String>? _lastLiveRoundIds;
  List<String>? _lastLiveTourIds;
  late final LiveSliceRefetchTrigger _liveTrigger = LiveSliceRefetchTrigger(
    debounce: const Duration(seconds: 4),
    onRefetch: _refetchForLiveSet,
  );
```

Replace the constructor (lines 2581-2584):

```dart
  PlayerProfileGamesNotifier(this._ref, this._playerKey)
    : super(PlayerProfileGamesState(playerKey: _playerKey)) {
    _loadGames();
  }
```

with:

```dart
  PlayerProfileGamesNotifier(this._ref, this._playerKey)
    : super(PlayerProfileGamesState(playerKey: _playerKey)) {
    _loadGames();

    // Live control plane: debounced, intersect-gated refetch when a newly-live
    // round adds games for THIS player. The profile query is keyed by
    // player_fide_ids (an array column) → no server-side postgres_changes;
    // per-card eq-id streams keep visible rows fresh, this only pulls in new
    // games. TWIC profiles are historical/static → not gated to the live set.
    if (_playerKey.source != PlayerProfileDataSource.twic) {
      _ref.listen<AsyncValue<SettingsDelta>>(liveControlPlaneProvider, (
        previous,
        next,
      ) {
        final delta = next.valueOrNull;
        if (delta == null) return;
        _onLiveControlPlaneDelta(delta);
      });
    }
  }

  void _onLiveControlPlaneDelta(SettingsDelta delta) {
    final changedRoundIds = LiveSliceRefetchTrigger.diffChangedIds(
      previous: _lastLiveRoundIds,
      next: delta.liveRoundIds,
    );
    final changedTourIds = LiveSliceRefetchTrigger.diffChangedIds(
      previous: _lastLiveTourIds,
      next: delta.liveTourIds,
    );
    _lastLiveRoundIds = delta.liveRoundIds;
    _lastLiveTourIds = delta.liveTourIds;

    if (changedRoundIds.isEmpty && changedTourIds.isEmpty) return;

    final renderedRoundIds = <String>{};
    final renderedTourIds = <String>{};
    for (final game in state.allGames) {
      renderedRoundIds.add(game.roundId);
      renderedTourIds.add(game.tourId);
    }

    final hit = LiveSliceRefetchTrigger.intersects(
      changedLiveRoundIds: changedRoundIds,
      changedLiveTourIds: changedTourIds,
      renderedRoundIds: renderedRoundIds,
      renderedTourIds: renderedTourIds,
    );
    if (!hit) return;

    debugPrint('[PlayerProfileGames] Live-set intersect → schedule refetch');
    _liveTrigger.schedule();
  }
```

- [ ] **Step 19: Add the refetch method to the player-profile notifier.**

The player-profile Supabase path loads via the paginated `_loadAllSupabaseGames` (lines 2607-2641) into `state.allGames`. Reuse `_mergeGames` (lines 2593-2605, which dedupes by `gameId`) so order/scroll and filter state are preserved — do NOT call `_loadGames()` (that resets the list to a spinner). Insert this method directly above `Future<void> refresh()` (line 3314):

```dart
  /// Intersect-gated, debounced refetch of this player's Supabase games merged
  /// into the existing list (no spinner, scroll/filter state preserved). Only
  /// the Supabase source path; TWIC profiles never schedule this.
  Future<void> _refetchForLiveSet() async {
    if (!mounted) return;
    if (_playerKey.source == PlayerProfileDataSource.twic) return;

    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      final fresh = await _loadAllSupabaseGames(gameRepo);
      if (!mounted) return;

      final freshModels = fresh
          .map((game) => GamesTourModel.fromGame(game))
          .where((game) => !_isVariantEvent(game.tourSlug))
          .toList();

      final merged = _mergeGames(state.allGames, freshModels);
      final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
      merged.sort((a, b) {
        final aTime = a.lastMoveTime ?? epochFallback;
        final bTime = b.lastMoveTime ?? epochFallback;
        return bTime.compareTo(aTime);
      });

      state = state.copyWith(allGames: merged, totalCount: merged.length);
    } catch (e) {
      debugPrint('[PlayerProfileGames] Live refetch error: $e');
    }
  }
```

- [ ] **Step 20: Add a `dispose()` override to the player-profile notifier.**

Replace the existing `refresh()` + class-closing region (lines 3314-3317):

```dart
  Future<void> refresh() async {
    await _loadGames();
  }
}
```

with:

```dart
  Future<void> refresh() async {
    await _loadGames();
  }

  @override
  void dispose() {
    _liveTrigger.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 21: Analyze the player-profile change.**

```bash
flutter analyze --no-pub lib/screens/player_profile/provider/player_profile_provider.dart
```

Expected: no new errors. Confirm `GamesTourModel`, `gameRepositoryProvider`, `_isVariantEvent`, `_mergeGames`, `_loadAllSupabaseGames`, and `PlayerProfileDataSource` all resolve (they are all already defined/imported in this file).

Manual device check note: open a live player's profile Games tab during R1; when R2 starts and the player has a new R2 game, it appears within ~4s, the list keeps its scroll offset and active filters (no spinner flash). A non-intersecting live-set change schedules no refetch. The `autoDispose` family tears down `_liveTrigger` when the profile closes.

- [ ] **Step 22: Commit the player-profile wiring.**

```bash
git add lib/screens/player_profile/provider/player_profile_provider.dart
git commit -m "$(cat <<'EOF'
Player profile games: intersect-gated, debounced live-set refetch

Supabase-source profiles subscribe to liveControlPlaneProvider and merge a
fresh fetch (dedup by gameId, scroll/filter preserved) only when changed live
ids intersect rendered games. TWIC profiles excluded; per-card eq-id streams
remain the visible-row freshness path.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

- [ ] **Step 23: Final cross-file analyze of all four PR-6 files.**

```bash
flutter analyze --no-pub \
  lib/repository/supabase/settings/live_slice_refetch_trigger.dart \
  lib/screens/countrymen/provider/countrymen_combined_games_provider.dart \
  lib/screens/favorites/player_games/provider/favorites_combined_games_provider.dart \
  lib/screens/player_profile/provider/player_profile_provider.dart
```

Expected: "No issues found!" (or only pre-existing warnings unrelated to this PR). Then re-run the unit suite one last time to confirm nothing regressed:

```bash
flutter test test/repository/live_slice_refetch_trigger_test.dart
```

Expected: PASS — all 10 tests green.

---



---

## Spec coverage check

| Spec goal / requirement | Implemented by |
|---|---|
| New live round visible without restart (all 5 surfaces) | PR-2 (control-plane signal) + PR-3 (publish settings) + PR-4 (event), PR-5 (For You), PR-6 (player/countrymen/favorites) |
| Replace 10s `Timer.periodic` poll with per-tour realtime channel | PR-4 (`tourGamesRealtimeProvider`, INSERT/UPDATE/DELETE) |
| Remove the 1000-row pagination loop in `getGamesByTourId` | PR-4 (single bounded query + repo test) |
| Round status reactive (promote-only derived liveness + clock tick) | PR-4 (clock tick, derived liveness, day-boundary `status()` fix) |
| New cards/rounds appear silently at top, scroll/focus preserved, no banners | PR-4 (event-tab anchor restore, no-auto-scroll rule), PR-6 (array-surface insertion) |
| Settings stream made live via realtime (diff-guarded, reconnect/empty guard) | PR-2 (`SettingsDelta`, no-op suppression, empty-after-non-empty guard) + PR-3 |
| No refetch storms when reviving the stream | PR-1 (For-You `listEquals` guards) + PR-5 (resolver-cascade short-circuit) + PR-6 (intersection-gate + debounce) |
| `shouldStreamProvider` lifecycle gating (background/chessboard) | PR-4 (channel subscribe/unsubscribe on shouldStream) |
| No conflict with in-flight standings-`rank` diff (R10) | PR-4 built on post-removal `PlayerCard` shape |
| Array columns cannot be server-filtered → control-plane fallback | PR-6 (`LiveSliceRefetchTrigger`, today-bucket refetch) |

## Open implementation-time decisions (from spec §Open Questions)
- Time-control source for the promote-window threshold (`tours.info->>'tc'` vs per-round) — resolve in PR-4.
- Per-card stream scale: debounce per-card dispose vs migrate games tab to `subscribeToLiveGameUpdatesBatch` — resolve in PR-4 (default: keep per-card + dispose debounce).
- DELETE delta UX: instantaneous drop (default, no chrome) vs subtle removal animation — PR-4/PR-6.
