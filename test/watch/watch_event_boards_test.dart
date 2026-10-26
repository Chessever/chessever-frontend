import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/watch/core/watch_models.dart';
import 'package:chessever2/watch/core/watch_repository.dart';
import 'package:chessever2/watch/ui/watch_event_boards_page.dart';
import 'package:chessever2/watch/ui/watch_board.dart';
import 'package:chessever2/watch/watch_app.dart';
import 'package:chessever2/watch/watch_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
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
        matching: find.byType(CupertinoButton),
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
        matching: find.byType(CupertinoButton),
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
}
