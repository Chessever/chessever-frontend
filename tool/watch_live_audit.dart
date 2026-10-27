// Read-only live watch smoke tour. Run with flutter-watchos and production
// public defines. This drives the actual app with pointer events, no fixtures.
import 'dart:ffi';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import 'package:chessever2/watch/ui/watch_replay_page.dart';
import 'package:chessever2/watch/core/watch_repository.dart';
import 'package:chessever2/watch/core/watch_models.dart';
import 'package:chessever2/watch/watch_controller.dart';
import 'package:chessever2/watch/watch_app.dart';
import 'package:chessever2/watch/ui/watch_board.dart';
import 'package:chessever2/watch/ui/watch_event_boards_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final native = DynamicLibrary.process();
  for (final symbol in [
    'chessever_watch_listen',
    'chessever_watch_stop',
    'chessever_watch_free',
  ]) {
    if (!native.providesSymbol(symbol)) throw StateError('Missing $symbol');
  }
  final repository = WatchRepository(
    apiKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  final controller = WatchController(repository: repository);
  await controller.initialize();
  runApp(ChessEverWatchApp(controller: controller));
  final driver = LiveWidgetController(WidgetsBinding.instance);
  WidgetController.hitTestWarningShouldBeFatal = true;
  Future<void> pause(String step) async {
    debugPrint('WATCH_AUDIT: $step');
    await driver.pump(const Duration(seconds: 3));
  }

  Future<void> waitFor(Finder target) async {
    for (var i = 0; i < 100; i++) {
      if (target.evaluate().isNotEmpty) return;
      await driver.pump(const Duration(milliseconds: 200));
    }
    throw StateError('Timed out waiting for $target');
  }

  Future<void> tapTarget(Finder target) async {
    final scroll = find.byType(Scrollable).last;
    final position = driver.state<ScrollableState>(scroll).position;
    position.jumpTo(0);
    await driver.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 150; i++) {
      if (target.evaluate().isNotEmpty) {
        final center = driver.getCenter(target);
        final screen = MediaQuery.sizeOf(driver.element(target));
        if (center.dy > 48 && center.dy < screen.height - 24) break;
        position.jumpTo(
          (position.pixels + center.dy - screen.height / 2).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      } else {
        position.jumpTo(
          (position.pixels + 80).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
      await driver.pump(const Duration(milliseconds: 100));
    }
    await driver.tap(target);
    await driver.pump(const Duration(milliseconds: 900));
  }

  Future<void> tap(String text) => tapTarget(find.text(text));

  await pause('Current events from production');
  await driver.drag(find.byType(CustomScrollView), const Offset(0, 180));
  await driver.pump(const Duration(seconds: 2));
  await pause('Pull to refresh on the real watch');
  await tap('My iPhone');
  await pause('Real paired account and connection');
  debugPrint(
    'WATCH_AUDIT: counterpart installed=${controller.connection.counterpartInstalled}, reachable=${controller.connection.reachable}',
  );
  await tap('Sync with iPhone');
  await pause('Sync requested through WatchConnectivity');
  await tap('Back');
  final event = controller.events.first;
  await tap(event.name);
  await waitFor(find.byType(WatchBoardTile).first);
  await pause('One tap from Current opens real boards');
  final tile = driver.widget<WatchBoardTile>(find.byType(WatchBoardTile).first);
  final selectedGame = tile.game;
  final selectedTour = (await repository.tours(
    event.id,
  )).where((t) => t.id == selectedGame.tourId).first;
  await tap('Standings');
  if (selectedTour.players.isNotEmpty) {
    await waitFor(find.text(selectedTour.standings.first.name));
  }
  await pause('Published standings and federation flags');
  await tap('Back');
  await tapTarget(find.byType(WatchBoardTile).first);
  await waitFor(find.byType(WatchBoard));
  await pause('Full real game tools');
  await tap('Review moves');
  await waitFor(find.byType(WatchReplayPage));
  await waitFor(find.byType(WatchBoard));
  final replayFen = driver.widget<WatchBoard>(find.byType(WatchBoard)).fen;
  if (!WatchCrown.instance.isEnabled) {
    throw StateError('Replay did not claim Crown');
  }
  await pause('Recorded game snapshot, Crown controls moves');
  final crownDelta = native
      .lookupFunction<Void Function(Double), void Function(double)>(
        'flutter_watchos_crown_push_delta',
      );
  crownDelta(-0.75);
  await driver.pump(const Duration(milliseconds: 500));
  if (driver.widget<WatchBoard>(find.byType(WatchBoard)).fen == replayFen) {
    throw StateError('Native Crown delta did not change the replay position');
  }
  await pause(
    'Simulated Crown delta through native FFI moved back three plies',
  );
  await tapTarget(find.bySemanticsLabel('Next move'));
  await pause('Touch button advances the same recorded game');
  await tapTarget(find.byType(WatchBoard));
  if (WatchCrown.instance.isEnabled) {
    throw StateError('Board tap did not release Crown');
  }
  await pause('Board tap restores native Crown scrolling');
  await tap('Crown: scroll');
  await pause('Move review reactivated without changing the selected move');
  await tap('Done');
  if (WatchCrown.instance.isEnabled) {
    throw StateError('Done did not release Crown');
  }
  await pause('Done restores game tools and Crown scrolling');
  final players = selectedGame.players!;
  await tap('Black at bottom');
  driver
      .state<ScrollableState>(find.byType(Scrollable).last)
      .position
      .jumpTo(0);
  await driver.pump(const Duration(milliseconds: 300));
  await pause('Flipped board');
  if (!driver.widget<WatchBoard>(find.byType(WatchBoard)).flipped) {
    throw StateError('Board flip failed');
  }
  await tap('Open on iPhone');
  await driver.pump(const Duration(seconds: 9));
  final handoffAccepted = find.text('Sent to iPhone.').evaluate().isNotEmpty;
  debugPrint('WATCH_AUDIT: handoff accepted=$handoffAccepted');
  await pause('Phone handoff result');
  final player = selectedTour.players
      .where((p) => watchPlayerMatches(players[0], p))
      .firstOrNull;
  if (player != null) {
    await tap(players[0].name);
    await waitFor(
      find.text(
        player.score == null ? 'Score unavailable' : watchStandingScore(player),
      ),
    );
    await pause('Published player scorecard');
    await tap('Back');
  }
  await tap('Back to games');
  await pause('Returned to event boards');
  await tap('Back to Current');
  await pause('Returned to Current');
  if (const bool.fromEnvironment('WATCH_REQUIRE_PHONE', defaultValue: true) &&
      !handoffAccepted) {
    throw StateError('The iPhone did not acknowledge the game handoff.');
  }
  debugPrint('WATCH_AUDIT: COMPLETE');
}
