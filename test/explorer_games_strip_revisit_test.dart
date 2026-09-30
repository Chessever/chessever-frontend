import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_game_focus_provider.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_games_cache.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/widgets/explorer_game_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The explorer's inline games strip (and the panel that lays it out) never
/// passes an answer held from minutes ago off as current: coming back to a
/// position asks the server again, exactly as the explorer always has.

const _fenP = kInitialFEN;
const _fenQ = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async {
    const settings = BoardSettingsNew(useFigurine: false);
    state = const AsyncValue.data(settings);
    return settings;
  }
}

class _EngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async {
    const settings = EngineSettings(showEngineAnalysis: false);
    state = const AsyncValue.data(settings);
    return settings;
  }
}

/// The n-th strip answer for a position carries rows `<P|Q>v<n>-*`, so a
/// re-ask is visible on screen. [failFrom] makes every strip request for P
/// from that count on fail; [pIds], [pTotals] and [pGates] script the n-th
/// one's rows, its total, and hold it on the wire. Full-sheet pages (20 a
/// page) are logged apart and answered at once.
class _Repo extends GamebaseRepository {
  _Repo() : super(Dio(), apiKey: 'test', baseUrl: 'https://example.test');

  final List<String> requests = <String>[];
  final List<String> sheetRequests = <String>[];
  final Map<String, int> _asked = <String, int>{};
  int? failFrom;
  final Map<int, List<String>> pIds = <int, List<String>>{};
  final Map<int, int> pTotals = <int, int>{};
  final Map<int, Completer<void>> pGates = <int, Completer<void>>{};

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
    final tag = fen == _fenP ? 'P' : 'Q';
    if (pageSize != 10) {
      sheetRequests.add('$tag|$pageNumber');
      return GamebaseSearchQueryResponse(
        status: 'success',
        data: [
          for (var i = 1; i <= pageSize; i++)
            <String, dynamic>{'id': '${tag}s$pageNumber-$i', 'result': '1-0'},
        ],
        metadata: GamebasePaginationMetadata(
          pageNumber: pageNumber,
          pageSize: pageSize,
          hasMoreValue: true,
        ),
      );
    }
    requests.add(tag);
    final n = _asked[tag] = (_asked[tag] ?? 0) + 1;
    final gate = tag == 'P' ? pGates[n] : null;
    if (gate != null) await gate.future;
    if (tag == 'P' && failFrom != null && n >= failFrom!) {
      throw Exception('offline');
    }
    final ids =
        (tag == 'P' ? pIds[n] : null) ??
        [for (var i = 1; i <= 3; i++) '${tag}v$n-$i'];
    return GamebaseSearchQueryResponse(
      status: 'success',
      data: [
        for (final id in ids)
          <String, dynamic>{
            'id': id,
            'white': 'W $id',
            'black': 'B $id',
            'result': '1-0',
            'date': '2024-05-12',
          },
      ],
      metadata: GamebasePaginationMetadata(
        pageNumber: pageNumber,
        pageSize: pageSize,
        totalCount: (tag == 'P' ? pTotals[n] : null) ?? ids.length,
        hasMoreValue: false,
      ),
    );
  }

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async => null;
}

ProviderContainer _container(_Repo repo, DateTime Function() now) {
  final container = ProviderContainer(
    overrides: [
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      gamebaseRepositoryProvider.overrideWithValue(repo),
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

/// The inline page the panel and the strip both read for [fen].
GamebasePositionGamesQuery _inline(String fen) =>
    GamebasePositionGamesQuery.fromFilters(
      fen: fen,
      filters: const GamebaseFilters(),
      pageSize: 10,
      notationPlies: 20,
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

Future<void> _pumpStrip(
  WidgetTester tester,
  ProviderContainer container,
  String fen,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: SingleChildScrollView(
                child: ExplorerGamesSection(
                  key: ValueKey(fen),
                  fen: fen,
                  moves: const [],
                  filters: const GamebaseFilters(),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
}

void main() {
  group('the inline strip', () {
    testWidgets('back on a position minutes later, its games are asked again', (
      tester,
    ) async {
      final repo = _Repo();
      var now = DateTime(2026, 9, 26, 12);
      final container = _container(repo, () => now);

      await _pumpStrip(tester, container, _fenP);
      expect(find.text('W Pv1-1'), findsOneWidget);
      await _pumpStrip(tester, container, _fenQ);
      expect(repo.requests, ['P', 'Q']);

      // The reader stays on Q for five minutes, then steps back to P, whose
      // page is still held in memory.
      now = now.add(const Duration(minutes: 5));
      await _pumpStrip(tester, container, _fenP);

      expect(repo.requests, ['P', 'Q', 'P']);
      expect(find.text('W Pv2-1'), findsOneWidget);
      expect(find.text('W Pv1-1'), findsNothing);
      final held = container.read(positionGamesProvider(_inline(_fenP)));
      expect(
        container.read(explorerGamesCacheProvider).isFresh(held.requireValue),
        isTrue,
      );
      await _tearDown(tester);
    });

    testWidgets('back within two minutes, the held games answer at once', (
      tester,
    ) async {
      final repo = _Repo();
      var now = DateTime(2026, 9, 26, 12);
      final container = _container(repo, () => now);

      await _pumpStrip(tester, container, _fenP);
      await _pumpStrip(tester, container, _fenQ);
      now = now.add(const Duration(seconds: 90));
      await _pumpStrip(tester, container, _fenP);

      expect(repo.requests, ['P', 'Q']);
      expect(find.text('W Pv1-1'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('if asking again fails, the old games stay, marked as saved', (
      tester,
    ) async {
      final repo = _Repo()..failFrom = 2;
      var now = DateTime(2026, 9, 26, 12);
      final container = _container(repo, () => now);

      await _pumpStrip(tester, container, _fenP);
      await _pumpStrip(tester, container, _fenQ);
      now = now.add(const Duration(minutes: 5));
      await _pumpStrip(tester, container, _fenP);

      expect(repo.requests, ['P', 'Q', 'P']);
      expect(find.text('W Pv1-1'), findsOneWidget);
      expect(find.text('Saved games. Couldn’t refresh them.'), findsOneWidget);
      expect(find.text('Updating games...'), findsNothing);
      await _tearDown(tester);
    });

    // The reader focuses a card while the strip still shows the rows held
    // from minutes ago; the server's answer then replaces them.
    for (final dropped in [true, false]) {
      testWidgets(
        dropped
            ? 'a focused card the new rows drop gives the arrows back'
            : 'a focused card the new rows keep stays focused',
        (tester) async {
          final repo = _Repo();
          var now = DateTime(2026, 9, 26, 12);
          final container = _container(repo, () => now);
          final focus = container.listen(
            explorerFocusedGameProvider,
            (_, __) {},
          );
          addTearDown(focus.close);

          await _pumpStrip(tester, container, _fenP);
          await _pumpStrip(tester, container, _fenQ);
          now = now.add(const Duration(minutes: 5));
          final refresh = repo.pGates[2] = Completer<void>();
          repo.pIds[2] =
              dropped
                  ? ['new', 'Pv1-1', 'Pv1-2']
                  : ['new', 'Pv1-1', 'Pv1-2', 'Pv1-3'];
          await _pumpStrip(tester, container, _fenP);
          expect(find.text('W Pv1-3'), findsOneWidget);

          container
              .read(explorerFocusedGameProvider.notifier)
              .focus(
                gameId: 'Pv1-3',
                anchorFen: _fenP,
                sans: const ['e4'],
                fens: const [_fenP, _fenQ],
              );
          await _settle(tester);
          expect(focus.read()?.gameId, 'Pv1-3');

          refresh.complete();
          await _settle(tester);
          expect(find.text('W new'), findsOneWidget);
          if (dropped) {
            expect(find.text('W Pv1-3'), findsNothing);
            expect(focus.read(), isNull);
          } else {
            expect(find.text('W Pv1-3'), findsOneWidget);
            expect(focus.read()?.gameId, 'Pv1-3');
          }
          focus.close();
          await _tearDown(tester);
          // What a focused card started (its sounds, the explorer behind the
          // focus) winds down before the test ends.
          await tester.pump(const Duration(seconds: 5));
        },
      );
    }

    testWidgets('a saved copy never names its old count, link or sheet', (
      tester,
    ) async {
      final repo = _Repo()
        ..pTotals[1] = 1230
        ..pTotals[2] = 1236;
      var now = DateTime(2026, 9, 26, 12);
      final container = _container(repo, () => now);

      // A current answer names its count, as the strip always has.
      await _pumpStrip(tester, container, _fenP);
      expect(find.text('View all 1230 games'), findsOneWidget);
      expect(find.text('Updating games...'), findsNothing);

      // Back five minutes later: the held rows stand in while the server is
      // asked again, and say so.
      await _pumpStrip(tester, container, _fenQ);
      now = now.add(const Duration(minutes: 5));
      final refresh = repo.pGates[2] = Completer<void>();
      await _pumpStrip(tester, container, _fenP);
      expect(find.text('W Pv1-1'), findsOneWidget);
      expect(find.text('Updating games...'), findsOneWidget);
      expect(find.text('View all games'), findsOneWidget);
      expect(find.textContaining('1230'), findsNothing);

      // Opened now, the sheet's title names no count either.
      await tester.tap(find.text('View all games'));
      await _settle(tester);
      expect(find.text('All games'), findsOneWidget);
      expect(find.textContaining('1230'), findsNothing);

      // The answer lands: the strip names the current count.
      refresh.complete();
      await _settle(tester);
      expect(find.text('View all 1236 games'), findsOneWidget);
      expect(find.text('Updating games...'), findsNothing);
      expect(find.textContaining('1230'), findsNothing);
      await _tearDown(tester);
    });
  });

  group('refreshExplorerGamesIfStale', () {
    testWidgets('a held failed refresh is retried while its listener remains', (
      tester,
    ) async {
      final repo = _Repo();
      var now = DateTime(2026, 9, 26, 12);
      final container = _container(repo, () => now);
      late WidgetRef widgetRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              widgetRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final query = _inline(_fenP);
      final provider = positionGamesProvider(query);
      final sub = container.listen(provider, (_, __) {});
      addTearDown(sub.close);
      await container.read(provider.future);
      expect(repo.requests, ['P']);

      now = now.add(kExplorerGamesFreshFor + const Duration(seconds: 1));
      repo.failFrom = 2;
      expect(refreshExplorerGamesIfStale(widgetRef, query), isTrue);
      await expectLater(container.read(provider.future), throwsException);
      await _settle(tester);
      expect(sub.read().hasError, isTrue);
      expect(repo.requests, ['P', 'P']);

      repo.failFrom = null;
      expect(refreshExplorerGamesIfStale(widgetRef, query), isTrue);
      await container.read(provider.future);
      await _settle(tester);
      expect(repo.requests, ['P', 'P', 'P']);
      expect(sub.read().requireValue.data.first['id'], 'Pv3-1');
      await _tearDown(tester);
    });

    testWidgets('asks again only for a settled answer past fresh', (
      tester,
    ) async {
      final repo = _Repo();
      var now = DateTime(2026, 9, 26, 12);
      final container = _container(repo, () => now);
      late WidgetRef widgetRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              widgetRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final query = _inline(_fenP);

      // Nothing held: nothing asked, nothing created.
      expect(refreshExplorerGamesIfStale(widgetRef, query), isFalse);
      expect(container.exists(positionGamesProvider(query)), isFalse);

      // In flight, then fresh: left alone.
      final pending = container.read(positionGamesProvider(query).future);
      expect(refreshExplorerGamesIfStale(widgetRef, query), isFalse);
      await pending;
      expect(refreshExplorerGamesIfStale(widgetRef, query), isFalse);
      expect(repo.requests, ['P']);

      // Past fresh (the panel re-attaching to it minutes later): asked again.
      now = now.add(kExplorerGamesFreshFor + const Duration(seconds: 1));
      final sub = container.listen(positionGamesProvider(query), (_, __) {});
      addTearDown(sub.close);
      expect(refreshExplorerGamesIfStale(widgetRef, query), isTrue);
      await _settle(tester);
      expect(repo.requests, ['P', 'P']);
      expect(sub.read().requireValue.data.first['id'], 'Pv2-1');
      await _tearDown(tester);
    });
  });
}
