import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/watch/core/watch_models.dart';
import 'package:chessever2/watch/core/watch_repository.dart';
import 'package:chessever2/watch/ui/watch_event_boards_page.dart';
import 'package:chessever2/watch/ui/watch_board.dart';
import 'package:chessever2/watch/ui/watch_widgets.dart';
import 'package:chessever2/watch/watch_app.dart';
import 'package:chessever2/watch/watch_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';
import 'watch_core_test.dart' show fixtureGame;

class _BoardsRepository extends WatchRepository {
  _BoardsRepository() : super(apiKey: 'key');
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
    return List.generate(
      2,
      (i) => Games.fromJson({...fixtureGame('$roundId-$i'), 'board_nr': i + 1}),
    );
  }
}

void main() {
  testWidgets(
    'event opens a full board in one tap, changes round, and retains it offline',
    (tester) async {
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
      final repository = _BoardsRepository();
      final controller = WatchController(repository: repository)
        ..events = [const WatchEvent(id: 'event', name: 'Club Championship')]
        ..hasMore = false;
      await tester.pumpWidget(ChessEverWatchApp(controller: controller));
      await tester.tap(find.text('Club Championship'));
      await tester.pumpAndSettle();
      expect(repository.requestedRounds.first, 'current');
      final first = find.byKey(const ValueKey('watch-board-current-0'));
      expect(first, findsOneWidget);
      expect(tester.getRect(first).top, greaterThanOrEqualTo(45));
      final firstContent = find.descendant(
        of: first,
        matching: find.byType(WatchPressable),
      );
      expect(tester.getRect(firstContent).bottom, lessThanOrEqualTo(212));
      final board = tester.getRect(
        find.descendant(of: first, matching: find.byType(WatchBoard)),
      );
      for (final side in [0, 1]) {
        final strip = tester.getRect(
          find.descendant(
            of: first,
            matching: find.byKey(ValueKey('watch-player-strip-$side')),
          ),
        );
        expect(strip.left, board.left);
        expect(strip.right, board.right);
      }
      Future<void> show(String label) async {
        final scroll = find.byType(Scrollable).last;
        tester.state<ScrollableState>(scroll).position.jumpTo(0);
        await tester.pump();
        await tester.scrollUntilVisible(
          find.text(label),
          60,
          scrollable: scroll,
        );
        await tester.pumpAndSettle();
      }

      await show('Round 2');
      await tester.tap(find.text('Round 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await show('Round 1');
      await tester.tap(find.text('Round 1'));
      await tester.pumpAndSettle();
      final older = find.byKey(const ValueKey('watch-board-older-0'));
      expect(older, findsOneWidget);
      expect(tester.getRect(older).top, greaterThanOrEqualTo(45));
      final olderContent = find.descendant(
        of: older,
        matching: find.byType(WatchPressable),
      );
      expect(tester.getRect(olderContent).bottom, lessThanOrEqualTo(212));
      repository.fail = true;
      await show('Refresh');
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      await show('Back to Current');
      expect(find.byType(WatchEventBoardsPage), findsOneWidget);
      await tester.tap(find.text('Back to Current'));
      await tester.pumpAndSettle();
      expect(find.text('Club Championship'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('a recorded wrist flick steps the real feed between boards', (
    tester,
  ) async {
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
    final gyro = StreamController<GyroscopeEvent>.broadcast();
    WatchEventBoardsPage.debugGyroscope = () => gyro.stream;
    addTearDown(() {
      WatchEventBoardsPage.debugGyroscope = null;
      gyro.close();
    });
    final controller = WatchController(repository: _BoardsRepository())
      ..events = [const WatchEvent(id: 'event', name: 'Club Championship')]
      ..hasMore = false;
    await tester.pumpWidget(ChessEverWatchApp(controller: controller));
    await tester.tap(find.text('Club Championship'));
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
