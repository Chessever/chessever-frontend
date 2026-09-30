import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_eval_provider.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_games_prefetch.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The explorer's move table warms the games sheets behind its rows only
/// for positions the reader stops on, only for sheets the table can open,
/// and drops what is still waiting once the reader moves on.

const _line = <String>[
  'e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5', 'c2c3', 'g8f6', //
  'd2d3', 'd7d6', 'b1d2', 'a7a6', 'h2h3', 'h7h6', 'a2a4', 'c8e6',
];

String _fenAfter(int plies) {
  Position position = Chess.initial;
  for (final uci in _line.take(plies)) {
    position = position.play(NormalMove.fromUci(uci));
  }
  return position.fen;
}

/// One games request: its position, its row (null for '∑') and page size.
typedef _GamesRequest = ({String fen, String? uci, int pageSize});

class _Repo extends GamebaseRepository {
  _Repo({required this.aggregateCount})
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  /// Moves in every position's table.
  final int aggregateCount;
  final List<_GamesRequest> games = <_GamesRequest>[];

  /// While set, every sheet page (20 a page) waits in [held]: a server slow
  /// on exactly the warm-ups.
  bool holdSheets = false;
  final List<Completer<void>> held = <Completer<void>>[];

  void release() {
    holdSheets = false;
    for (final gate in held) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  /// Sheet requests for [fen], in the order they were sent.
  List<_GamesRequest> sheetsFor(String fen) => [
    for (final request in games)
      if (request.fen == fen && request.pageSize == kExplorerGamesSheetPageSize)
        request,
  ];

  @override
  Future<GamebaseResponse> getMoveAggregates({
    required String fen,
    List<String> moves = const [],
    String? playerId,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
    String? color,
    String? result,
    int? yearFrom,
    int? yearTo,
    bool? isOnline,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final position = Chess.fromSetup(Setup.parseFen(fen));
    final aggregates = <MoveAggregate>[];
    for (final entry in position.legalMoves.entries) {
      for (final to in entry.value.squares) {
        if (aggregates.length == aggregateCount) break;
        aggregates.add(
          MoveAggregate(
            uci: NormalMove(from: entry.key, to: to).uci,
            white: 5,
            black: 5,
            draws: 5,
            total: 15 + aggregates.length,
          ),
        );
      }
    }
    return GamebaseResponse(
      status: 'success',
      data: GamebaseData(moves: aggregates),
    );
  }

  Future<GamebaseSearchQueryResponse> _answer(
    String fen,
    String? uci,
    int pageNumber,
    int pageSize,
  ) async {
    games.add((fen: fen, uci: uci, pageSize: pageSize));
    if (holdSheets && pageSize == kExplorerGamesSheetPageSize) {
      final gate = Completer<void>();
      held.add(gate);
      await gate.future;
    }
    return GamebaseSearchQueryResponse(
      status: 'success',
      data: [
        <String, dynamic>{
          'id': 'g-$uci-$pageNumber',
          'white': 'A',
          'black': 'B',
          'result': '1-0',
          'date': '2024-01-01',
          'continuation': const <String>[],
        },
      ],
      // More than the inline strip shows, so the panel stays a plain move
      // table: these tests are about the rows' warm-ups.
      metadata: GamebasePaginationMetadata(
        pageNumber: pageNumber,
        pageSize: pageSize,
        hasMoreValue: true,
      ),
    );
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
  }) => _answer(fen, uci, pageNumber, pageSize);

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
  }) => _answer(fen, uci, pageNumber, pageSize);

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async => null;
}

class _Subscribed extends SubscriptionNotifier {
  _Subscribed() : super() {
    state = SubscriptionState(isSubscribed: true);
  }
}

class _Engine extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async {
    const settings = EngineSettings(
      showEngineAnalysis: false,
      engineLinesView: EngineLinesView.cards,
    );
    state = const AsyncValue.data(settings);
    return settings;
  }
}

class _Board extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async {
    const settings = BoardSettingsNew(useFigurine: false);
    state = const AsyncValue.data(settings);
    return settings;
  }
}

class _Eval extends ExplorerEvalNotifier {
  _Eval(super.ref);

  @override
  void setEngineEnabled({
    required bool enabled,
    required String fen,
    bool force = false,
  }) {}

  @override
  Future<void> evaluatePosition(String fen, {bool force = false}) async {}
}

/// The explorer on the start position, settled.
Future<ProviderContainer> _pumpExplorer(
  WidgetTester tester,
  _Repo repo,
) async {
  // Wide enough that no move row overflows in the test font.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 932);
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      gamebaseRepositoryProvider.overrideWithValue(repo),
      subscriptionProvider.overrideWith((ref) => _Subscribed()),
      engineSettingsProviderNew.overrideWith(_Engine.new),
      boardSettingsProviderNew.overrideWith(_Board.new),
      explorerEvalProvider.overrideWith((ref) => _Eval(ref)),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const GamebaseExplorerScreen(
              enableWorkspaceCoachmarks: false,
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  return container;
}

/// Frames 20 ms apart for [time], as a phone would draw them.
Future<void> _stay(WidgetTester tester, Duration time) async {
  for (var t = Duration.zero; t < time; t += const Duration(milliseconds: 20)) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void _goTo(ProviderContainer container, int plies) {
  container
      .read(gamebaseExplorerProvider.notifier)
      .setPositionWithMoves(
        _fenAfter(plies),
        _line.take(plies).toList(),
        startingFen: Chess.initial.fen,
      );
}

Future<void> _tearDown(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  group("'∑' warm-up", () {
    testWidgets("a position with one move never warms '∑'", (tester) async {
      final repo = _Repo(aggregateCount: 1);
      final container = await _pumpExplorer(tester, repo);

      _goTo(container, 4);
      await _stay(tester, const Duration(seconds: 2));

      // Its only row is warmed; the '∑' sheet, which no row on screen opens,
      // is not.
      expect(find.text('∑'), findsNothing);
      final sheets = repo.sheetsFor(_fenAfter(4));
      expect(sheets, hasLength(1));
      expect(sheets.single.uci, isNotNull);
      await _tearDown(tester, container);
    });

    testWidgets("with two moves or more, '∑' is warmed first", (tester) async {
      final repo = _Repo(aggregateCount: 3);
      final container = await _pumpExplorer(tester, repo);

      _goTo(container, 4);
      await _stay(tester, const Duration(seconds: 2));

      expect(find.text('∑'), findsOneWidget);
      final sheets = repo.sheetsFor(_fenAfter(4));
      expect(sheets.map((request) => request.uci == null), [
        true,
        false,
        false,
        false,
      ]);
      await _tearDown(tester, container);
    });
  });

  group('warm-ups wait for the reader to stop', () {
    testWidgets('stepping at 400 ms a move warms none of the positions', (
      tester,
    ) async {
      final repo = _Repo(aggregateCount: 5);
      final container = await _pumpExplorer(tester, repo);

      for (var plies = 1; plies <= 8; plies++) {
        _goTo(container, plies);
        await _stay(tester, const Duration(milliseconds: 400));
      }
      for (var plies = 1; plies <= 8; plies++) {
        expect(repo.sheetsFor(_fenAfter(plies)), isEmpty, reason: '$plies');
      }

      // Stopping on the last one warms it, '∑' first.
      await _stay(tester, const Duration(seconds: 1));
      final stoppedOn = repo.sheetsFor(_fenAfter(8));
      expect(stoppedOn, isNotEmpty);
      expect(stoppedOn.first.uci, isNull);
      await _tearDown(tester, container);
    });

    testWidgets('leaving a position drops what it still had waiting', (
      tester,
    ) async {
      final repo = _Repo(aggregateCount: 5);
      final container = await _pumpExplorer(tester, repo);
      await _stay(tester, const Duration(seconds: 1));
      final prefetcher = container.read(explorerGamesPrefetchProvider);

      // A, on a server slow on sheets: three on the wire, three waiting.
      repo.holdSheets = true;
      final a = _fenAfter(4);
      _goTo(container, 4);
      await _stay(tester, const Duration(seconds: 1));
      expect(repo.sheetsFor(a), hasLength(kExplorerGamesPrefetchConcurrency));
      expect(prefetcher.queued.map((query) => query.fen).toSet(), {a});

      // The reader moves on and scrubs through a few positions.
      for (var plies = 5; plies <= 9; plies++) {
        _goTo(container, plies);
        await _stay(tester, const Duration(milliseconds: 80));
      }
      expect(prefetcher.queued, isEmpty);

      // A's requests on the wire land; none of the dropped ones follows.
      repo.release();
      await _stay(tester, const Duration(milliseconds: 200));
      expect(repo.sheetsFor(a), hasLength(kExplorerGamesPrefetchConcurrency));
      await _tearDown(tester, container);
    });
  });
}
