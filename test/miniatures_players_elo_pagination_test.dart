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

/// In-memory gamebase leaderboard so page enrichment never hits the network.
class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository([this._records = const []])
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final List<MiniaturePlayer> _records;

  @override
  Future<MiniaturePlayersPage> getMiniaturePlayers({
    MiniatureGamesWindow window = MiniatureGamesWindow.all,
    MiniaturePlayerSort sort = MiniaturePlayerSort.games,
    Set<MiniaturePlayerTitle> titles = const {},
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final q = (search ?? '').trim().toLowerCase();
    final items =
        q.isEmpty
            ? _records
            : _records
                .where((r) => r.name.toLowerCase().contains(q))
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

  group('enrichPlayersWithMiniatureRecords', () {
    test('attaches W-L and gamebase id before cards would paint', () async {
      final repo = _FakeGamebaseRepository([
        const MiniaturePlayer(
          playerId: 'gb-carlsen',
          name: 'Carlsen, Magnus',
          games: 16,
          wins: 12,
          losses: 4,
          fideId: 1503014,
        ),
      ]);
      final enriched = await enrichPlayersWithMiniatureRecords(
        repo: repo,
        players: [
          chessPlayerToStandingModel(
            _p(1503014, 'Carlsen, Magnus', 2839, title: 'GM'),
          ),
          chessPlayerToStandingModel(_p(99, 'Unknown, Player', 2500)),
        ],
      );
      expect(enriched[0].matchScore, '12W-4L');
      expect(enriched[0].gamebasePlayerId, 'gb-carlsen');
      // No gamebase row → score slot stays empty rather than inventing zeros.
      expect(enriched[1].matchScore, isNull);
      expect(enriched[1].gamebasePlayerId, isNull);
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

    test('first ready page already carries prefetched W-L labels', () async {
      final chess = _FakeChessPlayerRepository([
        _p(1503014, 'Carlsen, Magnus', 2839, title: 'GM'),
        _p(2020009, 'Caruana, Fabiano', 2804, title: 'GM'),
      ]);
      final gamebase = _FakeGamebaseRepository([
        const MiniaturePlayer(
          playerId: 'gb-m',
          name: 'Carlsen, Magnus',
          games: 16,
          wins: 12,
          losses: 4,
          fideId: 1503014,
        ),
        const MiniaturePlayer(
          playerId: 'gb-f',
          name: 'Caruana, Fabiano',
          games: 7,
          wins: 5,
          losses: 2,
          fideId: 2020009,
        ),
      ]);
      final container = containerWith(chess: chess, gamebase: gamebase);
      addTearDown(container.dispose);
      final sub = container.listen(
        miniaturePlayersPaginatedProvider,
        (_, __) {},
      );
      addTearDown(sub.close);

      // isLoading stays true until W-L enrichment finishes — the UI keeps
      // shimmer cards for that whole window so W-L never pops in later.
      final early = container.read(miniaturePlayersPaginatedProvider);
      expect(early.isLoading, isTrue);
      expect(early.items, isEmpty);

      final state = await waitUntil(
        container,
        done: (s) => !s.isLoading && s.items.isNotEmpty,
      );
      expect(state.items.map((p) => p.matchScore).toList(), [
        '12W-4L',
        '5W-2L',
      ]);
      expect(state.items.map((p) => p.gamebasePlayerId).toList(), [
        'gb-m',
        'gb-f',
      ]);
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
        expect(source, contains('enrichPlayersWithMiniatureRecords'));
        expect(source, contains('miniaturePlayerRecordProvider'));

        final rankingPath = source.substring(
          source.indexOf('class MiniaturePlayersNotifier'),
        );
        // Rank order still comes from chess players, not gamebase sort.
        expect(rankingPath, contains('chessPlayerRepositoryProvider'));
        expect(rankingPath, contains('enrichPlayersWithMiniatureRecords'));
        expect(rankingPath, isNot(contains('sort: _query.sort')));

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

