import 'dart:async';
import 'dart:convert';
import 'package:chessever2/watch/core/watch_eval.dart';
import 'package:chessever2/watch/core/watch_replay.dart';
import 'package:chessever2/watch/core/watch_sound.dart';
import 'package:chessever2/watch/core/watch_repository.dart';
import 'package:chessever2/watch/ui/watch_board.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/watch/ui/watch_game_page.dart';
import 'package:chessever2/watch/watch_controller.dart';
import 'package:flutter_watchos/flutter_watchos.dart'
    show WatchAlwaysOn, WatchCrown, WatchOSNativeBindings;
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
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
  late WatchEvalSource previousEvalSource;
  late List<WatchSound> played;
  var soundTime = Duration.zero;
  setUp(() {
    played = [];
    soundTime = Duration.zero;
    WatchSounds.debugPlayer = played.add;
    WatchSounds.debugNow = () => soundTime;
    WatchSounds.shared.debugReset();
    bindings = _CrownBindings();
    WatchAlwaysOn.bindingsOverride = bindings;
    WatchCrown.instance.bindingsOverride = bindings;
    WatchCrown.instance.debugAutoTick = false;
    previousEvalSource = WatchEvalSource.shared;
    WatchEvalSource.shared = WatchEvalSource(
      client: MockClient((_) async => http.Response('', 404)),
    );
  });
  tearDown(() {
    WatchSounds.debugPlayer = null;
    WatchSounds.debugNow = null;
    WatchSounds.shared.debugReset();
    WatchAlwaysOn.bindingsOverride = null;
    WatchCrown.instance.bindingsOverride = null;
    WatchCrown.instance.debugAutoTick = true;
    WatchEvalSource.shared.dispose();
    WatchEvalSource.shared = previousEvalSource;
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

  testWidgets('Crown and overlay arrows review moves; swiping changes games', (
    tester,
  ) async {
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
    // The square board and bar have their own gutters, clear of the edge.
    final board = tester.getRect(find.byType(WatchBoard));
    expect(
      board.left,
      greaterThan(WatchGamePage.evalBarWidth + WatchGamePage.evalBarGap),
    );
    expect(board.right, lessThan(162 - 8));
    expect(board.width, closeTo(board.height, 0.01));
    const barSpace = WatchGamePage.evalBarWidth + WatchGamePage.evalBarGap;
    final leftGutter = board.left - barSpace;
    final rightGutter = 162 - board.right;
    expect(leftGutter, greaterThanOrEqualTo(WatchGamePage.minGutter));
    expect(leftGutter, moreOrLessEquals(rightGutter, epsilon: 0.01));

    expect(
      find.text('Board 1 of 2 · swipe the board sideways', skipOffstage: false),
      findsOneWidget,
    );
    // A swipe on the board moves to the next board of the list; the Crown
    // then reviews that game.
    await tester.fling(find.byType(WatchBoard), const Offset(-80, 0), 600);
    await tester.pumpAndSettle();
    expect(
      find.text('Board 2 of 2 · swipe the board sideways', skipOffstage: false),
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
      find.text('Board 1 of 2 · swipe the board sideways', skipOffstage: false),
      findsOneWidget,
    );
    await show(tester, find.text(WatchGamePage.backLabel));
    await tester.tap(find.text(WatchGamePage.backLabel));
    await tester.pumpAndSettle();
    expect(bindings.mode, 0);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(162, 197),
    Size(176, 215),
    Size(184, 224),
    Size(198, 242),
    Size(205, 251),
    Size(211, 257),
  ]) {
    testWidgets('board, players, eval and arrows clear safe edges at $size', (
      tester,
    ) async {
      final band = size.width > 200 ? 56.5 : (size.width > 180 ? 45.0 : 40.0);
      final corner = size.width > 200 ? 17.0 : (size.width > 180 ? 12.0 : 9.0);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(
        top: band,
        bottom: corner,
        left: corner,
        right: corner + 2,
      );
      addTearDown(tester.view.reset);
      await tester.pumpWidget(CupertinoApp(home: page(repo())));
      await tester.pumpAndSettle();
      final board = tester.getRect(find.byType(WatchBoard));
      final black = tester.getRect(
        find.byKey(const ValueKey('watch-player-strip-1')),
      );
      final white = tester.getRect(
        find.byKey(const ValueKey('watch-player-strip-0')),
      );
      expect(black.top, greaterThanOrEqualTo(band + 4));
      expect(black.bottom, lessThan(board.top));
      expect(white.top, greaterThan(board.bottom));
      expect(white.bottom, lessThanOrEqualTo(size.height - corner - 4));
      final caption = find.byKey(const ValueKey('watch-game-caption'));
      if (caption.evaluate().isNotEmpty) {
        expect(
          tester.getTopLeft(caption).dy,
          greaterThanOrEqualTo(size.height),
        );
      }
      for (final row in [white, black]) {
        expect(row.left, greaterThanOrEqualTo(corner + 12));
        expect(row.right, lessThanOrEqualTo(size.width - corner - 14));
      }
      expect(board.width, closeTo(board.height, 0.01));
      final bar = tester.getRect(find.bySemanticsLabel('Engine'));
      expect(bar.top, board.top);
      expect(bar.bottom, board.bottom);
      expect(bar.left, greaterThanOrEqualTo(corner + 12));
      expect(bar.right, lessThan(board.left));
      final previous = tester.getRect(find.bySemanticsLabel('Previous move'));
      final next = tester.getRect(find.bySemanticsLabel('Next move'));
      for (final target in [previous, next]) {
        expect(target.width, greaterThanOrEqualTo(44));
        expect(target.height, greaterThanOrEqualTo(44));
        expect(target.left, greaterThanOrEqualTo(0));
        expect(target.right, lessThanOrEqualTo(size.width));
        expect(target.bottomRight.dy, lessThanOrEqualTo(board.bottom));
        expect(target.center.dy, closeTo(board.center.dy, 0.01));
      }
      for (final label in ['Previous move', 'Next move']) {
        final target = find.bySemanticsLabel(label);
        final icon = find.descendant(of: target, matching: find.byType(Icon));
        final center = tester.getCenter(icon);
        expect(center.dy, closeTo(board.center.dy, 0.01));
        if (label == 'Previous move') {
          expect(center.dx, closeTo(bar.left / 2, 0.01));
        } else {
          expect(center.dx, closeTo((board.right + size.width) / 2, 0.01));
        }
      }
      expect(previous.right, lessThanOrEqualTo(next.left));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('stepping plays the phone board sounds', (tester) async {
    tester.view.physicalSize = const Size(184, 224);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _GameRepository('1. e4 d5 2. exd5 Qxd5 *');
    await tester.pumpWidget(CupertinoApp(home: page(repository)));
    await tester.pumpAndSettle();
    // Opening the game is quiet; the Crown back a move plays a move sound.
    expect(played, isEmpty);
    await turn(tester, -0.25);
    expect(played, [WatchSound.move]);
    // Turns faster than the spacing tick once.
    await turn(tester, -0.25);
    expect(played, [WatchSound.move]);
    soundTime += WatchSounds.spacing;
    await tester.tap(find.bySemanticsLabel('Next move'));
    await tester.pumpAndSettle();
    expect(played, [WatchSound.move, WatchSound.takeover]);
    soundTime += WatchSounds.spacing;
    // Wheel input reaches the same sound path, including captures.
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(WatchBoard)),
        scrollDelta: const Offset(0, 40),
      ),
    );
    await tester.pump();
    expect(played, [WatchSound.move, WatchSound.takeover, WatchSound.takeover]);
    soundTime += WatchSounds.spacing;
    await turn(tester, 0.25);
    expect(played, hasLength(3), reason: 'The end is silent');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('live sounds require the foreground game being followed', (
    tester,
  ) async {
    final repository = repo();
    await tester.pumpWidget(CupertinoApp(home: page(repository)));
    await tester.pumpAndSettle();
    expect(played, isEmpty, reason: 'Initial history is quiet');

    Future<void> publish(String moves) async {
      repository.pgn = moves;
      repository.moved = !repository.moved;
      soundTime += WatchSounds.spacing;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
    }

    await publish('1. e4 e5 2. Nf3 Nc6 3. Bb5 *');
    expect(played, [WatchSound.move]);
    soundTime += WatchSounds.spacing;
    await turn(tester, -0.25);
    expect(played, [WatchSound.move, WatchSound.move]);
    await publish('1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *');
    expect(played, hasLength(2), reason: 'Review holds its own position');
    // Returning to the end follows new moves again.
    await turn(tester, 100);
    expect(played, hasLength(3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await publish('1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Bxc6 *');
    expect(played, hasLength(3), reason: 'Inactive games do not poll or sound');
    await turn(tester, -0.25);
    expect(played, hasLength(3));
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a watched draw sounds once', (tester) async {
    final row = <String, Object?>{};
    final repository = _GameRepository(pgn, overrides: row);
    await tester.pumpWidget(CupertinoApp(home: page(repository)));
    await tester.pumpAndSettle();
    row['status'] = '1/2-1/2';
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(played, [WatchSound.draw]);
    soundTime += WatchSounds.spacing;
    await show(tester, find.text('Refresh'));
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(played, [WatchSound.draw]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('wheel detents review moves without scrolling the board away', (
    tester,
  ) async {
    await tester.pumpWidget(CupertinoApp(home: page(repo())));
    await tester.pumpAndSettle();
    final lastFen = tester.widget<WatchBoard>(find.byType(WatchBoard)).fen;
    final before = tester.getRect(find.byType(WatchBoard));
    Future<void> wheel(double dy) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(WatchBoard)),
          scrollDelta: Offset(0, dy),
        ),
      );
      await tester.pump();
    }

    await wheel(-10);
    expect(tester.widget<WatchBoard>(find.byType(WatchBoard)).fen, lastFen);
    await wheel(-30);
    expect(
      tester.widget<WatchBoard>(find.byType(WatchBoard)).fen,
      isNot(lastFen),
    );
    expect(tester.getRect(find.byType(WatchBoard)), before);
    await wheel(40);
    expect(tester.widget<WatchBoard>(find.byType(WatchBoard)).fen, lastFen);
    await wheel(4000);
    await wheel(-40);
    expect(
      tester.widget<WatchBoard>(find.byType(WatchBoard)).fen,
      isNot(lastFen),
      reason: 'reverses immediately at the last move',
    );
    // Both touch shortcuts use the same position and clamp at the ends.
    await tester.longPress(find.bySemanticsLabel('Previous move'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<WatchBoard>(find.byType(WatchBoard)).fen,
      watchReplayPositions(pgn).first.fen,
    );
    await wheel(-4000);
    await wheel(40);
    expect(
      tester.widget<WatchBoard>(find.byType(WatchBoard)).fen,
      watchReplayPositions(pgn)[1].fen,
    );
    await tester.longPress(find.bySemanticsLabel('Next move'));
    await tester.pumpAndSettle();
    expect(tester.widget<WatchBoard>(find.byType(WatchBoard)).fen, lastFen);
    expect(tester.getRect(find.byType(WatchBoard)), before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('evaluation clears as soon as the shown position changes', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var calls = 0;
    WatchEvalSource.shared.dispose();
    WatchEvalSource.shared = WatchEvalSource(
      client: MockClient((_) {
        calls++;
        return calls == 1
            ? Future.value(
                http.Response(
                  jsonEncode({
                    'depth': 24,
                    'pvs': [
                      {'cp': 130},
                    ],
                  }),
                  200,
                ),
              )
            : response.future;
      }),
    );
    await tester.runAsync(
      () => WatchEvalSource.shared.eval(watchReplayPositions(pgn).last.fen),
    );
    await tester.pumpWidget(CupertinoApp(home: page(repo())));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.bySemanticsLabel('Engine')).value, '+1.3');
    await turn(tester, -0.25);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Engine')).value,
      'Unknown',
    );
    await tester.pump(const Duration(milliseconds: 250));
    response.complete(http.Response('', 404));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Engine')).value,
      'Unknown',
    );
    await turn(tester, 0.25);
    expect(tester.getSemantics(find.bySemanticsLabel('Engine')).value, '+1.3');
    final fill = find.descendant(
      of: find.bySemanticsLabel('Engine'),
      matching: find.byType(AnimatedPositioned),
    );
    final normalFill = tester.widget<AnimatedPositioned>(fill);
    expect(normalFill.bottom, 0);
    expect(normalFill.top, isNull);
    await show(tester, find.text('Black at bottom'));
    await tester.tap(find.text('Black at bottom'));
    await tester.pumpAndSettle();
    await show(tester, find.byType(WatchBoard));
    final flippedFill = tester.widget<AnimatedPositioned>(fill);
    expect(flippedFill.top, 0);
    expect(flippedFill.bottom, isNull);
    expect(flippedFill.height, normalFill.height);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('watch-player-strip-0'))).dy,
      lessThan(tester.getTopLeft(find.byType(WatchBoard)).dy),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('large type and long player names retain clocks and controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(162, 197);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 16);
    addTearDown(tester.view.reset);
    final repository = _GameRepository(
      pgn,
      overrides: {
        'players': [
          {'name': 'Praggnanandhaa, Rameshbabu', 'title': 'GM'},
          {'name': 'Abdusattorov, Nodirbek', 'title': 'GM'},
        ],
        'last_clock_white': 5208,
        'last_clock_black': 102,
      },
    );
    await tester.pumpWidget(
      CupertinoApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: page(repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('86:48'), findsOneWidget);
    expect(find.text('1:42'), findsOneWidget);
    final board = tester.getRect(find.byType(WatchBoard));
    expect(board.width, closeTo(board.height, 0.01));
    expect(board.width, greaterThanOrEqualTo(88));
    await show(tester, find.byKey(const ValueKey('watch-player-strip-0')));
    expect(
      find.bySemanticsLabel(RegExp('GM Praggnanandhaa, Rameshbabu')),
      findsOneWidget,
    );
    final white = tester.getRect(
      find.byKey(const ValueKey('watch-player-strip-0')),
    );
    expect(white.bottom, lessThanOrEqualTo(197 - 16));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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
    tester.view.physicalSize = const Size(184, 224);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = repo(withholdMoves: true);
    await tester.pumpWidget(CupertinoApp(home: page(repository)));
    await tester.pumpAndSettle();
    expect(bindings.mode, 0, reason: 'nothing to review yet');
    expect(find.byType(WatchBoard), findsOneWidget);
    expect(find.text('Live · Nb8–c6', skipOffstage: false), findsOneWidget);
    repository.withholdMoves = false;
    repository.moved = true;
    await show(tester, find.text('Refresh'));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).last);
    expect(scroll.position.pixels, greaterThan(0));
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(bindings.mode, 1);
    expect(
      scroll.position.pixels,
      0,
      reason: 'Move review brings the board back',
    );
    expect(tester.getRect(find.byType(WatchBoard)).bottom, lessThan(224));
    expect(find.text('2… Nc6 · Live', skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _GameRepository extends WatchRepository {
  _GameRepository(
    this.pgn, {
    this.withholdMoves = false,
    this.overrides = const {},
  }) : super(apiKey: 'key');
  String pgn;
  final Map<String, Object?> overrides;
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
      ...overrides,
    });
  }
}
