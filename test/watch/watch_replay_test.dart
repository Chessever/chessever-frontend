import 'dart:convert';
import 'package:chessever2/watch/core/watch_replay.dart';
import 'package:chessever2/watch/core/watch_repository.dart';
import 'package:chessever2/watch/ui/watch_board.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/watch/ui/watch_game_page.dart';
import 'package:chessever2/watch/watch_controller.dart';
import 'package:flutter_watchos/flutter_watchos.dart'
    show WatchAlwaysOn, WatchCrown, WatchOSNativeBindings;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _CrownBindings extends WatchOSNativeBindings {
  _CrownBindings() : super.forTesting();
  int mode = 0;
  double pending = 0;
  bool dimmed = false;
  @override
  bool get alwaysOnActive => dimmed;
  @override
  set crownMode(int value) => mode = value;
  @override
  int get crownMode => mode;
  @override
  double consumeCrownDelta() {
    final delta = pending;
    pending = 0;
    return delta;
  }
}

void main() {
  const pgn = '1. e4 e5 2. Nf3 Nc6 *';

  test(
    'replay follows mainline, highlights moves, and respects FEN starts',
    () {
      final positions = watchReplayPositions('1. e4 (1. d4 d5) e5 2. Nf3 *');
      expect(positions, hasLength(4));
      expect(positions[1].lastMove, 'e2e4');
      expect(positions.last.lastMove, 'g1f3');
      expect(positions.last.label, '2. Nf3');
      final custom = watchReplayPositions(
        '[SetUp "1"]\n'
        '[FEN "7k/8/8/8/8/8/8/K7 b - - 0 42"]\n\n42... Kg7 *',
      );
      expect(custom, hasLength(2));
      expect(custom.last.label, '42… Kg7');
      expect(custom.last.lastMove, 'h8g7');
      expect(watchReplayPositions(null), isEmpty);
      expect(watchReplayPositions('1. e4 e5 2. e4 *'), isEmpty);
      expect(watchReplayPositions('No published moves'), isEmpty);
    },
  );

  test(
    'dial accumulates detents, clamps and reverses immediately at limits',
    () {
      final dial = WatchReplayDial();
      expect(dial.turn(0.1, index: 2, last: 4), 2);
      expect(dial.turn(0.15, index: 2, last: 4), 3);
      expect(dial.turn(50, index: 3, last: 4), 4);
      expect(dial.turn(-0.25, index: 4, last: 4), 3);
      expect(dial.turn(-50, index: 3, last: 4), 0);
      expect(dial.turn(0.25, index: 0, last: 4), 1);
      expect(dial.turn(double.nan, index: 1, last: 4), 1);
    },
  );

  test('PGN is fetched separately from lightweight game lists', () async {
    final repository = WatchRepository(
      apiKey: 'key',
      client: MockClient((request) async {
        expect(request.url.path, '/rest/v1/games');
        expect(request.url.queryParameters, {
          'select': 'pgn',
          'id': 'eq.game-1',
          'limit': '1',
        });
        return http.Response(
          jsonEncode([
            {'pgn': pgn},
          ]),
          200,
        );
      }),
    );
    expect(await repository.gamePgn('game-1'), pgn);
    expect(WatchRepository.gameColumns.split(','), isNot(contains('pgn')));
    repository.dispose();
  });

  late _CrownBindings bindings;
  setUp(() {
    bindings = _CrownBindings();
    WatchAlwaysOn.bindingsOverride = bindings;
    WatchCrown.instance.bindingsOverride = bindings;
    WatchCrown.instance.debugAutoTick = false;
  });
  tearDown(() {
    WatchAlwaysOn.bindingsOverride = null;
    WatchCrown.instance.bindingsOverride = null;
    WatchCrown.instance.debugAutoTick = true;
  });

  Future<void> turn(WidgetTester tester, double delta) async {
    bindings.pending = delta;
    WatchCrown.instance.debugPoll(const Duration(milliseconds: 16));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// Two boards of one round, each with the same short game, served the
  /// way the feed serves them; the moves can be withheld for a first try.
  _GameRepository repo({bool withholdMoves = false}) =>
      _GameRepository(pgn, withholdMoves: withholdMoves);

  Games game(String id) => Games.fromJson({
    'id': id,
    'tour_id': 'tour1',
    'tour_slug': 'open',
    'round_id': 'r1',
    'round_slug': 'r1',
    'status': '*',
    'board_nr': id == 'g1' ? 1 : 2,
    'players': [
      {'name': 'Player One', 'fideId': 1},
      {'name': 'Player Two', 'fideId': 2},
    ],
    'fen': 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
    'last_move': 'b8c6',
  });

  Widget page(_GameRepository repository, {bool many = false}) => WatchGamePage(
    controller: WatchController(repository: repository),
    game: game('g1'),
    games: many ? [game('g1'), game('g2')] : const [],
  );

  Future<void> show(WidgetTester tester, Finder target) async {
    final scroll = find.byType(Scrollable).last;
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(target, 50, scrollable: scroll);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Crown and touch change the same replay; mode and Done release it',
    (tester) async {
      tester.view.physicalSize = const Size(162, 197);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = repo();
      await tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              child: const Text('Open'),
              onPressed: () {
                Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => page(repository, many: true),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(bindings.mode, 1);
      final lastFen = tester.widget<WatchBoard>(find.byType(WatchBoard)).fen;
      await turn(tester, -0.25);
      expect(
        tester.widget<WatchBoard>(find.byType(WatchBoard)).fen,
        isNot(lastFen),
      );
      await show(tester, find.bySemanticsLabel('Next move'));
      final next = find.bySemanticsLabel('Next move');
      expect(tester.getSize(next).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(next).width, greaterThanOrEqualTo(44));
      await tester.tap(next);
      await tester.pumpAndSettle();
      await show(tester, find.byType(WatchBoard));
      expect(tester.widget<WatchBoard>(find.byType(WatchBoard)).fen, lastFen);
      // The board fills the width beside the engine bar, under the clock
      // band, White's line under it, nothing else above the fold.
      final board = tester.getRect(find.byType(WatchBoard));
      expect(board.left, WatchGamePage.evalBarWidth + WatchGamePage.evalBarGap);
      expect(board.width, 162 - board.left - 2);
      expect(
        find.text(
          'Board 1 of 2 · swipe the board sideways',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      // A swipe on the board moves to the next board of the list; the Crown
      // then reviews that game.
      await tester.fling(find.byType(WatchBoard), const Offset(-80, 0), 600);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Board 2 of 2 · swipe the board sideways',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(repository.fetched, ['g1', 'g2']);
      expect(bindings.mode, 1);
      await turn(tester, -0.25);
      expect(
        tester.widget<WatchBoard>(find.byType(WatchBoard)).fen,
        isNot(lastFen),
      );
      await tester.fling(find.byType(WatchBoard), const Offset(80, 0), 600);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Board 1 of 2 · swipe the board sideways',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      await show(tester, find.text(WatchGamePage.backLabel));
      await tester.tap(find.text(WatchGamePage.backLabel));
      await tester.pumpAndSettle();
      expect(bindings.mode, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('covered routes and inactive app relinquish the raw Crown', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      CupertinoApp(navigatorKey: nav, home: page(repo())),
    );
    await tester.pumpAndSettle();
    expect(bindings.mode, 1);
    nav.currentState!.push(
      CupertinoPageRoute<void>(
        builder: (_) =>
            const CupertinoPageScaffold(child: Text('Other screen')),
      ),
    );
    await tester.pumpAndSettle();
    expect(bindings.mode, 0);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(bindings.mode, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(bindings.mode, 0);
    bindings.dimmed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(bindings.mode, 0, reason: "Always On keeps move input disabled");
    bindings.dimmed = false;
    await tester.pump(const Duration(milliseconds: 250));
    expect(bindings.mode, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(bindings.mode, 0);
  });

  testWidgets('without moves the relay position shows and the Crown waits; '
      'the moves arrive with the next poll', (tester) async {
    final repository = repo(withholdMoves: true);
    await tester.pumpWidget(CupertinoApp(home: page(repository)));
    await tester.pumpAndSettle();
    expect(bindings.mode, 0, reason: 'nothing to review yet');
    expect(find.byType(WatchBoard), findsOneWidget);
    expect(find.text('Live · Nb8–c6', skipOffstage: false), findsOneWidget);
    repository.withholdMoves = false;
    repository.moved = true;
    await show(tester, find.text('Refresh'));
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(bindings.mode, 1);
    expect(find.text('2… Nc6 · Live', skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _GameRepository extends WatchRepository {
  _GameRepository(this.pgn, {this.withholdMoves = false})
    : super(apiKey: 'key');
  final String pgn;
  bool withholdMoves;

  /// True once the relay has a move the page has not seen.
  bool moved = false;
  final fetched = <String>[];

  @override
  Future<String?> gamePgn(String id) async => withholdMoves ? null : pgn;

  @override
  Future<Games?> game(String id) async {
    fetched.add(id);
    return Games.fromJson({
      'id': id,
      'tour_id': 'tour1',
      'tour_slug': 'open',
      'round_id': 'r1',
      'round_slug': 'r1',
      'status': '*',
      'board_nr': id == 'g1' ? 1 : 2,
      'players': [
        {'name': 'Player One', 'fideId': 1},
        {'name': 'Player Two', 'fideId': 2},
      ],
      'fen': 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
      'last_move': moved ? 'b8c6!' : 'b8c6',
    });
  }
}
