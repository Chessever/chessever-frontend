import 'dart:async';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/watch/core/watch_models.dart';
import 'package:chessever2/watch/core/watch_repository.dart';
import 'package:chessever2/watch/ui/watch_event_boards_page.dart';
import 'package:chessever2/watch/ui/watch_game_page.dart';
import 'package:chessever2/watch/ui/watch_round_wheel.dart';
import 'package:chessever2/watch/watch_app.dart';
import 'package:chessever2/watch/watch_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'watch_core_test.dart' show fixtureGame;
import 'watch_review_capture.dart';

class _CrownBindings extends WatchOSNativeBindings {
  _CrownBindings() : super.forTesting();
  int mode = 0;
  double pending = 0;
  @override
  bool get alwaysOnActive => false;
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

/// An event laid out the way the feed serves it: sections, their rounds,
/// and every board without a position. Positions come by id, on request.
class _BoardsRepository extends WatchRepository {
  _BoardsRepository({this.teams = false, this.sections = 1})
    : super(apiKey: 'key');
  final bool teams;
  final int sections;
  final requestedIds = <String>[];
  int layouts = 0;
  bool fail = false;

  @override
  Future<String?> eventArtwork(String eventId) async => null;

  @override
  Future<List<WatchTour>> tours(String eventId) async {
    if (fail) throw StateError('offline');
    layouts++;
    return [
      WatchTour(
        id: 'tour1',
        eventId: eventId,
        name: 'Open',
        avgElo: 2600,
        players: [],
      ),
      if (sections > 1)
        WatchTour(
          id: 'tour2',
          eventId: eventId,
          name: 'Women',
          avgElo: 2400,
          players: [],
        ),
    ];
  }

  @override
  Future<List<WatchRound>> eventRounds(Iterable<String> tourIds) async => [
    for (final tour in tourIds) ...[
      WatchRound(
        id: '$tour-older',
        name: 'Round 1',
        tourId: tour,
        startsAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      WatchRound(
        id: '$tour-current',
        name: 'Round 2',
        tourId: tour,
        startsAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      WatchRound(
        id: '$tour-future',
        name: 'Round 3',
        tourId: tour,
        startsAt: DateTime.now().add(const Duration(days: 1)),
      ),
    ],
  ];

  Map<String, Object?> _layout(
    String id, {
    required String tour,
    required String round,
    required int board,
    required String status,
    bool moved = true,
  }) => {
    ...fixtureGame(id, round: round),
    'tour_id': tour,
    'board_nr': board,
    'status': status,
    'fen': null,
    'last_move': moved ? 'e2e4' : null,
    'last_clock_white': null,
    'last_clock_black': null,
    'players': [
      {'name': 'White $tour $board', 'fideId': 100 + board, 'fed': 'NOR'},
      {'name': 'Black $tour $board', 'fideId': 200 + board, 'fed': 'IND'},
    ],
  };

  List<Map<String, Object?>> _rows() => [
    for (final tour in ['tour1', if (sections > 1) 'tour2']) ...[
      if (!teams) ...[
        for (var i = 0; i < 2; i++)
          _layout(
            '$tour-current-$i',
            tour: tour,
            round: '$tour-current',
            board: i + 1,
            status: '*',
          ),
        for (var i = 0; i < 2; i++)
          _layout(
            '$tour-older-$i',
            tour: tour,
            round: '$tour-older',
            board: i + 1,
            status: '1-0',
          ),
        _layout(
          '$tour-future-0',
          tour: tour,
          round: '$tour-future',
          board: 1,
          status: '*',
          moved: false,
        ),
      ],
      if (teams)
        // Two four-board matches; colours alternate by board as in team
        // chess.
        for (var i = 0; i < 8; i++)
          () {
            final first = i < 4;
            final (a, b) = first
                ? ('Hangzhou Qianjiang Lianyi', 'Shanghai Jianqiao University')
                : ('Beijing', 'Tianjin');
            final aWhite = i.isEven;
            const results = [
              '1-0',
              '1/2-1/2',
              '0-1',
              '*',
              '1-0',
              '0-1',
              '1-0',
              '1-0',
            ];
            return {
              ..._layout(
                '$tour-current-$i',
                tour: tour,
                round: '$tour-current',
                board: i + 1,
                status: results[i],
              ),
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
            };
          }(),
    ],
  ];

  @override
  Future<List<Games>> eventBoards(Iterable<String> tourIds) async {
    if (fail) throw StateError('offline');
    return _rows().map(Games.fromJson).toList();
  }

  @override
  Future<List<Games>> gamesByIds(Iterable<String> gameIds) async {
    requestedIds.addAll(gameIds);
    if (fail) throw StateError('offline');
    final rows = {for (final row in _rows()) row['id'] as String: row};
    return [
      for (final id in gameIds)
        if (rows[id] != null)
          Games.fromJson({
            ...rows[id]!,
            'fen': fixtureGame(id)['fen'],
            'last_clock_white': 3600,
            'last_clock_black': 1800,
          }),
    ];
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
  // 120 per step: a two-section event runs past 50 steps of 60.
  await tester.scrollUntilVisible(target, 120, scrollable: scroll);
  await tester.pumpAndSettle();
}

double _top(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey(key))).top;

void main() {
  late _CrownBindings bindings;
  setUpAll(watchReviewFonts);
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
    await tester.pumpAndSettle();
  }

  testWidgets(
    'an event is one list: latest round first with full boards, positions '
    'loaded as boards near the screen, the Crown stepping item by item, the '
    'wheel jumping rounds, and the boards kept offline',
    (tester) async {
      _size(tester);
      final repository = _BoardsRepository();
      final controller = WatchController(repository: repository)
        ..events = [const WatchEvent(id: 'event', name: 'Club Championship')]
        ..hasMore = false;
      await tester.pumpWidget(ChessEverWatchApp(controller: controller));
      await tester.tap(find.text('Club Championship'));
      await tester.pumpAndSettle();
      expect(find.byType(WatchEventBoardsPage), findsOneWidget);
      expect(repository.layouts, 1);

      // The round being played leads, with its boards right under it.
      expect(
        find.byKey(const ValueKey('watch-round-tour1-current')),
        findsOneWidget,
      );
      expect(find.text('2 live'), findsOneWidget);
      expect(find.byType(WatchBoardTile), findsWidgets);
      // Only the boards near the screen asked for their position; the
      // round a day away did not.
      expect(repository.requestedIds, contains('tour1-current-0'));
      expect(repository.requestedIds, isNot(contains('tour1-future-0')));
      await _show(
        tester,
        find.byKey(const ValueKey('watch-board-tour1-current-0')),
      );
      expect(find.text('60:00'), findsWidgets, reason: 'position arrived');

      // Rounds read latest first; the one still to come closes the list.
      final orderOf = <String>[];
      for (final id in ['tour1-current', 'tour1-older', 'tour1-future']) {
        await _show(tester, find.byKey(ValueKey('watch-round-$id')));
        orderOf.add(
          tester
              .state<ScrollableState>(find.byType(Scrollable).last)
              .position
              .pixels
              .toStringAsFixed(0),
        );
      }
      final offsets = orderOf.map(double.parse).toList();
      expect(offsets[0], lessThan(offsets[1]));
      expect(offsets[1], lessThan(offsets[2]));
      expect(repository.requestedIds, contains('tour1-future-0'));
      expect(find.text('Starts Tomorrow', skipOffstage: false), findsNothing);
      expect(
        find.textContaining('Starts', skipOffstage: false),
        findsOneWidget,
      );

      // The Crown is the list's own control: one detent, one item, landing
      // it in the resting slot under the clock; the finger still scrolls.
      expect(bindings.mode, 1, reason: 'crown in raw mode while reading');
      tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await turn(tester, 0.3);
      expect(_top(tester, 'watch-round-tour1-current'), closeTo(49, 1));
      await turn(tester, 0.3);
      expect(_top(tester, 'watch-board-tour1-current-0'), closeTo(49, 1));
      await turn(tester, -0.3);
      expect(_top(tester, 'watch-round-tour1-current'), closeTo(49, 1));

      // The round heading opens the wheel on this round; a tapped round
      // lands in the resting slot.
      await tester.tap(find.byKey(const ValueKey('watch-round-tour1-current')));
      await tester.pumpAndSettle();
      expect(find.byType(WatchRoundWheelPage), findsOneWidget);
      expect(find.text('Showing now'), findsOneWidget);
      expect(bindings.mode, 0, reason: 'the wheel scrolls natively');
      await tester.tap(find.text('Round 1'));
      await tester.pumpAndSettle();
      expect(find.byType(WatchRoundWheelPage), findsNothing);
      expect(_top(tester, 'watch-round-tour1-older'), closeTo(49, 1));
      expect(bindings.mode, 1);

      // A board opens its game tools and hands the Crown back.
      await tester.tap(find.byKey(const ValueKey('watch-board-tour1-older-0')));
      await tester.pumpAndSettle();
      expect(find.byType(WatchGamePage), findsOneWidget);
      expect(bindings.mode, 0);
      await _show(tester, find.text('Back to boards'));
      await tester.tap(find.text('Back to boards'));
      await tester.pumpAndSettle();
      expect(bindings.mode, 1);

      // Offline: refresh keeps the boards on screen and says so.
      repository.fail = true;
      await _show(tester, find.text('Refresh'));
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      await _show(tester, find.text('Offline · showing the last boards.'));
      expect(find.byType(WatchBoardTile), findsWidgets);
      await _show(tester, find.text('Back to Current'));
      await tester.tap(find.text('Back to Current'));
      await tester.pumpAndSettle();
      expect(find.text('Club Championship'), findsOneWidget);
      expect(bindings.mode, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'several sections read strongest first under their own headings, and '
    'Standings asks which section',
    (tester) async {
      _size(tester);
      final repository = _BoardsRepository(sections: 2);
      final controller = WatchController(repository: repository)
        ..events = [const WatchEvent(id: 'event', name: 'Grand Open')]
        ..hasMore = false;
      await tester.pumpWidget(
        watchReviewBoundary(ChessEverWatchApp(controller: controller)),
      );
      await tester.tap(find.text('Grand Open'));
      await tester.pumpAndSettle();
      await watchReviewShot(tester, 'event-sections-top');
      expect(find.text('2 sections'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('watch-category-tour1')),
        findsOneWidget,
      );
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Avg 2600 · 3 rounds'), findsOneWidget);
      final open = _top(tester, 'watch-category-tour1');
      await _show(tester, find.byKey(const ValueKey('watch-category-tour2')));
      expect(find.text('Women'), findsOneWidget);
      await watchReviewShot(tester, 'event-sections-women');
      // Every round of Open sits above Women.
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position;
      expect(scroll.pixels, greaterThan(open));
      expect(
        find.byKey(
          const ValueKey('watch-round-tour1-future'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      await _show(tester, find.text('Standings'));
      await tester.tap(find.text('Standings'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Women'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('a team round lists each match before its boards and a match '
      'card goes to them', (tester) async {
    _size(tester);
    final controller =
        WatchController(repository: _BoardsRepository(teams: true))
          ..events = [const WatchEvent(id: 'event', name: 'Chinese League')]
          ..hasMore = false;
    await tester.pumpWidget(
      watchReviewBoundary(ChessEverWatchApp(controller: controller)),
    );
    await tester.tap(find.text('Chinese League'));
    await tester.pumpAndSettle();
    final first = find.byKey(
      ValueKey(
        'watch-match-tour1-current-${watchTeamMatchKey('Hangzhou Qianjiang Lianyi', 'Shanghai Jianqiao University')}',
      ),
    );
    await _show(tester, first);
    await watchReviewShot(tester, 'event-team-match');
    // Long team names stay inside the card.
    final card = tester.getRect(first);
    for (final name in [
      'Hangzhou Qianjiang Lianyi',
      'Shanghai Jianqiao University',
    ]) {
      expect(
        tester.getRect(find.text(name)).right,
        lessThanOrEqualTo(card.right),
      );
    }
    // Board 1 home White wins, board 2 draw, board 3 home White loses,
    // board 4 still playing: 1½ – 1½, read board by board as 1 ½ 0 •.
    expect(
      find.descendant(of: first, matching: find.text('1½')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: first, matching: find.text('1  ½  0  •')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('Live')),
      findsOneWidget,
    );
    // The match's boards follow its card.
    final board1 = find.byKey(const ValueKey('watch-board-tour1-current-0'));
    expect(tester.getRect(board1).top, greaterThanOrEqualTo(card.bottom));
    // Beijing: 1-0 home, 0-1 with Beijing Black → Beijing, 1-0 home,
    // 1-0 with Beijing Black → Tianjin: 3 – 1, final.
    final second = find.byKey(
      ValueKey(
        'watch-match-tour1-current-${watchTeamMatchKey('Beijing', 'Tianjin')}',
      ),
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
    // Tapping the card lands its first board in the resting slot.
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(_top(tester, 'watch-board-tour1-current-4'), closeTo(49, 1));
    await watchReviewShot(tester, 'event-team-board');
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

  testWidgets('a recorded wrist flick steps board to board past the headings', (
    tester,
  ) async {
    _size(tester);
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
    expect(gyro.hasListener, isFalse, reason: 'Current does not listen');
    await tester.tap(find.text('Club Championship'));
    await tester.pumpAndSettle();
    expect(gyro.hasListener, isTrue, reason: 'the list listens while shown');

    // A real flick recorded at 50 Hz: out past 6 rad/s, snap back.
    Future<void> flick(double sign) async {
      for (final x in [1.0, 7.5, 2.0, -5.0, -0.5]) {
        gyro.add(GyroscopeEvent(sign * x, 0.6, 0.4, DateTime.now()));
      }
      await tester.pumpAndSettle();
    }

    await flick(1);
    expect(_top(tester, 'watch-board-tour1-current-0'), closeTo(49, 1));
    // The flick cooldown runs on real time; wait it out for real.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 950)),
    );
    await flick(1);
    expect(_top(tester, 'watch-board-tour1-current-1'), closeTo(49, 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 950)),
    );
    // Back over the round heading, straight to the earlier board.
    await flick(-1);
    expect(_top(tester, 'watch-board-tour1-current-0'), closeTo(49, 1));

    // Opening a game covers the list: the gyroscope must stop.
    await tester.tap(find.byKey(const ValueKey('watch-board-tour1-current-0')));
    await tester.pumpAndSettle();
    expect(gyro.hasListener, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
