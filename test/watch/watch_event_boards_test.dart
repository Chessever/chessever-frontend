import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/watch/core/watch_models.dart';
import 'package:chessever2/watch/core/watch_repository.dart';
import 'package:chessever2/watch/ui/watch_event_boards_page.dart';
import 'package:chessever2/watch/ui/watch_board.dart';
import 'package:chessever2/watch/ui/watch_round_wheel.dart';
import 'package:chessever2/watch/ui/watch_widgets.dart';
import 'package:chessever2/watch/watch_app.dart';
import 'package:chessever2/watch/watch_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';
import 'watch_core_test.dart' show fixtureGame;

class _BoardsRepository extends WatchRepository {
  _BoardsRepository({this.teams = false}) : super(apiKey: 'key');
  final bool teams;
  final requestedRounds = <String>[];
  bool fail = false;
  @override
  Future<String?> eventArtwork(String eventId) async => null;
  @override
  Future<List<WatchTour>> tours(String eventId) async => [
    WatchTour(id: 'tour1', eventId: eventId, name: 'Open', players: []),
  ];
  @override
  Future<List<WatchRound>> rounds(String tourId) async => [
    const WatchRound(id: 'older', name: 'Round 1'),
    WatchRound(
      id: 'current',
      name: 'Round 2',
      startsAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    WatchRound(
      id: 'future',
      name: 'Round 3',
      startsAt: DateTime.now().add(const Duration(days: 1)),
    ),
  ];
  @override
  Future<List<Games>> games(String roundId, {int offset = 0}) async {
    requestedRounds.add(roundId);
    if (fail) throw StateError('offline');
    if (!teams) {
      return List.generate(
        2,
        (i) =>
            Games.fromJson({...fixtureGame('$roundId-$i'), 'board_nr': i + 1}),
      );
    }
    // Two four-board matches; colours alternate by board as in team chess.
    const results = ['1-0', '1/2-1/2', '0-1', '*', '1-0', '0-1', '1-0', '1-0'];
    return List.generate(8, (i) {
      final first = i < 4;
      final (a, b) = first
          ? ('Hangzhou Qianjiang Lianyi', 'Shanghai Jianqiao University')
          : ('Beijing', 'Tianjin');
      final aWhite = i.isEven;
      return Games.fromJson({
        ...fixtureGame('$roundId-$i'),
        'board_nr': i + 1,
        'status': results[i],
        'players': [
          {
            'name': 'Wangzhang, Alexander-Maximilian $i',
            'fideId': 100 + i,
            'fed': 'CHN',
            'team': aWhite ? a : b,
          },
          {
            'name': 'Player $i',
            'fideId': 200 + i,
            'fed': 'CHN',
            'team': aWhite ? b : a,
          },
        ],
      });
    });
  }
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(184, 224);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(
    top: 45,
    left: 12,
    right: 12,
    bottom: 12,
  );
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
}

Future<void> _show(WidgetTester tester, Finder target) async {
  final scroll = find.byType(Scrollable).last;
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(target, 60, scrollable: scroll);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'event opens on its round, steps and wheels rounds, opens a full board, '
    'and retains boards offline',
    (tester) async {
      _size(tester);
      final repository = _BoardsRepository();
      final controller = WatchController(repository: repository)
        ..events = [const WatchEvent(id: 'event', name: 'Club Championship')]
        ..hasMore = false;
      await tester.pumpWidget(ChessEverWatchApp(controller: controller));
      await tester.tap(find.text('Club Championship'));
      await tester.pumpAndSettle();
      expect(repository.requestedRounds.first, 'current');
      expect(find.byType(WatchEventBoardsPage), findsOneWidget);
      // The latest started round, with its state, sits under the event.
      await _show(tester, find.byKey(const ValueKey('watch-round-name')));
      expect(find.text('Round 2'), findsOneWidget);
      expect(find.text('2 live'), findsOneWidget);
      expect(find.byType(WatchPairingRow), findsNWidgets(2));

      // A pairing opens the feed with that board in the resting slot.
      await _show(
        tester,
        find.byKey(const ValueKey('watch-pairing-current-1')),
      );
      await tester.tap(find.byKey(const ValueKey('watch-pairing-current-1')));
      await tester.pumpAndSettle();
      final second = find.byKey(const ValueKey('watch-board-current-1'));
      expect(second, findsOneWidget);
      expect(tester.getRect(second).top, closeTo(49, 1));
      final content = find.descendant(
        of: second,
        matching: find.byType(WatchPressable),
      );
      expect(tester.getRect(content).bottom, lessThanOrEqualTo(212));
      final board = tester.getRect(
        find.descendant(of: second, matching: find.byType(WatchBoard)),
      );
      for (final side in [0, 1]) {
        final strip = tester.getRect(
          find.descendant(
            of: second,
            matching: find.byKey(ValueKey('watch-player-strip-$side')),
          ),
        );
        expect(strip.left, board.left);
        expect(strip.right, board.right);
      }
      await _show(tester, find.text('Back to event'));
      await tester.tap(find.text('Back to event'));
      await tester.pumpAndSettle();

      // The arrow steps one round back.
      await _show(tester, find.bySemanticsLabel('Previous round'));
      await tester.tap(find.bySemanticsLabel('Previous round'));
      await tester.pumpAndSettle();
      expect(repository.requestedRounds.last, 'older');
      expect(find.text('Round 1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('watch-pairing-older-0')),
        findsOneWidget,
      );

      // The round wheel opens on the shown round and opens a tapped one.
      await _show(tester, find.byKey(const ValueKey('watch-round-name')));
      await tester.tap(find.byKey(const ValueKey('watch-round-name')));
      await tester.pumpAndSettle();
      expect(find.byType(WatchRoundWheelPage), findsOneWidget);
      expect(find.text('Showing now'), findsOneWidget);
      await tester.tap(find.text('Round 2'));
      await tester.pumpAndSettle();
      expect(find.byType(WatchRoundWheelPage), findsNothing);
      expect(repository.requestedRounds.last, 'current');
      expect(find.text('Round 2'), findsOneWidget);

      // Offline: refresh keeps the boards on screen and says so.
      repository.fail = true;
      await _show(tester, find.text('Refresh'));
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      await _show(tester, find.text('Offline · showing the last boards.'));
      expect(find.text('Offline · showing the last boards.'), findsOneWidget);
      expect(find.byType(WatchPairingRow), findsNWidgets(2));
      await _show(tester, find.text('Back to Current'));
      await tester.tap(find.text('Back to Current'));
      await tester.pumpAndSettle();
      expect(find.text('Club Championship'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('a team round shows matches with team scores and opens one '
      'match\'s boards', (tester) async {
    _size(tester);
    final controller =
        WatchController(repository: _BoardsRepository(teams: true))
          ..events = [const WatchEvent(id: 'event', name: 'Chinese League')]
          ..hasMore = false;
    await tester.pumpWidget(ChessEverWatchApp(controller: controller));
    await tester.tap(find.text('Chinese League'));
    await tester.pumpAndSettle();
    expect(find.byType(WatchPairingRow), findsNothing);
    final first = find.byKey(
      ValueKey(
        'watch-match-${watchTeamMatchKey('Hangzhou Qianjiang Lianyi', 'Shanghai Jianqiao University')}',
      ),
    );
    await _show(tester, first);
    // Long team names stay inside the card.
    final card = tester.getRect(first);
    for (final name in [
      'Hangzhou Qianjiang Lianyi',
      'Shanghai Jianqiao University',
    ]) {
      final text = tester.getRect(find.text(name));
      expect(text.right, lessThanOrEqualTo(card.right));
    }
    // Board 1 home White wins, board 2 draw, board 3 home White loses,
    // board 4 still playing: 1½ – 1½, read board by board as 1 ½ 0 •.
    expect(
      find.descendant(of: first, matching: find.text('1½')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: first,
        matching: find.text('1\u2009\u2009½\u2009\u20090\u2009\u2009•'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('Live')),
      findsOneWidget,
    );
    // Beijing: 1-0 home, 0-1 with Beijing Black → Beijing, 1-0 home,
    // 1-0 with Beijing Black → Tianjin: 3 – 1, final.
    final second = find.byKey(
      ValueKey('watch-match-${watchTeamMatchKey('Beijing', 'Tianjin')}'),
    );
    await _show(tester, second);
    expect(
      find.descendant(of: second, matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: second, matching: find.text('Final')),
      findsOneWidget,
    );
    await _show(tester, find.text('Standings'));
    expect(find.text('Standings'), findsOneWidget);
    await _show(tester, second);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(find.byType(WatchBoardTile), findsWidgets);
    expect(find.byKey(const ValueKey('watch-board-current-0')), findsNothing);
    expect(find.byKey(const ValueKey('watch-board-current-4')), findsOneWidget);
    // A name too long for the strip falls back to surname and initial.
    // (The test font is wider than SF, so it may fall back to the surname.)
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == 'Wangzhang, A.' || w.data == 'Wangzhang') &&
            w.semanticsLabel!.startsWith('Wangzhang, Alexander-Maximilian'),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('a recorded wrist flick steps the real feed between boards', (
    tester,
  ) async {
    _size(tester);
    final gyro = StreamController<GyroscopeEvent>.broadcast();
    WatchBoardsFeedPage.debugGyroscope = () => gyro.stream;
    addTearDown(() {
      WatchBoardsFeedPage.debugGyroscope = null;
      gyro.close();
    });
    final controller = WatchController(repository: _BoardsRepository())
      ..events = [const WatchEvent(id: 'event', name: 'Club Championship')]
      ..hasMore = false;
    await tester.pumpWidget(ChessEverWatchApp(controller: controller));
    await tester.tap(find.text('Club Championship'));
    await tester.pumpAndSettle();
    expect(gyro.hasListener, isFalse, reason: 'event page does not listen');
    await _show(tester, find.byKey(const ValueKey('watch-pairing-current-0')));
    await tester.tap(find.byKey(const ValueKey('watch-pairing-current-0')));
    await tester.pumpAndSettle();
    expect(gyro.hasListener, isTrue, reason: 'feed listens while visible');

    // A real flick recorded at 50 Hz: out past 6 rad/s, snap back.
    Future<void> flick(double sign) async {
      for (final x in [1.0, 7.5, 2.0, -5.0, -0.5]) {
        gyro.add(GyroscopeEvent(sign * x, 0.6, 0.4, DateTime.now()));
      }
      await tester.pumpAndSettle();
    }

    double top(int i) =>
        tester.getRect(find.byKey(ValueKey('watch-board-current-$i'))).top;
    final restingTop = top(0);
    await flick(1);
    expect(top(1), closeTo(restingTop, 1), reason: 'board 2 now in place');
    // The flick cooldown runs on real time; wait it out for real.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 950)),
    );
    await flick(-1);
    expect(top(0), closeTo(restingTop, 1), reason: 'back on board 1');

    // Opening a game covers the feed: the gyroscope must stop.
    await tester.tap(find.byKey(const ValueKey('watch-board-current-0')));
    await tester.pumpAndSettle();
    expect(gyro.hasListener, isFalse);
  });
}
