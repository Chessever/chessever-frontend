import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_games_cache.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The explorer's games cache: what it keys pages by, what it keeps, how long,
/// and when it forgets. Every rule here is one a stale or crossed page would
/// break silently, so each has a test that fails the moment it does.

const _fen =
    'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R b KQkq - 3 5';
const _moves = <String>[
  'e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6', 'd2d3', 'f8c5', 'b1c3', //
];

Map<String, dynamic> _row(String id) => <String, dynamic>{
  'id': id,
  'white': 'White $id',
  'black': 'Black $id',
  'result': '1-0',
  'whiteElo': 2700,
  'blackElo': 2650,
  'date': '2024-05-12',
};

GamebaseSearchQueryResponse _page(
  List<String> ids, {
  int pageNumber = 0,
  bool hasMore = true,
  int? totalCount,
}) => GamebaseSearchQueryResponse(
  status: 'success',
  data: [for (final id in ids) _row(id)],
  metadata: GamebasePaginationMetadata(
    pageNumber: pageNumber,
    pageSize: 20,
    totalCount: totalCount,
    hasMoreValue: hasMore,
  ),
);

/// Answers every request with one row naming it, and counts the requests.
class _Repo extends GamebaseRepository {
  _Repo({String? baseUrl})
    : super(Dio(), apiKey: 'test', baseUrl: baseUrl ?? 'https://example.test');

  int calls = 0;
  Completer<void>? gate;

  @override
  Future<GamebaseSearchQueryResponse> getPositionGames({
    required String fen,
    List<String> moves = const [],
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    calls++;
    await gate?.future;
    return _page(['$uci-$pageNumber-$calls'], pageNumber: pageNumber);
  }

  @override
  Future<GamebaseSearchQueryResponse> getFenPositionGames({
    required String fen,
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    calls++;
    await gate?.future;
    return _page(['fen-$pageNumber-$calls'], pageNumber: pageNumber);
  }
}

GamebasePositionGamesQuery _query({
  String? uci,
  List<String> moves = _moves,
  int pageNumber = 0,
  GamebaseFilters filters = const GamebaseFilters(),
  bool fen = false,
}) => GamebasePositionGamesQuery.sheetPage(
  fen: _fen,
  filters: filters,
  moves: moves,
  uci: uci,
  pageNumber: pageNumber,
  useFenEndpoint: fen,
);

void main() {
  group('response JSON', () {
    test('round-trips every field of a page', () {
      final pages = [
        _page(['a', 'b'], totalCount: 2, hasMore: false),
        const GamebaseSearchQueryResponse(
          status: 'success',
          data: [
            {
              'id': 'x',
              'continuation': ['e2e4', 'e7e5'],
              'whiteFideId': 1503014,
              'nested': {
                'k': null,
                'list': [1, 2.5, true],
              },
            },
          ],
          metadata: GamebasePaginationMetadata(
            pageNumber: 3,
            pageSize: 10,
            totalCountIsEstimate: true,
          ),
        ),
      ];
      for (final page in pages) {
        final back = GamebaseSearchQueryResponse.fromJson(
          jsonDecode(jsonEncode(page.toJson())) as Map<String, dynamic>,
        );
        expect(back.status, page.status);
        expect(back.data, page.data);
        expect(back.metadata.pageNumber, page.metadata.pageNumber);
        expect(back.metadata.pageSize, page.metadata.pageSize);
        expect(back.metadata.totalCount, page.metadata.totalCount);
        expect(back.metadata.hasMoreValue, page.metadata.hasMoreValue);
        expect(back.metadata.hasMore, page.metadata.hasMore);
        expect(
          back.metadata.totalCountIsEstimate,
          page.metadata.totalCountIsEstimate,
        );
        expect(jsonEncode(back.toJson()), jsonEncode(page.toJson()));
      }
    });
  });

  group('wire request', () {
    final repo = _Repo();

    test('position games: the same method, url and body as before', () {
      final withMoves = repo.positionGamesRequest(
        fen: _fen,
        moves: _moves,
        uci: 'd7d6',
        sortBy: GamebaseSortField.avgElo,
        sortDirection: GamebaseSortDirection.asc,
      );
      expect(withMoves.method, 'POST');
      expect(
        withMoves.url,
        'https://example.test/api/game-position/games/query',
      );
      expect(
        withMoves.payload,
        GamebaseRepository.buildPositionGamesQueryBody(
          fen: _fen,
          moves: _moves,
          uci: 'd7d6',
          sortBy: GamebaseSortField.avgElo,
          sortDirection: GamebaseSortDirection.asc,
        ),
      );

      final noMoves = repo.positionGamesRequest(fen: _fen, uci: 'd7d6');
      expect(noMoves.method, 'GET');
      expect(noMoves.url, 'https://example.test/api/game-position/games');
    });

    test('FEN games: the same GET and parameters as before', () {
      final request = repo.fenPositionGamesRequest(
        fen: _fen,
        playerId: 'p1',
        sortBy: GamebaseSortField.date,
        sortDirection: GamebaseSortDirection.desc,
      );
      expect(request.method, 'GET');
      expect(request.url, 'https://example.test/api/game-position/fen/games');
      expect(
        request.payload,
        GamebaseRepository.buildFenPositionGamesQueryParameters(
          fen: _fen,
          playerId: 'p1',
          sortBy: GamebaseSortField.date,
          sortDirection: GamebaseSortDirection.desc,
        ),
      );
    });

    test('identity ignores the order fields were built in', () {
      const a = GamebaseWireRequest(
        method: 'GET',
        url: 'u',
        payload: {
          'b': 1,
          'a': 2,
          'n': {'y': 1, 'x': 2},
        },
      );
      const b = GamebaseWireRequest(
        method: 'GET',
        url: 'u',
        payload: {
          'a': 2,
          'n': {'x': 2, 'y': 1},
          'b': 1,
        },
      );
      expect(a.identity, b.identity);
    });
  });

  group('cache keys', () {
    ExplorerGamesCache cacheFor(GamebaseRepository repo) =>
        ExplorerGamesCache(repository: () => repo, currentUserId: () => 'u');

    test('one key per wire request', () {
      final cache = cacheFor(_Repo());
      final base = cache.keyFor(_query(uci: 'd7d6'));

      expect(cache.keyFor(_query(uci: 'd7d6')), base);
      // The repository trims the uci before sending it.
      expect(cache.keyFor(_query(uci: ' d7d6 ')), base);

      // Everything that changes the request changes the key.
      expect(cache.keyFor(_query(uci: 'a7a6')), isNot(base));
      expect(cache.keyFor(_query()), isNot(base));
      expect(cache.keyFor(_query(uci: 'd7d6', pageNumber: 1)), isNot(base));
      expect(
        cache.keyFor(
          _query(uci: 'd7d6', filters: const GamebaseFilters(minRating: 2400)),
        ),
        isNot(base),
      );
      expect(
        cache.keyFor(
          _query(
            uci: 'd7d6',
            filters: const GamebaseFilters(sortBy: GamebaseSortField.whiteElo),
          ),
        ),
        isNot(base),
      );
      expect(cache.keyFor(_query(uci: 'd7d6', fen: true)), isNot(base));
      expect(
        cacheFor(
          _Repo(baseUrl: 'https://staging.example.test'),
        ).keyFor(_query(uci: 'd7d6')),
        isNot(base),
      );
    });

    test('the FEN endpoint ignores the move line, so every line shares it', () {
      final viaLine = _query(fen: true);
      final viaTransposition = _query(fen: true, moves: const ['e2e4']);
      final noLine = _query(fen: true, moves: const []);
      expect(viaLine, viaTransposition);
      expect(viaLine, noLine);
      expect(viaLine.moves, isEmpty);

      final cache = cacheFor(_Repo());
      expect(cache.keyFor(viaLine), cache.keyFor(noLine));
    });
  });

  group('in-flight requests', () {
    test('identical wire requests share one network call', () async {
      final repo = _Repo()..gate = Completer<void>();
      final cache = ExplorerGamesCache(
        repository: () => repo,
        currentUserId: () => 'u',
      );

      final first = cache.fetch(_query(uci: 'd7d6'));
      final second = cache.fetch(_query(uci: ' d7d6'));
      expect(cache.isFetching(_query(uci: 'd7d6')), isTrue);
      repo.gate!.complete();
      final results = await Future.wait([first, second]);

      expect(repo.calls, 1);
      expect(identical(results.first, results.last), isTrue);
      expect(cache.isFetching(_query(uci: 'd7d6')), isFalse);

      // Settled: the next fetch goes to the server again.
      await cache.fetch(_query(uci: 'd7d6'));
      expect(repo.calls, 2);
    });

    test('a failed request is not remembered', () async {
      final repo = _FailingRepo();
      final cache = ExplorerGamesCache(
        repository: () => repo,
        currentUserId: () => 'u',
      );
      await expectLater(cache.fetch(_query()), throwsException);
      expect(cache.peek(_query()), isNull);
      expect(cache.isFetching(_query()), isFalse);
    });
  });

  group('freshness', () {
    test(
      'a fetched page is current for two minutes, then only a snapshot',
      () async {
        var now = DateTime(2026, 9, 26, 12);
        final cache = ExplorerGamesCache(
          repository: _Repo.new,
          currentUserId: () => 'u',
          now: () => now,
        );
        final response = await cache.fetch(_query());
        expect(cache.isFresh(response), isTrue);
        expect(cache.peek(_query())?.response, same(response));
        expect(cache.peek(_query())?.source, ExplorerGamesSource.memory);

        now = now.add(kExplorerGamesFreshFor + const Duration(seconds: 1));
        expect(cache.isFresh(response), isFalse);
        // Still there to paint, never passed off as current.
        expect(cache.peek(_query())?.response, same(response));

        // A page that did not come through the cache has no known age.
        expect(cache.isFresh(_page(['x'])), isFalse);
      },
    );

    test('later pages are never kept as snapshots', () async {
      final cache = ExplorerGamesCache(
        repository: _Repo.new,
        currentUserId: () => 'u',
      );
      await cache.fetch(_query(pageNumber: 1));
      expect(cache.peek(_query(pageNumber: 1)), isNull);
    });
  });

  group('retention', () {
    test(
      'a first page stays answerable from memory after 60 other pages',
      () async {
        var now = DateTime(2026, 9, 26, 12);
        final repo = _Repo();
        final container = ProviderContainer(
          overrides: [
            gamebaseRepositoryProvider.overrideWithValue(repo),
            explorerGamesCacheProvider.overrideWith((ref) {
              final cache = ExplorerGamesCache(
                repository: () => repo,
                currentUserId: () => 'u',
                now: () => now,
              );
              ref.onDispose(cache.dispose);
              return cache;
            }),
          ],
        );
        addTearDown(container.dispose);

        // The inline strip's page for the position the reader starts on.
        final first = GamebasePositionGamesQuery.fromFilters(
          fen: _fen,
          filters: const GamebaseFilters(),
          moves: _moves,
          pageSize: 10,
          notationPlies: 20,
        );
        await container.read(positionGamesProvider(first).future);
        final callsAfterFirst = repo.calls;

        // Sixty other first pages, as stepping through a line warms them.
        for (var i = 0; i < 60; i++) {
          await container.read(
            positionGamesProvider(_query(uci: 'a2a3-$i')).future,
          );
          now = now.add(const Duration(milliseconds: 500));
        }
        await Future<void>.delayed(Duration.zero);

        // Stepping back: answered from memory, no loading frame, no request.
        final back = container.read(positionGamesProvider(first));
        expect(back.isLoading, isFalse);
        expect(back.hasValue, isTrue);
        expect(repo.calls, callsAfterFirst + 60);

        // Past the retention window the page is released on the next call.
        now = now.add(kExplorerGamesRetainFor);
        container.read(explorerGamesCacheProvider).peek(_query());
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(explorerGamesCacheProvider).debugRetainedCount,
          0,
        );
        final later = container.read(positionGamesProvider(first));
        expect(later.isLoading, isTrue);
        await container.read(positionGamesProvider(first).future);
      },
    );

    testWidgets(
      'in the app, pages are released on time with no further explorer use',
      (tester) async {
        var now = DateTime(2026, 9, 26, 12);
        final repo = _Repo();
        final container = ProviderContainer(
          overrides: [
            gamebaseRepositoryProvider.overrideWithValue(repo),
            explorerGamesCacheProvider.overrideWith((ref) {
              final cache = ExplorerGamesCache(
                repository: () => repo,
                currentUserId: () => 'u',
                now: () => now,
                releaseOnTimer: true,
              );
              ref.onDispose(cache.dispose);
              return cache;
            }),
          ],
        );
        final cache = container.read(explorerGamesCacheProvider);

        // A burst of pages settles, then the reader leaves the explorer.
        final queries = [for (var i = 0; i < 5; i++) _query(uci: 'a2a3-$i')];
        for (final query in queries) {
          await container.read(positionGamesProvider(query).future);
        }
        expect(cache.debugRetainedCount, queries.length);
        expect(cache.debugReleaseTimerArmed, isTrue);

        // Still held just before they expire...
        now = now.add(kExplorerGamesRetainFor - const Duration(seconds: 1));
        await tester.pump(kExplorerGamesRetainFor - const Duration(seconds: 1));
        expect(cache.debugRetainedCount, queries.length);

        // ...and released once they have, with no cache call to prompt it.
        now = now.add(const Duration(seconds: 1) + kExplorerGamesReleaseBatch);
        await tester.pump(const Duration(seconds: 1) + kExplorerGamesReleaseBatch);
        await tester.pump();
        expect(cache.debugRetainedCount, 0);
        expect(cache.debugReleaseTimerArmed, isFalse);
        for (final query in queries) {
          expect(container.exists(positionGamesProvider(query)), isFalse);
        }

        // A page arriving later arms the timer again; disposing the
        // container cancels it (a pending timer would fail this test).
        await container.read(positionGamesProvider(queries.first).future);
        expect(cache.debugReleaseTimerArmed, isTrue);
        container.dispose();
        expect(cache.debugReleaseTimerArmed, isFalse);
        await tester.pump();
      },
    );

    test('only the app turns the release timer on', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Under `flutter test` the shared cache releases on its next call, so
      // widget tests that outlive their tree never trip on a pending timer.
      expect(container.read(explorerGamesCacheProvider).releaseOnTimer, isFalse);
    });
  });

  group('disk store', () {
    late Directory dir;
    var now = DateTime(2026, 9, 26, 12);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('explorer_games_test');
      now = DateTime(2026, 9, 26, 12);
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    FileExplorerGamesDiskStore store({int maxPages = 10, int? maxBytes}) =>
        FileExplorerGamesDiskStore(
          directory: () async => dir,
          maxPages: maxPages,
          maxBytes: maxBytes ?? kExplorerGamesDiskBytes,
          now: () => now,
        );

    String key(String name) => explorerGamesCacheKey(
      GamebaseWireRequest(method: 'GET', url: name, payload: const {}),
    );

    Future<List<String>> filesOnDisk() async => [
      await for (final entity in dir.list())
        if (entity is File && entity.path.endsWith('.json'))
          entity.uri.pathSegments.last,
    ]..sort();

    Future<void> expectIndexMatchesDisk(FileExplorerGamesDiskStore s) async {
      final indexed = List.of(await s.debugIndexedFiles())..sort();
      expect(indexed, await filesOnDisk());
      var bytes = 0;
      for (final name in indexed) {
        bytes += await File('${dir.path}/$name').length();
      }
      expect(await s.debugIndexedBytes(), bytes);
    }

    test('pages survive a restart', () async {
      await store().write(key('a'), _page(['a1', 'a2']), now, owner: 'o');

      final reopened = store();
      final found = await reopened.readMany([key('a'), key('b')], owner: 'o');
      expect(found.keys, [key('a')]);
      expect(found[key('a')]!.source, ExplorerGamesSource.disk);
      expect(found[key('a')]!.fetchedAt, now);
      expect(found[key('a')]!.response.data.map((row) => row['id']), [
        'a1',
        'a2',
      ]);
      await expectIndexMatchesDisk(reopened);
    });

    test('an expired page is deleted on read and leaves the index', () async {
      final s = store(maxPages: 3);
      final old = now.subtract(
        kExplorerGamesDiskMaxAge + const Duration(hours: 1),
      );
      await s.write(key('old'), _page(['o']), old, owner: 'o');
      await s.write(key('b'), _page(['b']), now, owner: 'o');
      await s.write(key('c'), _page(['c']), now, owner: 'o');

      expect(await s.readMany([key('old')], owner: 'o'), isEmpty);
      await expectIndexMatchesDisk(s);
      expect(await s.debugIndexedFiles(), hasLength(2));

      // Room for one more: nothing live may be evicted to make it.
      await s.write(key('d'), _page(['d']), now, owner: 'o');
      expect(
        (await s.readMany([key('b'), key('c'), key('d')], owner: 'o')).keys,
        [key('b'), key('c'), key('d')],
      );
      await expectIndexMatchesDisk(s);
    });

    test('evicts the least recently used page first', () async {
      final s = store(maxPages: 2);
      await s.write(key('a'), _page(['a']), now, owner: 'o');
      await s.write(key('b'), _page(['b']), now, owner: 'o');
      await s.readMany([key('a')], owner: 'o'); // a is now the most recent
      await s.write(key('c'), _page(['c']), now, owner: 'o');

      final found = await s.readMany([
        key('a'),
        key('b'),
        key('c'),
      ], owner: 'o');
      expect(found.keys, [key('a'), key('c')]);
      await expectIndexMatchesDisk(s);
    });

    test('keeps within its byte budget', () async {
      // The size of one saved file, wrapper included.
      final probe = store(maxPages: 100);
      await probe.write(key('a'), _page(['a']), now, owner: 'o');
      final one = await probe.debugIndexedBytes();

      final s = store(maxPages: 100, maxBytes: one * 3);
      for (final name in ['a', 'b', 'c', 'd', 'e']) {
        await s.write(key(name), _page([name]), now, owner: 'o');
      }
      expect(await s.debugIndexedBytes(), lessThanOrEqualTo(one * 3));
      await expectIndexMatchesDisk(s);
      expect((await s.readMany([key('d'), key('e')], owner: 'o')).keys, [
        key('d'),
        key('e'),
      ]);
    });

    test('another owner never sees, and wipes, the pages', () async {
      final s = store();
      await s.write(key('a'), _page(['a']), now, owner: 'alice');
      expect(await s.readMany([key('a')], owner: 'bob'), isEmpty);
      expect(await filesOnDisk(), isEmpty);
      // Even across a restart, the files are gone.
      expect(await store().readMany([key('a')], owner: 'alice'), isEmpty);
    });

    test('a damaged page is dropped, not shown', () async {
      final s = store();
      await s.write(key('a'), _page(['a']), now, owner: 'o');
      final name = '${key('a')}.json';
      await File('${dir.path}/$name').writeAsString('{not json');

      final reopened = store();
      expect(await reopened.readMany([key('a')], owner: 'o'), isEmpty);
      await expectIndexMatchesDisk(reopened);
      expect(await filesOnDisk(), isEmpty);
    });

    test('a half-written page from a crash is cleaned up', () async {
      await store().write(key('a'), _page(['a']), now, owner: 'o');
      await File('${dir.path}/${key('b')}.json.tmp').writeAsString('{');

      final reopened = store();
      await reopened.readMany([key('a')], owner: 'o');
      // The folder scan runs right after the first read answers.
      await expectIndexMatchesDisk(reopened);
      final leftovers = [
        await for (final entity in dir.list())
          if (entity.path.endsWith('.tmp')) entity,
      ];
      expect(leftovers, isEmpty);
    });

    test('the first read after a restart does not wait for the folder scan',
        () async {
      final s = store(maxPages: 100);
      for (final name in ['a', 'b', 'c', 'd']) {
        await s.write(key(name), _page([name]), now, owner: 'o');
      }

      // A restart onto a folder whose scan cannot finish until released.
      final scan = Completer<void>();
      final events = <String>[];
      final reopened = FileExplorerGamesDiskStore(
        directory: () async => _ScanGatedDirectory(dir, scan.future, events),
        maxPages: 100,
        now: () => now,
      );
      final found = await reopened.readMany([
        key('b'),
        key('missing'),
      ], owner: 'o');
      events.add('answered');

      // Answered by name, with the scan still held behind it.
      expect(found.keys, [key('b')]);
      expect(found[key('b')]!.response.data.single['id'], 'b');
      expect(scan.isCompleted, isFalse);

      scan.complete();
      await expectIndexMatchesDisk(reopened);
      expect(events.where((e) => e == 'scan'), hasLength(1));
    });

    test('a page read before the scan counts as recently used after it',
        () async {
      final s = store(maxPages: 2);
      await s.write(key('a'), _page(['a']), now, owner: 'o');
      now = now.add(const Duration(seconds: 1));
      await s.write(key('b'), _page(['b']), now, owner: 'o');

      // After a restart, `a` (the older file) is the first page read.
      final reopened = store(maxPages: 2);
      await reopened.readMany([key('a')], owner: 'o');
      await reopened.write(key('c'), _page(['c']), now, owner: 'o');

      // So `b` is the one evicted, not the page just read.
      expect(
        (await reopened.readMany([key('a'), key('b'), key('c')], owner: 'o'))
            .keys,
        [key('a'), key('c')],
      );
      await expectIndexMatchesDisk(reopened);
    });
  });

  group('cache with a disk', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('explorer_games_cache');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    FileExplorerGamesDiskStore store() =>
        FileExplorerGamesDiskStore(directory: () async => dir);

    test('a first page fetched in one session paints the next one', () async {
      final repo = _Repo();
      final first = ExplorerGamesCache(
        repository: () => repo,
        disk: store(),
        currentUserId: () => 'u',
      );
      final fetched = await first.fetch(_query(uci: 'd7d6'));
      await first.debugDiskIdle();

      // A new app launch: new cache, new store object, same folder.
      final next = ExplorerGamesCache(
        repository: () => repo,
        disk: store(),
        currentUserId: () => 'u',
      );
      expect(next.peek(_query(uci: 'd7d6')), isNull);
      await next.preload([_query(uci: 'd7d6')]);
      final snapshot = next.peek(_query(uci: 'd7d6'));
      expect(snapshot, isNotNull);
      expect(snapshot!.source, ExplorerGamesSource.disk);
      expect(snapshot.response.data, fetched.data);
      // A saved page is never current: it has no server answer behind it.
      expect(next.isFresh(snapshot.response), isFalse);
      expect(repo.calls, 1);
    });

    test('signing out empties memory and disk', () async {
      var user = 'alice';
      final disk = store();
      final cache = ExplorerGamesCache(
        repository: _Repo.new,
        disk: disk,
        currentUserId: () => user,
      );
      await cache.fetch(_query(uci: 'd7d6'));
      await cache.debugDiskIdle();
      expect(await disk.debugIndexedFiles(), hasLength(1));

      user = '';
      cache.handleAccountChange();
      await cache.debugDiskIdle();

      expect(cache.peek(_query(uci: 'd7d6')), isNull);
      expect(await disk.debugIndexedFiles(), isEmpty);
      final pages = [
        await for (final entity in dir.list())
          if (entity.path.endsWith('.json')) entity,
      ];
      expect(pages, isEmpty);
    });

    test('another account never gets the previous account\'s pages', () async {
      var user = 'alice';
      final cache = ExplorerGamesCache(
        repository: _Repo.new,
        disk: store(),
        currentUserId: () => user,
      );
      await cache.fetch(_query(uci: 'd7d6'));
      await cache.debugDiskIdle();

      // No auth event at all: the next call notices the account itself.
      user = 'bob';
      expect(cache.peek(_query(uci: 'd7d6')), isNull);
      await cache.preload([_query(uci: 'd7d6')]);
      expect(cache.peek(_query(uci: 'd7d6')), isNull);

      // And a fresh launch as bob finds nothing of alice's on disk.
      final relaunch = ExplorerGamesCache(
        repository: _Repo.new,
        disk: store(),
        currentUserId: () => 'bob',
      );
      await relaunch.preload([_query(uci: 'd7d6')]);
      expect(relaunch.peek(_query(uci: 'd7d6')), isNull);
    });

    test(
      'a page fetched for the old account is not saved for the new one',
      () async {
        var user = 'alice';
        final repo = _Repo()..gate = Completer<void>();
        final disk = store();
        final cache = ExplorerGamesCache(
          repository: () => repo,
          disk: disk,
          currentUserId: () => user,
        );
        final pending = cache.fetch(_query(uci: 'd7d6'));
        user = 'bob';
        cache.handleAccountChange();
        repo.gate!.complete();
        await pending;
        await cache.debugDiskIdle();

        expect(cache.peek(_query(uci: 'd7d6')), isNull);
        expect(await disk.debugIndexedFiles(), isEmpty);
      },
    );
  });
}

class _FailingRepo extends GamebaseRepository {
  _FailingRepo() : super(Dio(), apiKey: 'test');

  @override
  Future<GamebaseSearchQueryResponse> getPositionGames({
    required String fen,
    List<String> moves = const [],
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) async => throw Exception('backend down');
}

/// The cache folder, except that listing it (the index scan) waits for
/// [scan] and is recorded in [events].
class _ScanGatedDirectory implements Directory {
  _ScanGatedDirectory(this._inner, this._scan, this._events);

  final Directory _inner;
  final Future<void> _scan;
  final List<String> _events;

  @override
  String get path => _inner.path;

  @override
  Future<Directory> create({bool recursive = false}) async {
    await _inner.create(recursive: recursive);
    return this;
  }

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    _events.add('scan');
    await _scan;
    yield* _inner.list(recursive: recursive, followLinks: followLinks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
