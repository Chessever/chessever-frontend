import 'dart:convert';
import 'package:chessever2/watch/core/watch_replay.dart';
import 'package:chessever2/watch/core/watch_repository.dart';
import 'package:chessever2/watch/ui/watch_board.dart';
import 'package:chessever2/watch/ui/watch_replay_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
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
      await tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              child: const Text('Open'),
              onPressed: () {
                Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => WatchReplayPage(loadPgn: () async => pgn),
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
      await tester.tap(find.byType(WatchBoard));
      await tester.pumpAndSettle();
      expect(bindings.mode, 0);
      await show(tester, find.text('Crown: scroll'));
      await tester.tap(find.text('Crown: scroll'));
      await tester.pumpAndSettle();
      expect(bindings.mode, 1);
      await show(tester, find.text('Done'));
      await tester.tap(find.text('Done'));
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
      CupertinoApp(
        navigatorKey: nav,
        home: WatchReplayPage(loadPgn: () async => pgn),
      ),
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

  testWidgets('missing history keeps scrolling and an actionable retry', (
    tester,
  ) async {
    var tries = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: WatchReplayPage(
          loadPgn: () async {
            tries++;
            return tries == 1 ? null : pgn;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(bindings.mode, 0);
    expect(find.text('Moves have not been published yet.'), findsOneWidget);
    await show(tester, find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(bindings.mode, 1);
    expect(find.byType(WatchBoard), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
