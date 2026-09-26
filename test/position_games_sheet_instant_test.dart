import 'dart:async';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_games_cache.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_games_prefetch.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/widgets/position_games_sheet.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The games sheet opens on rows in its first frame whenever the explorer
/// already holds its first page, and a saved page is only ever shown as a
/// copy being checked: never final, never paged on top of, never able to
/// change which game a tap opens.

const _fen =
    'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R b KQkq - 3 5';
const _moves = <String>[
  'e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6', 'd2d3', 'f8c5', 'b1c3', //
];
const _filters = GamebaseFilters(minRating: 2400, isOnline: false);

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

List<String> _ids(String prefix, [int count = 20]) => [
  for (var i = 1; i <= count; i++) '$prefix$i',
];

/// A scripted backend: each request takes the next scripted answer for its
/// page (or a default), optionally held behind a gate.
class _Repo extends GamebaseRepository {
  _Repo() : super(Dio(), apiKey: 'test', baseUrl: 'https://example.test');

  final List<String> requests = <String>[];
  final Map<int, List<Object>> script = <int, List<Object>>{};
  Completer<void>? gate;
  GamebaseSearchQueryResponse Function(int pageNumber) fallback =
      (pageNumber) => _page(_ids('p$pageNumber-'), pageNumber: pageNumber);

  /// Arguments of the last FEN request.
  Map<String, Object?>? lastFenRequest;

  /// One-shot, per page: the next request for that page gets its answer as
  /// the server's list stands when it is sent, then waits here, like a slow
  /// request on the wire while new games land.
  final Map<int, Completer<void>> pageGates = <int, Completer<void>>{};

  Future<GamebaseSearchQueryResponse> _answer(int pageNumber) async {
    final held = gate;
    if (held != null) await held.future;
    final queued = script[pageNumber];
    final next = (queued != null && queued.isNotEmpty)
        ? queued.removeAt(0)
        : null;
    final Object answer = next ?? fallback(pageNumber);
    final onTheWire = pageGates.remove(pageNumber);
    if (onTheWire != null) await onTheWire.future;
    if (answer is Exception) throw answer;
    return answer as GamebaseSearchQueryResponse;
  }

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
  }) {
    requests.add('games|$uci|$pageNumber|$pageSize');
    return _answer(pageNumber);
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
  }) {
    requests.add('fen|$uci|$pageNumber|$pageSize');
    lastFenRequest = <String, Object?>{
      'fen': fen,
      'uci': uci,
      'minRating': minRating,
      'isOnline': isOnline,
      'sortBy': sortBy,
      'sortDirection': sortDirection,
      'notationPlies': notationPlies,
      'pageNumber': pageNumber,
      'pageSize': pageSize,
    };
    return _answer(pageNumber);
  }
}

/// Saved pages "from an earlier session", served from memory.
class _Disk implements ExplorerGamesDiskStore {
  final Map<String, ExplorerGamesSnapshot> pages = {};

  @override
  Future<Map<String, ExplorerGamesSnapshot>> readMany(
    List<String> keys, {
    required String owner,
  }) async => {
    for (final key in keys)
      if (pages[key] != null) key: pages[key]!,
  };

  @override
  Future<void> write(
    String key,
    GamebaseSearchQueryResponse response,
    DateTime fetchedAt, {
    required String owner,
  }) async {}

  @override
  Future<void> clear() async => pages.clear();
}

class _EngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async {
    const settings = EngineSettings(showEngineAnalysis: false);
    state = const AsyncValue.data(settings);
    return settings;
  }
}

ProviderContainer _container(_Repo repo, {_Disk? disk}) {
  final container = ProviderContainer(
    overrides: [
      gamebaseRepositoryProvider.overrideWithValue(repo),
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      if (disk != null) explorerGamesDiskStoreProvider.overrideWithValue(disk),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A container whose games cache reads the time from [now].
ProviderContainer _clockContainer(_Repo repo, DateTime Function() now) {
  final container = ProviderContainer(
    overrides: [
      gamebaseRepositoryProvider.overrideWithValue(repo),
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      explorerGamesCacheProvider.overrideWith((ref) {
        final cache = ExplorerGamesCache(
          repository: () => repo,
          currentUserId: () => 'u',
          now: now,
        );
        ref.onDispose(cache.dispose);
        return cache;
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Top edge of the first card on screen.
double _firstCardTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(LibraryGameCard).first).dy;

GamebasePositionGamesQuery _sheetQuery({String? uci, bool fen = false}) =>
    GamebasePositionGamesQuery.sheetPage(
      fen: _fen,
      filters: _filters,
      moves: _moves,
      uci: uci,
      useFenEndpoint: fen,
    );

Future<void> _pumpSheet(
  WidgetTester tester,
  ProviderContainer container, {
  String? uci,
  bool fen = false,
  List<String> moves = _moves,
  GamebaseGameOpener opener = openGamebaseGame,
  String title = 'Games',
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: Scaffold(
                body: SizedBox(
                  height: 900,
                  child: PositionGamesSheet(
                    fen: _fen,
                    moves: moves,
                    uci: uci,
                    filters: _filters,
                    useFenEndpoint: fen,
                    title: title,
                    openGame: opener,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// [text] as the reader sees it: painted and reachable, not merely laid out
/// (the header lays out both of its saved-copy states and shows one).
Finder _visible(String text) => find.text(text).hitTestable();

/// The ids of the cards on screen, top to bottom.
List<String> _shownIds(WidgetTester tester) => [
  for (final card in tester.widgetList<LibraryGameCard>(
    find.byType(LibraryGameCard),
  ))
    card.game.gameId,
];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -6000));
  await _settle(tester);
}

/// Puts a page "saved by an earlier session" where the sheet will find it.
Future<void> _saveEarlier(
  WidgetTester tester,
  ProviderContainer container,
  _Disk disk,
  GamebasePositionGamesQuery query,
  GamebaseSearchQueryResponse response, {
  Duration age = const Duration(days: 3),
}) async {
  final cache = container.read(explorerGamesCacheProvider);
  disk.pages[cache.keyFor(query)] = ExplorerGamesSnapshot(
    response: response,
    fetchedAt: DateTime.now().subtract(age),
    source: ExplorerGamesSource.disk,
  );
  unawaited(cache.preload([query]));
  await _settle(tester);
  expect(cache.peek(query)?.source, ExplorerGamesSource.disk);
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
}

void main() {
  group('first frame', () {
    for (final entry in <String, ({String? uci, bool fen, List<String> moves})>{
      'a move row': (uci: 'd7d6', fen: false, moves: _moves),
      "the '∑' row": (uci: null, fen: false, moves: _moves),
      // Reached through a different line: the FEN sheet shares one entry.
      "an exact-FEN 'View all'": (
        uci: null,
        fen: true,
        moves: const ['e2e4', 'e7e5'],
      ),
    }.entries) {
      testWidgets('${entry.key}: a warmed sheet paints rows, asks nothing', (
        tester,
      ) async {
        final repo = _Repo();
        final container = _container(repo);
        container.read(explorerGamesPrefetchProvider).warm([
          _sheetQuery(uci: entry.value.uci, fen: entry.value.fen),
        ]);
        await _settle(tester);
        expect(repo.requests, hasLength(1));

        await _pumpSheet(
          tester,
          container,
          uci: entry.value.uci,
          fen: entry.value.fen,
          moves: entry.value.moves,
        );

        // One frame: rows, no spinner, and no request of the sheet's own.
        expect(_shownIds(tester), isNotEmpty);
        expect(find.text('Searching'), findsNothing);
        expect(repo.requests, hasLength(1));
        await _tearDown(tester);
      });
    }

    testWidgets('with nothing held, the sheet waits for the server', (
      tester,
    ) async {
      final repo = _Repo()..gate = Completer<void>();
      final container = _container(repo);

      await _pumpSheet(tester, container, uci: 'd7d6');
      expect(_shownIds(tester), isEmpty);
      expect(find.text('Searching'), findsOneWidget);

      repo.gate!.complete();
      await _settle(tester);
      expect(_shownIds(tester).first, 'p0-1');
      expect(repo.requests, ['games|d7d6|0|20']);
      await _tearDown(tester);
    });

    testWidgets('the exact-FEN sheet sends the request it always sent', (
      tester,
    ) async {
      final repo = _Repo();
      final container = _container(repo);

      await _pumpSheet(tester, container, fen: true);
      await _settle(tester);

      expect(repo.requests, ['fen|null|0|20']);
      expect(repo.lastFenRequest, <String, Object?>{
        'fen': _fen,
        'uci': null,
        'minRating': 2400,
        'isOnline': false,
        'sortBy': GamebaseSortField.date,
        'sortDirection': GamebaseSortDirection.desc,
        'notationPlies': 0,
        'pageNumber': 0,
        'pageSize': 20,
      });
      expect(_shownIds(tester).first, 'p0-1');
      await _tearDown(tester);
    });
  });

  group('saved first page', () {
    testWidgets(
      'paints at once, is replaced whole by the server rows, pages only after',
      (tester) async {
        final repo = _Repo()..gate = Completer<void>();
        final disk = _Disk();
        final container = _container(repo, disk: disk);
        final query = _sheetQuery(uci: 'd7d6');
        await _saveEarlier(tester, container, disk, query, _page(_ids('s')));
        repo.script[0] = [
          _page(['new', ..._ids('s', 19)]),
        ];

        await _pumpSheet(tester, container, uci: 'd7d6');
        // First frame: the saved rows, while the server is asked again.
        expect(_shownIds(tester).take(2), ['s1', 's2']);
        expect(repo.requests, ['games|d7d6|0|20']);

        // Paging waits for the current first page.
        await _scrollToEnd(tester);
        expect(find.text('Updating games...'), findsOneWidget);
        expect(repo.requests, ['games|d7d6|0|20']);

        repo.gate!.complete();
        await _settle(tester);
        await tester.drag(find.byType(ListView), const Offset(0, 6000));
        await _settle(tester);
        // The server's order, whole: the new game on top, the rest shifted.
        expect(_shownIds(tester).take(3), ['new', 's1', 's2']);

        // Now paging goes ahead, on the current first page's offsets.
        await _scrollToEnd(tester);
        expect(repo.requests.take(2), ['games|d7d6|0|20', 'games|d7d6|1|20']);
        await _tearDown(tester);
      },
    );

    testWidgets(
      'a failed refresh keeps the rows, says they are saved, holds paging',
      (tester) async {
        final repo = _Repo();
        final disk = _Disk();
        final container = _container(repo, disk: disk);
        final query = _sheetQuery(uci: 'd7d6');
        await _saveEarlier(tester, container, disk, query, _page(_ids('s')));
        repo.script[0] = [Exception('offline')];

        await _pumpSheet(tester, container, uci: 'd7d6');
        await _settle(tester);

        expect(_shownIds(tester).first, 's1');
        // The header offers a retry in the count's place, and no count.
        expect(_visible('Retry'), findsOneWidget);
        expect(_visible('Updating'), findsNothing);
        expect(_visible('20+ games'), findsNothing);
        expect(find.text('Failed to load games.'), findsNothing);

        // Never a live page 1 stacked on a week-old page 0. The end of the
        // list says how old the copy is.
        await _scrollToEnd(tester);
        expect(repo.requests, ['games|d7d6|0|20']);
        expect(
          find.text('Saved 3 days ago. Couldn’t refresh.'),
          findsOneWidget,
        );
        expect(find.text('Try again to load more'), findsOneWidget);

        // Back online: the retry lands the current page and paging resumes.
        await tester.tap(find.text('Retry'));
        await _settle(tester);
        expect(find.textContaining('Saved'), findsNothing);
        // A count again (the reader was already at the end, so page 1 has
        // followed the current page 0 in).
        expect(find.textContaining('+ games').hitTestable(), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, 6000));
        await _settle(tester);
        expect(_shownIds(tester).first, 'p0-1');
        await _scrollToEnd(tester);
        expect(repo.requests.take(3), [
          'games|d7d6|0|20', // failed
          'games|d7d6|0|20', // retried
          'games|d7d6|1|20', // and only then page 1
        ]);
        await _tearDown(tester);
      },
    );

    testWidgets('offline with nothing saved still says the load failed', (
      tester,
    ) async {
      final repo = _Repo();
      repo.script[0] = [Exception('offline')];
      final container = _container(repo);

      await _pumpSheet(tester, container, uci: 'd7d6');
      await _settle(tester);
      expect(find.textContaining('Failed to load games.'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('a page fetched over two minutes ago is re-asked, not final', (
      tester,
    ) async {
      final repo = _Repo();
      var now = DateTime(2026, 9, 26, 12);
      final container = ProviderContainer(
        overrides: [
          gamebaseRepositoryProvider.overrideWithValue(repo),
          engineSettingsProviderNew.overrideWith(_EngineSettings.new),
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
      // Held by the warm-up, so the provider still has the old answer.
      container.read(explorerGamesPrefetchProvider).warm([
        _sheetQuery(uci: 'd7d6'),
      ]);
      await _settle(tester);
      now = now.add(kExplorerGamesFreshFor + const Duration(seconds: 1));
      repo.script[0] = [
        _page(['fresh', ..._ids('p0-', 19)]),
      ];

      await _pumpSheet(tester, container, uci: 'd7d6');
      expect(_shownIds(tester).first, 'p0-1');
      await _settle(tester);
      expect(repo.requests, ['games|d7d6|0|20', 'games|d7d6|0|20']);
      expect(_shownIds(tester).first, 'fresh');
      await _tearDown(tester);
    });
  });

  group('saved copy status', () {
    testWidgets('checking, failing and retrying never move the rows', (
      tester,
    ) async {
      final repo = _Repo()..gate = Completer<void>();
      final disk = _Disk();
      final container = _container(repo, disk: disk);
      final query = _sheetQuery(uci: 'd7d6');
      await _saveEarlier(tester, container, disk, query, _page(_ids('s')));
      repo.script[0] = [Exception('offline'), Exception('still offline')];

      // Checking the saved copy: the header says so, in the count's place.
      await _pumpSheet(tester, container, uci: 'd7d6');
      await _settle(tester);
      expect(_shownIds(tester).first, 's1');
      expect(_visible('Updating'), findsOneWidget);
      final top = _firstCardTop(tester);

      // The check fails.
      repo.gate!.complete();
      await _settle(tester);
      expect(_visible('Retry'), findsOneWidget);
      expect(_visible('Updating'), findsNothing);
      expect(_firstCardTop(tester), top);

      // Retry while the server is slow: back to "Updating", in place.
      repo.gate = Completer<void>();
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(_visible('Updating'), findsOneWidget);
      expect(_visible('Retry'), findsNothing);
      expect(_firstCardTop(tester), top);

      // It fails again.
      repo.gate!.complete();
      await _settle(tester);
      expect(_visible('Retry'), findsOneWidget);
      expect(_firstCardTop(tester), top);

      // Back online: the current rows land exactly where the copy was.
      repo.gate = null;
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(_shownIds(tester).first, 'p0-1');
      expect(_visible('20+ games'), findsOneWidget);
      expect(_firstCardTop(tester), top);
      await _tearDown(tester);
    });

    // A long title beside the count slot, on a narrow phone and at larger
    // text sizes: the title keeps its lines and the rows keep their place
    // through checking, failing and retrying, and the header never overflows.
    for (final (width, scale) in const [
      (393.0, 1.0),
      (393.0, 1.3),
      (360.0, 1.0),
      (320.0, 1.3),
    ]) {
      testWidgets('$width wide at ${scale}x text: the header holds still', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1000);
        addTearDown(tester.view.reset);
        const title = 'Games for 12...Nxe4';
        final repo = _Repo()..gate = Completer<void>();
        final disk = _Disk();
        final container = _container(repo, disk: disk);
        final query = _sheetQuery(uci: 'd7d6');
        await _saveEarlier(tester, container, disk, query, _page(_ids('s')));
        repo.script[0] = [Exception('offline'), Exception('still offline')];

        await _pumpSheet(
          tester,
          container,
          uci: 'd7d6',
          title: title,
          textScale: scale,
        );
        await _settle(tester);
        expect(_visible('Updating'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final titleBox = tester.getRect(find.text(title));
        final top = _firstCardTop(tester);

        void expectHeldStill() {
          expect(tester.takeException(), isNull);
          expect(tester.getRect(find.text(title)), titleBox);
          expect(_firstCardTop(tester), top);
        }

        // The check fails.
        repo.gate!.complete();
        await _settle(tester);
        expect(_visible('Retry'), findsOneWidget);
        expectHeldStill();

        // Retried while the server is slow, then failing again.
        repo.gate = Completer<void>();
        await tester.tap(find.text('Retry'));
        await _settle(tester);
        expect(_visible('Updating'), findsOneWidget);
        expectHeldStill();
        repo.gate!.complete();
        await _settle(tester);
        expect(_visible('Retry'), findsOneWidget);
        expectHeldStill();

        // Back online: the server's answer (the same rows) takes over, and
        // the count takes the slot without moving anything.
        repo.gate = null;
        repo.fallback = (pageNumber) => _page(_ids('s'));
        await tester.tap(find.text('Retry'));
        await _settle(tester);
        expect(_visible('20+ games'), findsOneWidget);
        expect(_visible('Updating'), findsNothing);
        expectHeldStill();
        await _tearDown(tester);
      });
    }

    testWidgets('a short saved copy is never shown as the whole list', (
      tester,
    ) async {
      final repo = _Repo()..gate = Completer<void>();
      final disk = _Disk();
      final container = _container(repo, disk: disk);
      final query = _sheetQuery(uci: 'd7d6');
      await _saveEarlier(
        tester,
        container,
        disk,
        query,
        _page(['s1', 's2', 's3'], hasMore: false, totalCount: 3),
      );
      repo.script[0] = [
        _page(['new', 's1', 's2', 's3'], hasMore: false, totalCount: 4),
      ];

      await _pumpSheet(tester, container, uci: 'd7d6');
      await _settle(tester);
      expect(_shownIds(tester), ['s1', 's2', 's3']);
      // Neither the header nor the footer calls the copy final.
      expect(find.text('Updating'), findsOneWidget);
      expect(find.text('Updating games...'), findsOneWidget);
      expect(_visible('3 games'), findsNothing);
      expect(find.text('Loaded all 3 games'), findsNothing);

      repo.gate!.complete();
      await _settle(tester);
      expect(_shownIds(tester), ['new', 's1', 's2', 's3']);
      expect(_visible('4 games'), findsOneWidget);
      expect(find.text('Loaded all 4 games'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('a short saved copy that cannot refresh offers a retry', (
      tester,
    ) async {
      final repo = _Repo();
      final disk = _Disk();
      final container = _container(repo, disk: disk);
      final query = _sheetQuery(uci: 'd7d6');
      await _saveEarlier(
        tester,
        container,
        disk,
        query,
        _page(['s1', 's2', 's3'], hasMore: false, totalCount: 3),
      );
      repo.script[0] = [Exception('offline')];

      await _pumpSheet(tester, container, uci: 'd7d6');
      await _settle(tester);
      expect(_visible('Retry'), findsOneWidget);
      expect(_visible('3 games'), findsNothing);
      expect(find.text('Loaded all 3 games'), findsNothing);
      expect(
        find.text('Saved 3 days ago. Couldn’t refresh.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      await _tearDown(tester);
    });
  });

  group('paging', () {
    testWidgets(
      'reaching the end while the copy is checked pages on once it is current',
      (tester) async {
        final repo = _Repo()..gate = Completer<void>();
        final disk = _Disk();
        final container = _container(repo, disk: disk);
        final query = _sheetQuery(uci: 'd7d6');
        await _saveEarlier(tester, container, disk, query, _page(_ids('s')));
        // The server confirms the very rows on screen.
        repo.script[0] = [_page(_ids('s'))];

        await _pumpSheet(tester, container, uci: 'd7d6');
        await _scrollToEnd(tester);
        expect(find.text('Updating games...'), findsOneWidget);
        expect(repo.requests, ['games|d7d6|0|20']);

        // No further scroll: the reader is already at the end.
        repo.gate!.complete();
        await _settle(tester);
        expect(repo.requests, ['games|d7d6|0|20', 'games|d7d6|1|20']);
        await _tearDown(tester);
      },
    );

    testWidgets(
      'a later page held from before page 0 was asked again is asked again too',
      (tester) async {
        final repo = _Repo();
        var now = DateTime(2026, 9, 26, 12);
        final container = _clockContainer(repo, () => now);

        // 12:00 open; 12:01 scroll on to page 1; close.
        await _pumpSheet(tester, container, uci: 'd7d6');
        await _settle(tester);
        now = now.add(const Duration(minutes: 1));
        await _scrollToEnd(tester);
        expect(repo.requests, ['games|d7d6|0|20', 'games|d7d6|1|20']);
        await _tearDown(tester);

        // Live ingestion puts one game on top: every row shifts down by one.
        repo.fallback = (pageNumber) => switch (pageNumber) {
          0 => _page(['new', ..._ids('p0-', 19)]),
          1 => _page(['p0-20', ..._ids('p1-', 19)], pageNumber: 1),
          _ => _page(_ids('p$pageNumber-'), pageNumber: pageNumber),
        };

        // 12:02:30 reopen: page 0 is past fresh, asked again and replaced.
        now = DateTime(2026, 9, 26, 12, 2, 30);
        await _pumpSheet(tester, container, uci: 'd7d6');
        await _settle(tester);
        expect(repo.requests, hasLength(3));

        // 12:03:36 scroll on: the page 1 held from 12:01 predates this page
        // 0, so it is asked again rather than appended.
        now = DateTime(2026, 9, 26, 12, 3, 36);
        await _scrollToEnd(tester);
        expect(repo.requests, [
          'games|d7d6|0|20',
          'games|d7d6|1|20',
          'games|d7d6|0|20',
          'games|d7d6|1|20',
        ]);
        // The game pushed from page 0 onto page 1 is in the list.
        expect(find.text('White p0-20', skipOffstage: false), findsOneWidget);
        await _tearDown(tester);
      },
    );

    // A page 1 sent before page 0 was asked again, but landing after it,
    // answers for the older list. Compared by when each was asked for, it is
    // asked again, whether it lands before the reader scrolls on (A2) or
    // while they are waiting for it (A).
    for (final landsWhileWaiting in [false, true]) {
      testWidgets(
        landsWhileWaiting
            ? 'a slow page 1 from before page 0 is asked again when it lands'
            : 'a page 1 sent before page 0 but landing after it is asked again',
        (tester) async {
          final repo = _Repo();
          var now = DateTime(2026, 9, 26, 12);
          final container = _clockContainer(repo, () => now);

          // 12:00:00 open: page 0 is current.
          await _pumpSheet(tester, container, uci: 'd7d6');
          await _settle(tester);

          // 12:01:55 scroll on: page 1 goes out (the list as it stands now)
          // and is slow. The reader closes the sheet.
          now = DateTime(2026, 9, 26, 12, 1, 55);
          final slowPage1 = repo.pageGates[1] = Completer<void>();
          await _scrollToEnd(tester);
          expect(repo.requests, ['games|d7d6|0|20', 'games|d7d6|1|20']);
          await _tearDown(tester);

          // Live ingestion puts one game on top: every row shifts by one.
          repo.fallback = (pageNumber) => switch (pageNumber) {
            0 => _page(['new', ..._ids('p0-', 19)]),
            1 => _page(['p0-20', ..._ids('p1-', 19)], pageNumber: 1),
            _ => _page(_ids('p$pageNumber-'), pageNumber: pageNumber),
          };

          // 12:02:05 reopen: page 0 is past fresh, asked again, replaced.
          now = DateTime(2026, 9, 26, 12, 2, 5);
          await _pumpSheet(tester, container, uci: 'd7d6');
          await _settle(tester);
          expect(_shownIds(tester).first, 'new');

          if (landsWhileWaiting) {
            // The reader scrolls on while the old page 1 is still out.
            now = DateTime(2026, 9, 26, 12, 2, 6);
            await _scrollToEnd(tester);
            now = DateTime(2026, 9, 26, 12, 2, 8);
            slowPage1.complete();
            await _settle(tester);
          } else {
            // It lands at 12:02:08; the reader scrolls on at 12:02:20.
            now = DateTime(2026, 9, 26, 12, 2, 8);
            slowPage1.complete();
            await _settle(tester);
            now = DateTime(2026, 9, 26, 12, 2, 20);
            await _scrollToEnd(tester);
          }

          expect(repo.requests, [
            'games|d7d6|0|20',
            'games|d7d6|1|20',
            'games|d7d6|0|20',
            'games|d7d6|1|20',
          ]);
          // The game pushed off page 0 sits right after page 0's last row.
          await tester.dragUntilVisible(
            find.text('White p0-19'),
            find.byType(ListView),
            const Offset(0, 120),
          );
          await _settle(tester);
          expect(
            _shownIds(tester).skipWhile((id) => id != 'p0-19').take(3),
            ['p0-19', 'p0-20', 'p1-1'],
          );
          await _tearDown(tester);
        },
      );
    }

    testWidgets('a later page fetched after page 0 is appended as it is', (
      tester,
    ) async {
      final repo = _Repo();
      var now = DateTime(2026, 9, 26, 12);
      final container = _clockContainer(repo, () => now);

      await _pumpSheet(tester, container, uci: 'd7d6');
      await _settle(tester);
      now = now.add(const Duration(seconds: 30));
      await _scrollToEnd(tester);
      await _tearDown(tester);

      // Reopened within the fresh window: page 0 and page 1 both still
      // current, so neither is asked for again.
      now = now.add(const Duration(seconds: 30));
      await _pumpSheet(tester, container, uci: 'd7d6');
      await _settle(tester);
      await _scrollToEnd(tester);
      expect(repo.requests, ['games|d7d6|0|20', 'games|d7d6|1|20']);
      expect(find.text('White p1-1', skipOffstage: false), findsOneWidget);
      await _tearDown(tester);
    });
  });

  group('opening a game', () {
    testWidgets('a refresh landing mid-open never changes the game opened', (
      tester,
    ) async {
      final repo = _Repo()..gate = Completer<void>();
      final disk = _Disk();
      final container = _container(repo, disk: disk);
      final query = _sheetQuery(uci: 'd7d6');
      await _saveEarlier(tester, container, disk, query, _page(_ids('s')));
      // Live ingestion put a new game on top in the meantime.
      repo.script[0] = [
        _page(['new', ..._ids('s', 19)]),
      ];

      GamesTourModel? tapped;
      List<GamesTourModel>? handed;
      List<String>? handedIdsAtTap;
      int? handedIndex;
      final paywall = Completer<void>();
      Future<void> opener(
        BuildContext context,
        WidgetRef ref,
        GamesTourModel game,
        List<GamesTourModel> allGames,
        int currentIndex,
        String? initialFen,
      ) async {
        tapped = game;
        handed = allGames;
        handedIdsAtTap = [for (final g in allGames) g.gameId];
        handedIndex = currentIndex;
        // The paywall and the PGN request take a while.
        await paywall.future;
      }

      await _pumpSheet(tester, container, uci: 'd7d6', opener: opener);
      expect(_shownIds(tester).take(2), ['s1', 's2']);
      await tester.tap(find.text('White s2'));
      await tester.pump();
      expect(tapped?.gameId, 's2');

      // The first page is refreshed while the open is still in progress.
      repo.gate!.complete();
      await _settle(tester);
      expect(_shownIds(tester).take(3), ['new', 's1', 's2']);

      // The list the tap handed over is untouched...
      expect([for (final g in handed!) g.gameId], handedIdsAtTap);
      expect(handed![handedIndex!].gameId, 's2');
      // ...and the board resolves the tapped game, whatever the index holds.
      final (games, index) = resolveGamebaseBoardGames(
        games: handed!,
        game: tapped!,
        currentIndex: handedIndex!,
        pgn: '1. e4 e5',
      );
      expect(games[index].gameId, 's2');
      expect(games[index].pgn, '1. e4 e5');
      paywall.complete();
      await _tearDown(tester);
    });
  });

  group('resolveGamebaseBoardGames', () {
    GamesTourModel game(String id) => mapGamebasePreviewToTourModel(_row(id));

    test('finds the tapped game after the list moved under it', () {
      final a = game('a');
      final b = game('b');
      final inserted = game('new');
      // The tap saw `a` at index 0; the list now starts with a new game.
      final (games, index) = resolveGamebaseBoardGames(
        games: [inserted, a, b],
        game: a,
        currentIndex: 0,
        pgn: 'pgn',
      );
      expect(index, 1);
      expect(games[index].gameId, 'a');
      expect(games[index].pgn, 'pgn');
      expect(games[0].pgn, isNull);
    });

    test('falls back to the id, then to the tapped game alone', () {
      final a = game('a');
      final (byId, byIdIndex) = resolveGamebaseBoardGames(
        games: [game('x'), game('a')],
        game: a,
        currentIndex: 0,
        pgn: null,
      );
      expect(byId[byIdIndex].gameId, 'a');

      final (alone, aloneIndex) = resolveGamebaseBoardGames(
        games: [game('x'), game('y')],
        game: a,
        currentIndex: 1,
        pgn: null,
      );
      expect(alone.map((g) => g.gameId), ['a']);
      expect(aloneIndex, 0);
    });
  });
}
