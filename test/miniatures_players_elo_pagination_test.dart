import 'dart:async';
import 'dart:io';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory high-ELO source that mirrors Favorites ranking semantics:
/// rating > 0, rating < 3300, rating desc, offset/limit range.
class _FakeChessPlayerRepository extends ChessPlayerRepository {
  _FakeChessPlayerRepository(this._players);

  final List<ChessPlayer> _players;

  List<ChessPlayer> _filtered({
    String? search,
    Iterable<String>? titles,
  }) {
    var list =
        _players
            .where((p) {
              final r = p.rating;
              return r != null && r > 0 && r < 3300;
            })
            .toList()
          ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));

    final titleSet =
        titles
            ?.map((t) => t.trim().toUpperCase())
            .where((t) => t.isNotEmpty)
            .toSet();
    if (titleSet != null && titleSet.isNotEmpty) {
      list =
          list
              .where(
                (p) =>
                    p.title != null && titleSet.contains(p.title!.toUpperCase()),
              )
              .toList();
    }

    final q = (search ?? '').trim().toLowerCase();
    if (q.isNotEmpty) {
      list =
          list
              .where(
                (p) =>
                    p.name.toLowerCase().contains(q) ||
                    (p.title?.toLowerCase().contains(q) ?? false),
              )
              .toList();
    }
    return list;
  }

  @override
  Future<List<ChessPlayer>> getTopPlayers({
    int limit = 30,
    int offset = 0,
    Iterable<String>? titles,
  }) async {
    final list = _filtered(titles: titles);
    return list.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<List<ChessPlayer>> searchAllPlayers({
    required String query,
    int limit = 30,
    int offset = 0,
    Iterable<String>? titles,
  }) async {
    final list = _filtered(search: query, titles: titles);
    return list.skip(offset).take(limit).toList(growable: false);
  }
}

ChessPlayer _p(int fideid, String name, int rating, {String? title}) {
  return ChessPlayer(
    fideid: fideid,
    name: name,
    rating: rating,
    title: title,
    country: 'NOR',
  );
}

List<ChessPlayer> _seedPlayers({int count = 45}) {
  // Strictly decreasing ratings so order is unambiguous.
  return List.generate(count, (i) {
    final rating = 2900 - i;
    return _p(1000 + i, 'Player $i', rating, title: i % 3 == 0 ? 'GM' : 'IM');
  });
}

/// In-memory gamebase leaderboard so W-L lookups never hit the network.
///
/// [searches] records every name search so a test can prove how many went out,
/// and [gate] holds them open to prove the list paints without waiting.
class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository([this._records = const []])
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final List<MiniaturePlayer> _records;
  final List<String> searches = <String>[];
  Completer<void>? gate;

  @override
  Future<MiniaturePlayersPage> getMiniaturePlayers({
    MiniatureGamesWindow window = MiniatureGamesWindow.all,
    MiniaturePlayerSort sort = MiniaturePlayerSort.games,
    Set<MiniaturePlayerTitle> titles = const {},
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    searches.add(search ?? '');
    final pending = gate;
    if (pending != null) await pending.future;
    final q = (search ?? '').trim().toLowerCase();
    final items =
        q.isEmpty
            ? _records
            : _records
                .where((r) {
                  if (r.name.toLowerCase().contains(q)) return true;
                  // Mirrors gamebase: pure-numeric queries also match fide_id.
                  final fide = r.fideId?.toString();
                  return fide != null && fide == q;
                })
                .toList(growable: false);
    final page = items.skip(offset).take(limit).toList(growable: false);
    return MiniaturePlayersPage(
      items: page,
      total: items.length,
      limit: limit,
      offset: offset,
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      anonKey: 'placeholder-anon-key',
    );
  });

  setUp(clearMiniaturePlayerRecordCacheForTest);

  group('chessPlayerToStandingModel', () {
    test('maps rating into score and fide id for FigmaPlayerCard', () {
      final standing = chessPlayerToStandingModel(
        _p(1503014, 'Carlsen, Magnus', 2839, title: 'GM'),
      );
      expect(standing.fideId, 1503014);
      expect(standing.name, 'Carlsen, Magnus');
      expect(standing.score, 2839);
      expect(standing.title, 'GM');
      expect(standing.matchScore, isNull);
      expect(standing.scoreChange, 0);
    });
  });

  group('matchMiniaturePlayerRecord', () {
    MiniaturePlayer mini(
      String name, {
      int? fideId,
      int wins = 0,
      int losses = 0,
    }) {
      return MiniaturePlayer(
        playerId: 'p-$name',
        name: name,
        games: wins + losses,
        wins: wins,
        losses: losses,
        fideId: fideId,
      );
    }

    test('matches on fide id even when the name text differs', () {
      final record = matchMiniaturePlayerRecord(
        candidates: [
          mini('Carlsen,M', fideId: 1503014, wins: 12, losses: 4),
          mini('Carlsen, Magnus', fideId: 99, wins: 1, losses: 1),
        ],
        fideId: 1503014,
        name: 'Carlsen, Magnus',
      );
      expect(record?.winLossLabel, '12W-4L');
      // The scorecard screen loads games by gamebase player id, so the row
      // itself must survive the lookup, not just its W-L counts.
      expect(record?.playerId, 'p-Carlsen,M');
    });

    test('never adopts a namesake record when fide ids disagree', () {
      final record = matchMiniaturePlayerRecord(
        candidates: [mini('Carlsen, Magnus', fideId: 12345, wins: 9, losses: 2)],
        fideId: 1503014,
        name: 'Carlsen, Magnus',
      );
      expect(record, isNull);
    });

    test('falls back to an exact name match only when the row has no fide id', () {
      final record = matchMiniaturePlayerRecord(
        candidates: [mini('carlsen, magnus', wins: 3, losses: 5)],
        fideId: 1503014,
        name: 'Carlsen, Magnus',
      );
      expect(record?.winLossLabel, '3W-5L');
    });

    test('empty leaderboard page resolves to no record', () {
      expect(
        matchMiniaturePlayerRecord(
          candidates: const [],
          fideId: 1503014,
          name: 'Carlsen, Magnus',
        ),
        isNull,
      );
    });
  });

  group('mergeMiniaturePlayersPage', () {
    PlayerStandingModel standing(int rankRating, String name) {
      return PlayerStandingModel(
        countryCode: 'NO',
        name: name,
        score: rankRating,
        scoreChange: 0,
        matchScore: null,
        fideId: rankRating,
      );
    }

    test('page 0 replaces list and keeps rating-desc order', () {
      final page = [
        standing(2900, 'A'),
        standing(2899, 'B'),
        standing(2898, 'C'),
      ];
      final next = mergeMiniaturePlayersPage(
        previous: const MiniaturePlayersState(isLoading: true),
        page: page,
        reset: true,
        pageSize: 20,
      );
      expect(next.items.map((p) => p.score).toList(), [2900, 2899, 2898]);
      expect(next.hasMore, isFalse); // short page
      expect(next.isLoading, isFalse);
    });

    test('full first page sets hasMore true', () {
      final page = List.generate(
        20,
        (i) => standing(2900 - i, 'P$i'),
      );
      final next = mergeMiniaturePlayersPage(
        previous: const MiniaturePlayersState(),
        page: page,
        reset: true,
        pageSize: 20,
      );
      expect(next.items, hasLength(20));
      expect(next.hasMore, isTrue);
    });

    test('page N appends without reordering prior rows', () {
      final page0 = List.generate(20, (i) => standing(2900 - i, 'P$i'));
      final after0 = mergeMiniaturePlayersPage(
        previous: const MiniaturePlayersState(),
        page: page0,
        reset: true,
        pageSize: 20,
      );
      final page1 = List.generate(5, (i) => standing(2880 - i, 'Q$i'));
      final after1 = mergeMiniaturePlayersPage(
        previous: after0,
        page: page1,
        reset: false,
        pageSize: 20,
      );

      expect(after1.items, hasLength(25));
      // Prior page untouched and still first.
      expect(after1.items.take(20).map((p) => p.name).toList(), page0.map((p) => p.name).toList());
      expect(after1.items.skip(20).map((p) => p.name).toList(), [
        'Q0',
        'Q1',
        'Q2',
        'Q3',
        'Q4',
      ]);
      // Overall still rating-desc (seed ratings were descending across pages).
      final scores = after1.items.map((p) => p.score).toList();
      expect(scores, List<int>.from(scores)..sort((a, b) => b.compareTo(a)));
      expect(after1.hasMore, isFalse);
    });
  });

  group('per-row W-L resolution', () {
    MiniaturePlayer carlsen() => const MiniaturePlayer(
      playerId: 'gb-carlsen',
      name: 'Carlsen, Magnus',
      games: 16,
      wins: 12,
      losses: 4,
      fideId: 1503014,
    );

    test('resolve attaches W-L, caches the hit, and caches the miss', () async {
      final repo = _FakeGamebaseRepository([carlsen()]);

      final hit = await resolveMiniaturePlayerRecord(
        repo: repo,
        fideId: 1503014,
        name: 'Carlsen, Magnus',
      );
      expect(hit?.winLossLabel, '12W-4L');
      expect(hit?.playerId, 'gb-carlsen');
      expect(cachedMiniaturePlayerRecord(1503014)?.playerId, 'gb-carlsen');

      // No gamebase row → a settled miss, so the score slot can stop
      // shimmering instead of retrying this player on every rebuild.
      final miss = await resolveMiniaturePlayerRecord(
        repo: repo,
        fideId: 99,
        name: 'Unknown, Player',
      );
      expect(miss, isNull);
      expect(hasResolvedMiniaturePlayerRecord(99), isTrue);
      expect(cachedMiniaturePlayerRecord(99), isNull);

      // Repeat asks are served from cache, not the network.
      final before = repo.searches.length;
      await resolveMiniaturePlayerRecord(
        repo: repo,
        fideId: 1503014,
        name: 'Carlsen, Magnus',
      );
      expect(repo.searches.length, before);
    });

    test('concurrent asks for one player share a single search', () async {
      final repo = _FakeGamebaseRepository([carlsen()])..gate = Completer<void>();

      // The row builds and a tap both want this record while it is in flight.
      final first = resolveMiniaturePlayerRecord(
        repo: repo,
        fideId: 1503014,
        name: 'Carlsen, Magnus',
      );
      final second = resolveMiniaturePlayerRecord(
        repo: repo,
        fideId: 1503014,
        name: 'Carlsen, Magnus',
      );
      repo.gate!.complete();
      final results = await Future.wait([first, second]);

      expect(results[0]?.playerId, 'gb-carlsen');
      expect(results[1]?.playerId, 'gb-carlsen');
      expect(repo.searches, hasLength(1));
    });

    test(
      'blank or PGN-style gamebase name still resolves via FIDE id first',
      () async {
        // Production failure modes while scrolling Miniatures → Players:
        // 1) player.name empty after partial FIDE ingest
        // 2) gamebase "Last,F" vs Supabase "Last, First" so name ILIKE misses
        // Resolve must hit fide_id search first, not depend on name shape.
        const blankName = MiniaturePlayer(
          playerId: 'gb-danya',
          name: '',
          games: 240,
          wins: 211,
          losses: 29,
          fideId: 2026961,
          rating: 2711,
          title: 'GM',
        );
        const pgnStyle = MiniaturePlayer(
          playerId: 'gb-hernando',
          name: 'Hernando Rodrigo,Ju',
          games: 107,
          wins: 54,
          losses: 53,
          fideId: 2208350,
          rating: 2471,
        );
        final blankRepo = _FakeGamebaseRepository([blankName]);
        final pgnRepo = _FakeGamebaseRepository([pgnStyle]);

        final blankHit = await resolveMiniaturePlayerRecord(
          repo: blankRepo,
          fideId: 2026961,
          name: 'Naroditsky, Daniel',
        );
        expect(blankHit?.playerId, 'gb-danya');
        expect(blankHit?.winLossLabel, '211W-29L');
        // FIDE id is tried first.
        expect(blankRepo.searches.first, '2026961');
        expect(blankRepo.searches, hasLength(1));

        final pgnHit = await resolveMiniaturePlayerRecord(
          repo: pgnRepo,
          fideId: 2208350,
          name: 'Hernando Rodrigo, Julio',
        );
        expect(pgnHit?.playerId, 'gb-hernando');
        expect(pgnHit?.winLossLabel, '54W-53L');
        expect(pgnRepo.searches, ['2208350']);
      },
    );

    test(
      'chessPlayerToStandingModel keeps classical 2700s rating on the card',
      () {
        final standing = chessPlayerToStandingModel(
          _p(2026961, 'Naroditsky, Daniel', 2711, title: 'GM'),
        );
        expect(standing.score, 2711);
        expect(standing.fideId, 2026961);
        expect(standing.title, 'GM');
      },
    );

    test('applyCachedMiniatureRecords seeds only what is already known', () async {
      final repo = _FakeGamebaseRepository([carlsen()]);
      await resolveMiniaturePlayerRecord(
        repo: repo,
        fideId: 1503014,
        name: 'Carlsen, Magnus',
      );

      final seeded = applyCachedMiniatureRecords([
        chessPlayerToStandingModel(
          _p(1503014, 'Carlsen, Magnus', 2839, title: 'GM'),
        ),
        chessPlayerToStandingModel(_p(2020009, 'Caruana, Fabiano', 2804)),
      ]);
      expect(seeded[0].matchScore, '12W-4L');
      expect(seeded[0].gamebasePlayerId, 'gb-carlsen');
      // Never looked up → left blank for the row to resolve, no extra request.
      expect(seeded[1].matchScore, isNull);
      expect(repo.searches, hasLength(1));
    });
  });

  group('MiniaturePlayersNotifier (Supabase high-ELO path)', () {
    Future<MiniaturePlayersState> waitUntil(
      ProviderContainer container, {
      required bool Function(MiniaturePlayersState) done,
    }) async {
      for (var i = 0; i < 50; i++) {
        final s = container.read(miniaturePlayersPaginatedProvider);
        if (done(s)) return s;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return container.read(miniaturePlayersPaginatedProvider);
    }

    ProviderContainer containerWith({
      required ChessPlayerRepository chess,
      GamebaseRepository? gamebase,
      MiniaturePlayersQuery? query,
    }) {
      return ProviderContainer(
        overrides: [
          chessPlayerRepositoryProvider.overrideWithValue(chess),
          gamebaseRepositoryProvider.overrideWithValue(
            gamebase ?? _FakeGamebaseRepository(),
          ),
          if (query != null)
            miniaturePlayersQueryProvider.overrideWith((ref) => query),
        ],
      );
    }

    test(
      'loads page 0 by rating desc, appends page 1, short page ends hasMore',
      () async {
        final fake = _FakeChessPlayerRepository(_seedPlayers(count: 45));
        final container = containerWith(chess: fake);
        addTearDown(container.dispose);
        // Keep autoDispose providers alive for the test.
        final sub = container.listen(
          miniaturePlayersPaginatedProvider,
          (_, __) {},
        );
        addTearDown(sub.close);

        final page0 = await waitUntil(
          container,
          done: (s) => !s.isLoading && s.items.isNotEmpty,
        );
        expect(page0.isLoading, isFalse);
        expect(page0.items, hasLength(MiniaturePlayersNotifier.pageSize));
        expect(page0.hasMore, isTrue);

        final scores0 = page0.items.map((p) => p.score).toList();
        expect(
          scores0,
          List<int>.from(scores0)..sort((a, b) => b.compareTo(a)),
          reason: 'page 0 must be rating descending',
        );
        expect(scores0.first, 2900);
        expect(scores0.last, 2900 - (MiniaturePlayersNotifier.pageSize - 1));

        // Page 1 append.
        await container
            .read(miniaturePlayersPaginatedProvider.notifier)
            .loadNextPage();
        final page1 = await waitUntil(
          container,
          done:
              (s) =>
                  !s.isLoading &&
                  s.items.length > MiniaturePlayersNotifier.pageSize,
        );
        expect(page1.items, hasLength(40));
        expect(page1.hasMore, isTrue);
        // Prior rows preserved in order.
        expect(page1.items.take(20).map((p) => p.score).toList(), scores0);
        expect(page1.items[20].score, 2900 - 20);

        // Final short page.
        await container
            .read(miniaturePlayersPaginatedProvider.notifier)
            .loadNextPage();
        final page2 = await waitUntil(
          container,
          done: (s) => !s.isLoading && s.items.length == 45,
        );
        expect(page2.items, hasLength(45));
        expect(page2.hasMore, isFalse);
        final allScores = page2.items.map((p) => p.score).toList();
        expect(
          allScores,
          List<int>.from(allScores)..sort((a, b) => b.compareTo(a)),
        );
      },
    );

    List<MiniaturePlayer> twoRecords() => const [
      MiniaturePlayer(
        playerId: 'gb-m',
        name: 'Carlsen, Magnus',
        games: 16,
        wins: 12,
        losses: 4,
        fideId: 1503014,
      ),
      MiniaturePlayer(
        playerId: 'gb-f',
        name: 'Caruana, Fabiano',
        games: 7,
        wins: 5,
        losses: 2,
        fideId: 2020009,
      ),
    ];

    _FakeChessPlayerRepository twoPlayers() => _FakeChessPlayerRepository([
      _p(1503014, 'Carlsen, Magnus', 2839, title: 'GM'),
      _p(2020009, 'Caruana, Fabiano', 2804, title: 'GM'),
    ]);

    test('page paints without waiting on any gamebase W-L lookup', () async {
      // Gate every gamebase search open: if first paint were still gated on
      // enrichment, the list would never leave shimmer here.
      final gamebase = _FakeGamebaseRepository(twoRecords())
        ..gate = Completer<void>();
      final container = containerWith(chess: twoPlayers(), gamebase: gamebase);
      addTearDown(container.dispose);
      final sub = container.listen(
        miniaturePlayersPaginatedProvider,
        (_, __) {},
      );
      addTearDown(sub.close);

      final state = await waitUntil(
        container,
        done: (s) => !s.isLoading && s.items.isNotEmpty,
      );
      expect(state.items.map((p) => p.name).toList(), [
        'Carlsen, Magnus',
        'Caruana, Fabiano',
      ]);
      // W-L is left to the rows that are actually on screen, so the ranking
      // page itself sends no name searches at all.
      expect(gamebase.searches, isEmpty);
      expect(state.items.every((p) => p.matchScore == null), isTrue);
      gamebase.gate!.complete();
    });

    test('a revisited page paints its W-L from the session cache', () async {
      final gamebase = _FakeGamebaseRepository(twoRecords());
      final container = containerWith(chess: twoPlayers(), gamebase: gamebase);
      addTearDown(container.dispose);
      final sub = container.listen(
        miniaturePlayersPaginatedProvider,
        (_, __) {},
      );
      addTearDown(sub.close);

      await waitUntil(container, done: (s) => !s.isLoading && s.items.isNotEmpty);

      // Stand in for the two visible rows resolving their own records.
      for (final row in container.read(miniaturePlayersPaginatedProvider).items) {
        await resolveMiniaturePlayerRecord(
          repo: gamebase,
          fideId: row.fideId!,
          name: row.name,
        );
      }
      final searchesAfterRows = gamebase.searches.length;

      await container.read(miniaturePlayersPaginatedProvider.notifier).refresh();
      final state = await waitUntil(
        container,
        done: (s) => !s.isLoading && s.items.first.matchScore != null,
      );
      expect(state.items.map((p) => p.matchScore).toList(), [
        '12W-4L',
        '5W-2L',
      ]);
      expect(state.items.map((p) => p.gamebasePlayerId).toList(), [
        'gb-m',
        'gb-f',
      ]);
      // Cached, so the refresh re-sent nothing to gamebase.
      expect(gamebase.searches.length, searchesAfterRows);
    });

    test('search still ranks by rating desc with pagination', () async {
      final fake = _FakeChessPlayerRepository([
        _p(1, 'Carlsen, Magnus', 2839, title: 'GM'),
        _p(2, 'Caruana, Fabiano', 2804, title: 'GM'),
        _p(3, 'Nakamura, Hikaru', 2802, title: 'GM'),
        _p(4, 'Carlson, Bob', 2100, title: 'FM'),
        _p(5, 'Someone Else', 2700, title: 'IM'),
      ]);
      final container = containerWith(
        chess: fake,
        query: const MiniaturePlayersQuery(search: 'Carl'),
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        miniaturePlayersPaginatedProvider,
        (_, __) {},
      );
      addTearDown(sub.close);

      final state = await waitUntil(
        container,
        done: (s) => !s.isLoading,
      );
      expect(state.error, isNull);
      // "Carl" matches Carlsen + Carlson only (not Caruana). Still rating desc.
      expect(state.items.map((p) => p.name).toList(), [
        'Carlsen, Magnus',
        'Carlson, Bob',
      ]);
      expect(state.items.map((p) => p.score).toList(), [2839, 2100]);
      expect(state.hasMore, isFalse);
    });
  });

  group('source path static checks', () {
    test(
      'miniatures players provider source uses chessPlayerRepository + getTopPlayers',
      () {
        // Structural guard on the shipped file: ranking is Supabase high-ELO.
        // Gamebase is only consulted to attach W-L after that ranking page.
        final source = File(
          'lib/screens/library/providers/miniatures_provider.dart',
        ).readAsStringSync();
        expect(source, contains('chessPlayerRepositoryProvider'));
        expect(source, contains('getTopPlayers'));
        expect(source, contains('searchAllPlayers'));
        expect(source, contains('mergeMiniaturePlayersPage'));
        expect(source, contains('applyCachedMiniatureRecords'));
        expect(source, contains('miniaturePlayerRecordProvider'));

        // Slice exactly the players notifier: the file also holds the games
        // notifier, which legitimately talks to gamebase.
        final rankingStart = source.indexOf('class MiniaturePlayersNotifier');
        final rankingEnd = source.indexOf('\nclass ', rankingStart + 1);
        final rankingPath = source.substring(
          rankingStart,
          rankingEnd == -1 ? source.length : rankingEnd,
        );
        // Rank order still comes from chess players, not gamebase sort.
        expect(rankingPath, contains('chessPlayerRepositoryProvider'));
        expect(rankingPath, isNot(contains('sort: _query.sort')));
        // First paint must never be gated on the gamebase W-L lookups: the
        // ranking page paints, then rows resolve their own record. Awaiting a
        // gamebase call in this path is exactly the regression to catch.
        expect(rankingPath, isNot(contains('await enrich')));
        expect(rankingPath, isNot(contains('gamebaseRepositoryProvider')));

        final tabSource = File(
          'lib/screens/library/miniatures/miniatures_players_tab.dart',
        ).readAsStringSync();
        expect(tabSource, contains('FigmaPlayerCard'));
        expect(tabSource, contains('rank: index + 1'));
        // Tap opens the miniature scorecard, with the full profile only as
        // the fallback for players gamebase has no row for.
        expect(tabSource, contains('MiniaturePlayerScorecardScreen'));
        expect(tabSource, contains('PlayerProfileScreen'));
      },
    );
  });
}

