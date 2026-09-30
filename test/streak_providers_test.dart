import 'dart:async';

import 'package:chessever2/screens/streaks/data/streak_repository.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

StreakRow _row(
  int fideId,
  StreakTimeClass tc,
  int streak, {
  String? name,
  int? rating = 2700,
  String? fed = 'ENG',
  String? sex,
  int? age = 30,
}) {
  return StreakRow(
    fideId: fideId,
    timeClass: tc,
    name: name ?? 'Player, $fideId',
    fed: fed,
    sex: sex,
    rating: rating,
    age: age,
    currentStreak: streak,
    bestStreak: streak,
  );
}

Map<String, dynamic> _raw(int id, [String tc = 'standard', int streak = 3]) => {
  'fide_id': id,
  'time_class': tc,
  'name': 'Player $id',
  'current_streak': streak,
};

class _FakeWall extends StreakWallNotifier {
  _FakeWall(this.rows);
  final List<StreakRow> rows;

  @override
  Future<List<StreakRow>> build() async => rows;
}

class _FakeRepository extends StreakRepository {
  _FakeRepository({this.wall = const [], this.player});

  List<StreakRow> wall;
  PlayerStreaks? player;
  Object? wallError;
  Object? playerError;
  Completer<void>? gate;
  int wallCalls = 0;
  int playerCalls = 0;

  @override
  Future<List<StreakRow>> fetchWall() async {
    wallCalls++;
    final g = gate;
    if (g != null) await g.future;
    final err = wallError;
    if (err != null) throw err;
    return wall;
  }

  @override
  Future<PlayerStreaks?> fetchPlayer(int fideId) async {
    playerCalls++;
    final err = playerError;
    if (err != null) throw err;
    return player;
  }
}

class _FakeCache extends StreakWallCache {
  _FakeCache([this.snapshot]);
  StreakWallSnapshot? snapshot;
  final writes = <List<StreakRow>>[];

  @override
  Future<StreakWallSnapshot?> read() async => snapshot;

  @override
  Future<void> write(List<StreakRow> rows) async => writes.add(rows);
}

/// Lets the notifier's microtasks and zero-duration timers run.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('derived wall providers', () {
    final rows = sortStreakWall([
      _row(1, StreakTimeClass.standard, 55, fed: 'NZL'),
      _row(2, StreakTimeClass.standard, 35, rating: 2512, age: 71),
      _row(3, StreakTimeClass.standard, 21, name: 'Vaz, Ethan', age: 15),
      _row(4, StreakTimeClass.standard, 4, sex: 'F'),
      _row(1, StreakTimeClass.rapid, 29, fed: 'NZL'),
      _row(5, StreakTimeClass.blitz, 11, rating: 2886),
      _row(6, StreakTimeClass.blitz, 11, rating: 2900),
      _row(7, StreakTimeClass.blitz, 11, rating: null),
    ]);

    late ProviderContainer container;
    setUp(() {
      container = ProviderContainer(
        overrides: [streakWallProvider.overrideWith(() => _FakeWall(rows))],
      );
    });
    tearDown(() => container.dispose());

    Future<void> load() => container.read(streakWallProvider.future);

    test('counts players on each class wall above the 2650 floor', () async {
      await load();
      // Player 2 (2512) and the unrated blitz player 7 sit under the floor.
      expect(container.read(streakClassCountsProvider), {
        StreakTimeClass.standard: 3,
        StreakTimeClass.rapid: 1,
        StreakTimeClass.blitz: 2,
      });
    });

    test('counts are zero before the wall loads', () {
      expect(container.read(streakClassCountsProvider), {
        StreakTimeClass.standard: 0,
        StreakTimeClass.rapid: 0,
        StreakTimeClass.blitz: 0,
      });
    });

    test('all class rows keep the wall ranking', () async {
      await load();
      List<int> ids(StreakTimeClass tc) => container
          .read(streakAllClassRowsProvider(tc))
          .map((r) => r.fideId)
          .toList();
      expect(ids(StreakTimeClass.standard), [1, 2, 3, 4]);
      expect(ids(StreakTimeClass.rapid), [1]);
      // Same streak: higher rating first, unrated last.
      expect(ids(StreakTimeClass.blitz), [6, 5, 7]);
    });

    test('default class rows keep only players rated 2650+', () async {
      await load();
      List<int> ids(StreakTimeClass tc) =>
          container.read(streakClassRowsProvider(tc)).map((r) => r.fideId).toList();
      expect(ids(StreakTimeClass.standard), [1, 3, 4]);
      expect(ids(StreakTimeClass.rapid), [1]);
      expect(ids(StreakTimeClass.blitz), [6, 5]);
    });

    test('visible rows follow the selected class and the filter', () async {
      await load();
      List<int> visible() =>
          container.read(streakVisibleRowsProvider).map((r) => r.fideId).toList();
      // Default: the 2650 floor hides player 2 (2512).
      expect(visible(), [1, 3, 4]);

      container.read(streakSelectedClassProvider.notifier).state =
          StreakTimeClass.rapid;
      expect(visible(), [1]);

      container.read(streakSelectedClassProvider.notifier).state =
          StreakTimeClass.standard;
      final filter = container.read(streakWallFilterProvider.notifier);
      filter.state = const StreakWallFilter(age: StreakAgeGroup.u16);
      expect(visible(), [3]);
      // Looking for someone (an age group, a federation, a name) searches
      // everyone, so the 71-year-old 2512 player is found.
      filter.state = const StreakWallFilter(age: StreakAgeGroup.s65);
      expect(visible(), [2]);
      filter.state = const StreakWallFilter(womenOnly: true);
      expect(visible(), [4]);
      filter.state = const StreakWallFilter(fed: 'NZL');
      expect(visible(), [1]);
      filter.state = const StreakWallFilter(query: 'ethan');
      expect(visible(), [3]);

      container.read(streakSelectedClassProvider.notifier).state =
          StreakTimeClass.blitz;
      expect(visible(), isEmpty);
    });

    test('a player sees every live run, strongest first', () async {
      await load();
      final mine = container.read(playerLiveStreaksProvider(1));
      expect(mine.map((r) => (r.timeClass, r.currentStreak)), [
        (StreakTimeClass.standard, 55),
        (StreakTimeClass.rapid, 29),
      ]);
      expect(container.read(playerLiveStreaksProvider(99)), isEmpty);
    });
  });

  group('StreakRepository.loadWall', () {
    test('reads past the server cap, offsetting by rows received', () async {
      final offsets = <int>[];
      final rows = await StreakRepository.loadWall((offset, limit) async {
        offsets.add(offset);
        return offsets.length == 1
            ? StreakWallPage([_raw(1), _raw(2)], 3)
            : StreakWallPage([_raw(3)], 3);
      });
      expect(rows.map((r) => r.fideId), [1, 2, 3]);
      expect(offsets, [0, 2]);
    });

    test('refuses a wall with no exact count, after reading again', () async {
      // A capped page and the last page look alike without the count, so a
      // short page is never taken as the end (the site's "count is
      // unavailable").
      var calls = 0;
      await expectLater(
        StreakRepository.loadWall((offset, limit) async {
          calls++;
          return StreakWallPage([_raw(1)]);
        }, pageSize: 2),
        throwsA(isA<StreakWallInconsistent>()),
      );
      expect(calls, 3);
    });

    test('drops bad rows and keeps one row per player per class', () async {
      final rows = await StreakRepository.loadWall(
        (offset, limit) async => StreakWallPage([
          _raw(1),
          _raw(1, 'rapid'),
          _raw(1, 'blitz'),
          {'fide_id': 2, 'time_class': 'bullet', 'name': 'x'},
          {'fide_id': 3, 'time_class': 'standard'},
        ], 5),
      );
      expect(rows.map((r) => (r.fideId, r.timeClass, r.currentStreak)), [
        (1, StreakTimeClass.standard, 3),
        (1, StreakTimeClass.rapid, 3),
        (1, StreakTimeClass.blitz, 3),
      ]);
    });

    test('a player twice in one class is a moved snapshot, refused', () async {
      // Whoever the rewrite pushed across the page boundary the other way was
      // never read, so the wall is read again from the top, then refused.
      var calls = 0;
      await expectLater(
        StreakRepository.loadWall((offset, limit) async {
          calls++;
          return StreakWallPage([_raw(1, 'rapid'), _raw(1, 'rapid', 9)], 2);
        }),
        throwsA(isA<StreakWallInconsistent>()),
      );
      expect(calls, 3);
    });

    test('ranks classical, rapid, blitz whatever the server order', () async {
      final rows = await StreakRepository.loadWall(
        (offset, limit) async => StreakWallPage([
          _raw(1, 'blitz', 11),
          _raw(2, 'rapid', 29),
          _raw(3, 'standard', 4),
          _raw(4, 'standard', 42),
        ], 4),
      );
      expect(rows.map((r) => r.fideId), [4, 3, 2, 1]);
    });

    test('reads again when the wall moves mid-read', () async {
      var call = 0;
      final rows = await StreakRepository.loadWall((offset, limit) async {
        call++;
        // Attempt 1: the count changes between pages. Attempt 2: consistent.
        if (call == 1) return StreakWallPage([_raw(1)], 2);
        if (call == 2) return StreakWallPage([_raw(2)], 3);
        if (offset == 0) return StreakWallPage([_raw(1)], 2);
        return StreakWallPage([_raw(2)], 2);
      }, pageSize: 1);
      expect(rows.map((r) => r.fideId), [1, 2]);
      expect(call, 4);
    });

    test('refuses a wall that never holds still', () async {
      var call = 0;
      await expectLater(
        StreakRepository.loadWall((offset, limit) async {
          call++;
          return StreakWallPage([_raw(call)], call + 1);
        }, pageSize: 1),
        throwsA(isA<StreakWallInconsistent>()),
      );
    });

    test('refuses a snapshot that runs out before its count', () async {
      await expectLater(
        StreakRepository.loadWall(
          (offset, limit) async =>
              StreakWallPage(offset == 0 ? [_raw(1)] : const [], 2),
        ),
        throwsA(isA<StreakWallInconsistent>()),
      );
    });

    test('an empty wall is an empty list', () async {
      final rows = await StreakRepository.loadWall(
        (offset, limit) async => const StreakWallPage([], 0),
      );
      expect(rows, isEmpty);
    });

    test('a missing view or table reads as no streaks', () {
      expect(
        StreakRepository.isMissingRelation(
          const PostgrestException(message: 'x', code: '42P01'),
        ),
        isTrue,
      );
      expect(
        StreakRepository.isMissingRelation(
          const PostgrestException(
            message:
                "Could not find the table 'public.player_streak_class_leaderboard' in the schema cache",
            code: 'PGRST205',
          ),
        ),
        isTrue,
      );
      expect(
        StreakRepository.isMissingRelation(
          const PostgrestException(message: 'timeout', code: '57014'),
        ),
        isFalse,
      );
    });
  });

  group('wall cache encoding', () {
    test('round-trips every field', () {
      final original = StreakRow(
        fideId: 4303636,
        timeClass: StreakTimeClass.rapid,
        name: 'Ang, Alphaeus Wei Ern',
        title: 'FM',
        fed: 'NZL',
        sex: 'M',
        rating: 2362,
        birthYear: 2002,
        age: 24,
        currentStreak: 29,
        bestStreak: 31,
        bestStreakAt: DateTime.utc(2026, 8, 1, 12),
        wins: 120,
        losses: 30,
        anchorLossGameDay: '2026-05-30',
        streakStartGameDay: '2026-05-31',
        lastGameDay: '2026-09-05',
        lastResult: 'win',
        runOppAvg: 2011,
        runOppBest: 2390,
        runOppBestName: 'Smith, John',
        runOppBestTitle: 'IM',
        trackedCurrent: true,
        trackedTop500: true,
        updatedAt: DateTime.utc(2026, 9, 22, 10, 0, 0, 123),
      );
      final decoded = decodeStreakWallCache(encodeStreakWallCache([original]));
      expect(decoded, hasLength(1));
      final r = decoded.single;
      expect(r.fideId, original.fideId);
      expect(r.timeClass, original.timeClass);
      expect(r.name, original.name);
      expect(r.title, original.title);
      expect(r.fed, original.fed);
      expect(r.sex, original.sex);
      expect(r.rating, original.rating);
      expect(r.birthYear, original.birthYear);
      expect(r.age, original.age);
      expect(r.currentStreak, original.currentStreak);
      expect(r.bestStreak, original.bestStreak);
      expect(r.bestStreakAt, original.bestStreakAt);
      expect(r.wins, original.wins);
      expect(r.losses, original.losses);
      expect(r.anchorLossGameDay, original.anchorLossGameDay);
      expect(r.streakStartGameDay, original.streakStartGameDay);
      expect(r.lastGameDay, original.lastGameDay);
      expect(r.lastResult, original.lastResult);
      expect(r.runOppAvg, original.runOppAvg);
      expect(r.runOppBest, original.runOppBest);
      expect(r.runOppBestName, original.runOppBestName);
      expect(r.runOppBestTitle, original.runOppBestTitle);
      expect(r.trackedCurrent, original.trackedCurrent);
      expect(r.trackedTop500, original.trackedTop500);
      expect(r.updatedAt, original.updatedAt);
    });

    test('unreadable or foreign payloads are no rows', () {
      expect(decodeStreakWallCache(''), isEmpty);
      expect(decodeStreakWallCache('{"v":2,"cols":[],"rows":[]}'), isEmpty);
      expect(decodeStreakWallCache('[1,2,3]'), isEmpty);
      expect(
        decodeStreakWallCache(
          '{"v":1,"cols":["fide_id","time_class","name"],'
          '"rows":[[1,"blitz","A, B"],[2,"bullet","C, D"],[3]]}',
        ).map((r) => r.fideId),
        [1],
      );
    });

    test('two thousand rows stay well under a megabyte', () {
      final rows = [
        for (var i = 0; i < 2000; i++)
          StreakRow(
            fideId: 1000000 + i,
            timeClass: StreakTimeClass.values[i % 3],
            name: 'Surname-$i, Given Names',
            title: 'GM',
            fed: 'IND',
            sex: 'M',
            rating: 2400,
            birthYear: 1990,
            age: 36,
            currentStreak: 3 + i % 40,
            bestStreak: 50,
            bestStreakAt: DateTime.utc(2026, 1, 1),
            anchorLossGameDay: '2026-05-30',
            streakStartGameDay: '2026-05-31',
            lastGameDay: '2026-09-05',
            lastResult: 'win',
            runOppAvg: 2100,
            runOppBest: 2500,
            runOppBestName: 'Opponent, Some',
            runOppBestTitle: 'IM',
            updatedAt: DateTime.utc(2026, 9, 22),
          ),
      ];
      expect(encodeStreakWallCache(rows).length, lessThan(1000000));
    });
  });

  group('StreakWallNotifier', () {
    ProviderContainer containerWith(_FakeRepository repo, _FakeCache cache) {
      final c = ProviderContainer(
        overrides: [
          streakRepositoryProvider.overrideWithValue(repo),
          streakWallCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    final cachedRows = [_row(1, StreakTimeClass.standard, 7)];
    final freshRows = [
      _row(1, StreakTimeClass.standard, 8),
      _row(2, StreakTimeClass.blitz, 3),
    ];

    test('a fresh cache paints and skips the network', () async {
      final repo = _FakeRepository(wall: freshRows);
      final cache = _FakeCache(StreakWallSnapshot(cachedRows, DateTime.now()));
      final c = containerWith(repo, cache);
      expect(await c.read(streakWallProvider.future), cachedRows);
      await _settle();
      expect(repo.wallCalls, 0);
      expect(c.read(streakWallProvider).value, cachedRows);
    });

    test('a stale cache paints first, then refreshes and rewrites', () async {
      final repo = _FakeRepository(wall: freshRows);
      final cache = _FakeCache(
        StreakWallSnapshot(
          cachedRows,
          DateTime.now().subtract(const Duration(minutes: 11)),
        ),
      );
      final c = containerWith(repo, cache);
      c.listen(streakWallProvider, (_, __) {});
      expect(await c.read(streakWallProvider.future), cachedRows);
      await _settle();
      expect(repo.wallCalls, 1);
      expect(c.read(streakWallProvider).value, freshRows);
      expect(cache.writes, [freshRows]);
    });

    test('no cache: loads from the network and caches it', () async {
      final repo = _FakeRepository(wall: freshRows);
      final cache = _FakeCache();
      final c = containerWith(repo, cache);
      expect(await c.read(streakWallProvider.future), freshRows);
      expect(repo.wallCalls, 1);
      await _settle();
      expect(cache.writes, [freshRows]);
    });

    test('an empty cache counts as no cache', () async {
      final repo = _FakeRepository(wall: freshRows);
      final cache = _FakeCache(StreakWallSnapshot(const [], DateTime.now()));
      final c = containerWith(repo, cache);
      expect(await c.read(streakWallProvider.future), freshRows);
      expect(repo.wallCalls, 1);
    });

    test('a failed refresh keeps the rows on screen', () async {
      final repo = _FakeRepository(wall: freshRows);
      final cache = _FakeCache(StreakWallSnapshot(cachedRows, DateTime.now()));
      final c = containerWith(repo, cache);
      c.listen(streakWallProvider, (_, __) {});
      await c.read(streakWallProvider.future);
      repo.wallError = Exception('offline');
      await c.read(streakWallProvider.notifier).refresh();
      final state = c.read(streakWallProvider);
      expect(state.hasError, isFalse);
      expect(state.value, cachedRows);
      expect(cache.writes, isEmpty);
    });

    test('a failed first load is an error the screen can retry', () async {
      final repo = _FakeRepository(wall: freshRows)
        ..wallError = Exception('offline');
      final c = containerWith(repo, _FakeCache());
      c.listen(streakWallProvider, (_, __) {});
      await expectLater(
        c.read(streakWallProvider.future),
        throwsA(isA<Exception>()),
      );
      expect(c.read(streakWallProvider).hasError, isTrue);

      repo.wallError = null;
      await c.read(streakWallProvider.notifier).refresh();
      expect(c.read(streakWallProvider).value, freshRows);
    });

    test('concurrent refreshes share one read', () async {
      final repo = _FakeRepository(wall: freshRows);
      final cache = _FakeCache(StreakWallSnapshot(cachedRows, DateTime.now()));
      final c = containerWith(repo, cache);
      c.listen(streakWallProvider, (_, __) {});
      await c.read(streakWallProvider.future);

      repo.gate = Completer<void>();
      final notifier = c.read(streakWallProvider.notifier);
      final a = notifier.refresh();
      final b = notifier.refresh();
      final d = notifier.refresh();
      repo.gate!.complete();
      await Future.wait([a, b, d]);
      expect(repo.wallCalls, 1);
      expect(c.read(streakWallProvider).value, freshRows);

      // Once it lands, the next refresh reads again.
      repo.gate = null;
      await notifier.refresh();
      expect(repo.wallCalls, 2);
    });

    test('refreshIfStale only reads when the rows are old', () async {
      final repo = _FakeRepository(wall: freshRows);
      final cache = _FakeCache(
        StreakWallSnapshot(
          cachedRows,
          DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );
      final c = containerWith(repo, cache);
      c.listen(streakWallProvider, (_, __) {});
      await c.read(streakWallProvider.future);
      final notifier = c.read(streakWallProvider.notifier);
      await notifier.refreshIfStale();
      expect(repo.wallCalls, 0);
      await notifier.refreshIfStale(
        maxAge: const Duration(milliseconds: 500),
      );
      expect(repo.wallCalls, 1);
      expect(notifier.fetchedAt, isNotNull);
    });
  });

  group('playerStreaksProvider', () {
    final carlsen = PlayerStreaks(
      fideId: 1503014,
      name: 'Carlsen, Magnus',
      runs: {
        StreakTimeClass.blitz: const StreakClassRun(
          timeClass: StreakTimeClass.blitz,
          currentStreak: 11,
          bestStreak: 11,
        ),
      },
    );

    testWidgets('outlives its last listener for five minutes', (tester) async {
      final repo = _FakeRepository(player: carlsen);
      final c = ProviderContainer(
        overrides: [streakRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      final provider = playerStreaksProvider(1503014);

      var sub = c.listen(provider, (_, __) {});
      await tester.pump();
      expect(c.read(provider).value, carlsen);
      expect(repo.playerCalls, 1);

      // Back to the wall and forward again inside the window: no re-read.
      sub.close();
      await tester.pump(const Duration(minutes: 4));
      sub = c.listen(provider, (_, __) {});
      await tester.pump();
      expect(c.read(provider).value, carlsen);
      expect(repo.playerCalls, 1);

      // Gone for longer than the window: read again.
      sub.close();
      await tester.pump(kPlayerStreaksKeepAlive + const Duration(seconds: 1));
      sub = c.listen(provider, (_, __) {});
      await tester.pump();
      expect(repo.playerCalls, 2);
      sub.close();
      await tester.pump(kPlayerStreaksKeepAlive + const Duration(seconds: 1));
    });

    testWidgets('a failed read is not kept', (tester) async {
      final repo = _FakeRepository(player: carlsen)
        ..playerError = Exception('offline');
      final c = ProviderContainer(
        overrides: [streakRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      final provider = playerStreaksProvider(1503014);

      var sub = c.listen(provider, (_, __) {});
      await tester.pump();
      expect(c.read(provider).hasError, isTrue);
      sub.close();
      // Riverpod disposes on a zero-duration timer; let fake time tick once.
      await tester.pump(const Duration(milliseconds: 1));

      repo.playerError = null;
      sub = c.listen(provider, (_, __) {});
      await tester.pump();
      expect(repo.playerCalls, 2);
      expect(c.read(provider).value, carlsen);
      sub.close();
      await tester.pump(kPlayerStreaksKeepAlive + const Duration(seconds: 1));
    });

    testWidgets('no streak profile is null, not an error', (tester) async {
      final repo = _FakeRepository();
      final c = ProviderContainer(
        overrides: [streakRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      final sub = c.listen(playerStreaksProvider(42), (_, __) {});
      await tester.pump();
      final state = c.read(playerStreaksProvider(42));
      expect(state.hasError, isFalse);
      expect(state.hasValue, isTrue);
      expect(state.value, isNull);
      sub.close();
      await tester.pump(kPlayerStreaksKeepAlive + const Duration(seconds: 1));
    });
  });
}
