import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/feed/race/race_client.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_flames.dart';
import 'package:chessever2/screens/feed/race/race_lobby_screen.dart';
import 'package:chessever2/screens/feed/race/race_stats_store.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'puzzle_race_fakes.dart';

class _TestBoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  RaceHarness h, {
  ThemeData? theme,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final container = ProviderContainer(
    overrides: [
      raceDepsProvider.overrideWithValue(h.deps()),
      boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
      raceServerStatsSourceProvider.overrideWithValue(
        FakeRaceServerStatsSource(),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const RaceLobbyScreen();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// Unmounts and closes the race inside the fake clock, so no race timer (the
/// heartbeat, a countdown) outlives the test.
Future<void> _unmount(WidgetTester tester) async {
  final scope = tester.widgetList<UncontrolledProviderScope>(
    find.byType(UncontrolledProviderScope),
  );
  final containers = [for (final s in scope) s.container];
  await tester.pumpWidget(const SizedBox.shrink());
  for (final c in containers) {
    c.dispose();
  }
  await tester.pump(const Duration(seconds: 1));
}

/// Lets socket events and zero-length timers run.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// Solo Survival from the lobby to the first puzzle on the board.
Future<ProviderContainer> _startSolo(WidgetTester tester, RaceHarness h) async {
  final container = await _pump(tester, h);
  await tester.tap(find.byKey(const ValueKey('race_start_solo')));
  await _settle(tester);
  h.server.last.push(snapshot());
  await _settle(tester);
  expect(h.server.last.sentTypes, contains('start'));
  h.server.last.push(snapshot(state: 'running', startedAt: h.clock - 2000));
  h.server.last.push(puzzle());
  await _settle(tester);
  return container;
}

/// Multiplayer Survival with Hikaru, from the room to this player's own
/// finish at 00:45.3 while Hikaru is still racing. The room's results are
/// frozen at this finish.
Future<FakeRaceSocket> _finishMultiplayer(
  WidgetTester tester,
  RaceHarness h,
) async {
  await _pump(tester, h);
  await tester.tap(find.byKey(const ValueKey('race_multiplayer')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('race_create_room')));
  await _settle(tester);
  final socket = h.server.last;
  final players = [player(), player(id: kRival, name: 'Hikaru', ready: true)];
  socket.push(snapshot(multiplayer: true, players: players));
  await _settle(tester);
  socket.push(
    snapshot(
      multiplayer: true,
      state: 'running',
      startedAt: h.clock - 2000,
      players: players,
    ),
  );
  socket.push(puzzle());
  await _settle(tester);
  socket.push(
    finished(
      playerId: kYou,
      reason: 'lives',
      roomFinished: false,
      results: [
        result(score: 3, mistakes: 3, elapsedMs: 45300, finishReason: 'lives'),
        result(
          rank: 2,
          id: kRival,
          name: 'Hikaru',
          score: 2,
          mistakes: 1,
          elapsedMs: 45300,
          finished: false,
        ),
      ],
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return socket;
}

Finder _inStandings(String text) => find.descendant(
  of: find.byKey(const ValueKey('race_standings')),
  matching: find.text(text),
);

void main() {
  testWidgets('no service configured: a calm state, one way back', (
    tester,
  ) async {
    final h = RaceHarness(configured: false);
    await _pump(tester, h);
    expect(find.text('Puzzle Race is almost here'), findsOneWidget);
    expect(find.text('Back to Feed'), findsOneWidget);
    expect(find.text('Start race'), findsNothing);
    expect(find.byKey(const ValueKey('race_mode_survival')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('lobby: the 2x2 choice, bests, and multiplayer asks to sign in', (
    tester,
  ) async {
    final h = RaceHarness();
    h.stats.bests = const RaceBests(survivalBest: 31, infiniteBest: 118);
    final container = await _pump(tester, h);
    await tester.pump();

    expect(find.text('Survival'), findsOneWidget);
    expect(find.text('Infinite'), findsOneWidget);
    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Multiplayer'), findsOneWidget);
    expect(find.text('Best 31'), findsOneWidget);
    expect(find.text('Best 118'), findsOneWidget);
    expect(find.text('Start race'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('race_mode_infinite')));
    await tester.pump();
    expect(container.read(raceControllerProvider).mode, RaceMode.infinite);

    await tester.tap(find.byKey(const ValueKey('race_multiplayer')));
    await tester.pump();
    expect(find.byKey(const ValueKey('race_sign_in_hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('race_sign_in')), findsOneWidget);
    expect(find.text('Create a room'), findsNothing);
    expect(h.api.creates, isEmpty);
    await _unmount(tester);
  });

  testWidgets('room: code, players, host start', (tester) async {
    final h = RaceHarness(token: 'jwt');
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('race_multiplayer')));
    await tester.pump();
    expect(find.text('Create a room'), findsOneWidget);
    expect(find.byKey(const ValueKey('race_code_field')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('race_create_room')));
    await _settle(tester);
    h.server.last.push(
      snapshot(
        multiplayer: true,
        players: [
          player(),
          player(id: kRival, name: 'Hikaru', ready: true),
        ],
      ),
    );
    await _settle(tester);

    expect(find.byKey(const ValueKey('race_room_code')), findsOneWidget);
    expect(find.text('7KQ2MX'), findsOneWidget);
    expect(find.text('Magnus'), findsOneWidget);
    expect(find.text(' (you)'), findsOneWidget);
    expect(find.text('Hikaru'), findsOneWidget);
    expect(find.text('Share invite'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('race_host_start')));
    await tester.pump();
    expect(h.server.last.sentTypes.last, 'start');
    await _unmount(tester);
  });

  testWidgets('a failed join keeps the way out: new code, new room', (
    tester,
  ) async {
    final h = RaceHarness(token: 'jwt');
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('race_multiplayer')));
    await tester.pump();

    h.server.failures.add(
      const RaceApiException('room_not_found', statusCode: 404),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('race_code_field')));
    await tester.enterText(
      find.byKey(const ValueKey('race_code_field')),
      '7KQ2MY',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('race_join')));
    await tester.tap(find.byKey(const ValueKey('race_join')));
    await _settle(tester);

    expect(
      find.text('No race has that code. Check it and try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('race_retry')), findsNothing);
    expect(find.byKey(const ValueKey('race_create_room')), findsOneWidget);
    expect(find.byKey(const ValueKey('race_join')), findsOneWidget);
    // The mistyped code comes back to be corrected.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('race_code_field')))
          .controller!
          .text,
      '7KQ2MY',
    );

    // A corrected code joins straight from here.
    await tester.ensureVisible(find.byKey(const ValueKey('race_code_field')));
    await tester.enterText(
      find.byKey(const ValueKey('race_code_field')),
      '7KQ2MX',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('race_join')));
    await tester.tap(find.byKey(const ValueKey('race_join')));
    await _settle(tester);
    expect(h.server.connects.last.uri.path, '/v1/races/7KQ2MX/ws');
    await _unmount(tester);
  });

  testWidgets('a network failure still offers Try again', (tester) async {
    final h = RaceHarness(token: 'jwt');
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('race_multiplayer')));
    await tester.pump();

    h.api.failures.add(const RaceApiException('network'));
    await tester.tap(find.byKey(const ValueKey('race_create_room')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('race_retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('race_create_room')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('race: frame, clock, lives, board, verdicts move the stream', (
    tester,
  ) async {
    final h = RaceHarness();
    final container = await _startSolo(tester, h);
    final socket = h.server.last;

    expect(find.byKey(const ValueKey('race_clock')), findsOneWidget);
    expect(find.text('00:02.0'), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('#1 · 812'), findsOneWidget);
    expect(find.bySemanticsLabel('3 lives left'), findsOneWidget);
    expect(find.byKey(const ValueKey('race_board_0')), findsOneWidget);
    expect(find.textContaining('Watch'), findsOneWidget);

    // The setup move plays once the page has landed.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Your move'), findsOneWidget);

    // The clock follows the room's start, not a local stopwatch.
    h.clock += 1500;
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('00:03.5'), findsOneWidget);

    // The player taps the rook, then a8: the move goes to the room, which
    // judges it. A solve, then straight on to the next puzzle.
    final board = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('race_board_0')),
        matching: find.byType(Chessboard),
      ),
    );
    final square = board.width / 8;
    await tester.tapAt(
      Offset(board.left + square / 2, board.bottom - square / 2),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(Offset(board.left + square / 2, board.top + square / 2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(socket.sentJson.last, {
      'type': 'move',
      'puzzleIndex': 0,
      'uci': 'a1a8',
      'ply': 1,
    });
    expect(container.read(raceControllerProvider).awaitingVerdict, isTrue);
    socket.push(verdict(score: 1, level: 1));
    socket.push(puzzle(index: 1, rating: 851, level: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('race_score')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('race_score'))).data,
      '1',
    );
    expect(find.text('Solved'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('race_board_1')), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('#2 · 851'), findsOneWidget);

    // A miss costs a heart.
    await tester.pump(const Duration(milliseconds: 400));
    container.read(raceControllerProvider.notifier).submitMove('b1b7');
    socket.push(verdict(index: 1, correct: false, score: 1, mistakes: 1));
    socket.push(puzzle(index: 2, level: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.bySemanticsLabel('2 lives left'), findsOneWidget);
    expect(find.text('Missed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await _unmount(tester);
  });

  /// Solo Survival down to its third miss, the room's `finished` right
  /// behind the verdict as the room sends them.
  Future<void> loseLastLife(WidgetTester tester, RaceHarness h) async {
    final container = await _startSolo(tester, h);
    final socket = h.server.last;
    await tester.pump(const Duration(milliseconds: 400));
    final race = container.read(raceControllerProvider.notifier);
    for (var i = 0; i < 3; i++) {
      race.submitMove('b1b7');
      socket.push(verdict(index: i, correct: false, score: 0, mistakes: i + 1));
      if (i < 2) {
        socket.push(puzzle(index: i + 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }
    }
    socket.push(
      finished(
        results: [result(mistakes: 3, elapsedMs: 9000, finishReason: 'lives')],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('the run-ending miss holds its board, then the results', (
    tester,
  ) async {
    final h = RaceHarness();
    await loseLastLife(tester, h);
    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('Out of lives'), findsNothing);
    // The finish is recorded at once; only the screen waits.
    expect(h.stats.recorded, hasLength(1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Out of lives'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('with reduced motion the results come at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final h = RaceHarness();
    await loseLastLife(tester, h);
    expect(find.text('Out of lives'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('results the room never confirmed say so', (tester) async {
    final h = RaceHarness();
    await _startSolo(tester, h);
    h.server.failures.addAll(const [
      RaceApiException('network'),
      RaceApiException('network'),
      RaceApiException('network'),
    ]);
    await h.server.last.drop(1006);
    await _settle(tester);
    expect(h.api.resultsRequests, ['7KQ2MX']);
    expect(find.byKey(const ValueKey('race_unconfirmed')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('stop asks first, then the results', (tester) async {
    final h = RaceHarness();
    final container = await _startSolo(tester, h);
    final socket = h.server.last;
    await tester.pump(const Duration(milliseconds: 400));

    container.read(raceControllerProvider.notifier).submitMove('a1a8');
    socket.push(verdict(score: 1, level: 1, elapsedMs: 4200));
    socket.push(puzzle(index: 1, level: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byKey(const ValueKey('race_stop')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('End this run?'), findsOneWidget);
    await tester.tap(find.text('End run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(socket.sentTypes.last, 'stop');

    socket.push(
      finished(
        results: [
          result(score: 1, level: 1, elapsedMs: 9400, finishReason: 'stopped'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Race over'), findsOneWidget);
    expect(find.byKey(const ValueKey('race_final_score')), findsOneWidget);
    expect(find.text('You ended the run'), findsOneWidget);
    expect(find.text('00:09.4'), findsOneWidget);
    expect(find.text('New best'), findsOneWidget);
    expect(find.text('Solved'), findsOneWidget);
    expect(find.text('2. Ra8#'), findsOneWidget);
    expect(find.text('Play again'), findsOneWidget);
    expect(find.bySemanticsLabel('Share result'), findsOneWidget);
    // The way back is named twice: the corner ("Feed") and the action row.
    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('Back to Feed'), findsOneWidget);
    expect(find.bySemanticsLabel('Back to Feed'), findsNWidgets(2));
    // One solve at 812 earns one flame, kept on this device for a guest.
    expect(find.text('+1 flame'), findsOneWidget);
    expect(find.text('Sign in to keep your flames'), findsOneWidget);
    expect(h.stats.recorded.single.score, 1);
    expect(h.stats.recorded.single.flames, 1);
    await _unmount(tester);
  });

  testWidgets('standings: a run that ends after yours reads done, then the '
      "room's time", (tester) async {
    final h = RaceHarness(token: 'jwt');
    final socket = await _finishMultiplayer(tester, h);

    expect(find.text('Race over'), findsOneWidget);
    expect(_inStandings('Magnus'), findsOneWidget);
    expect(_inStandings(' (you)'), findsOneWidget);
    expect(_inStandings('00:45.3'), findsOneWidget);
    expect(_inStandings('racing'), findsOneWidget);

    // Hikaru's run ends at 5:00. The room says so in a snapshot only; the
    // time frozen at this player's finish must not stand in for it.
    socket.push(
      snapshot(
        multiplayer: true,
        state: 'running',
        startedAt: h.clock - 2000,
        players: [
          player(score: 3, mistakes: 3, finished: true),
          player(
            id: kRival,
            name: 'Hikaru',
            score: 5,
            mistakes: 1,
            finished: true,
          ),
        ],
      ),
    );
    await _settle(tester);
    expect(_inStandings('racing'), findsNothing);
    expect(_inStandings('done'), findsOneWidget);
    expect(_inStandings('00:45.3'), findsOneWidget);
    expect(
      tester.getTopLeft(_inStandings('Hikaru')).dy,
      lessThan(tester.getTopLeft(_inStandings('Magnus')).dy),
    );

    // The room's final results carry the real time.
    socket.push(
      finished(
        playerId: kRival,
        reason: 'stopped',
        results: [
          result(
            id: kRival,
            name: 'Hikaru',
            score: 5,
            mistakes: 1,
            elapsedMs: 300000,
            finishReason: 'stopped',
          ),
          result(
            rank: 2,
            score: 3,
            mistakes: 3,
            elapsedMs: 45300,
            finishReason: 'lives',
          ),
        ],
      ),
    );
    await _settle(tester);
    expect(_inStandings('done'), findsNothing);
    expect(_inStandings('05:00.0'), findsOneWidget);
    expect(_inStandings('00:45.3'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('results fit a 360dp phone at the largest text', (tester) async {
    final h = RaceHarness(token: 'jwt');
    await _finishMultiplayer(tester, h);

    // The route clamps text scaling at 1.4; ask for more to prove it.
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    expect(tester.takeException(), isNull);

    void expectWhole(Finder finder) {
      final text = tester.renderObject<RenderParagraph>(finder);
      expect(text.didExceedMaxLines, isFalse);
      expect(
        text.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(text.size.width + 0.5),
      );
    }

    final title = find.byKey(const ValueKey('race_results_title'));
    expectWhole(title);
    expectWhole(_inStandings('00:45.3'));
    expectWhole(_inStandings('racing'));
    // With the test font's square glyphs the mode label cannot share the
    // title's line here, so it takes its own line under the title.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('race_results_mode'))).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
    );
    expectWhole(find.text('Back to Feed'));
    expectWhole(find.text('Play again'));
    expect(find.bySemanticsLabel('Share result'), findsOneWidget);
    // The corner control and the action row both stay at least 44 tall.
    expect(
      tester.getSize(find.byKey(const ValueKey('race_back'))).height,
      greaterThanOrEqualTo(44),
    );
    await _unmount(tester);
  });
}
