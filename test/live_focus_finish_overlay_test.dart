import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_focus_finish_hold_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/live_focus_finish_overlay.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

GamesTourModel _game({
  String id = 'g1',
  GameStatus status = GameStatus.ongoing,
}) {
  PlayerCard player(String name) => PlayerCard(
    name: name,
    federation: 'USA',
    title: 'GM',
    rating: 2700,
    countryCode: 'USA',
    team: null,
  );
  return GamesTourModel(
    gameId: id,
    whitePlayer: player('White'),
    blackPlayer: player('Black'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: status,
    roundId: 'round-1',
    tourId: 'tour-1',
  );
}

class _FakeEventNoSpoilersController extends EventNoSpoilersController {
  _FakeEventNoSpoilersController({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _Host extends StatefulWidget {
  const _Host({required this.initialGame});

  final GamesTourModel initialGame;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late GamesTourModel game = widget.initialGame;

  void finishAsWhite() {
    setState(() => game = _game(status: GameStatus.whiteWins));
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          height: 88,
          child: LiveFocusFinishLayer(
            game: game,
            child: const ColoredBox(
              color: Colors.blue,
              child: Center(child: Text('card')),
            ),
          ),
        ),
      ),
    );
  }
}

Future<ProviderContainer> _pumpHost(
  WidgetTester tester, {
  required GamesTourModel game,
  GameDisplayMode mode = GameDisplayMode.hideFinishedGames,
}) async {
  final container = ProviderContainer(
    overrides: [
      gameDisplayModeProvider.overrideWith((ref, tourId) => mode),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) =>
            _FakeEventNoSpoilersController(ref: ref, tourId: tourId),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: _Host(initialGame: game),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  test('gameResultScoreLabel matches board orientation', () {
    expect(
      gameResultScoreLabel(status: GameStatus.whiteWins),
      '1–0',
    );
    expect(
      gameResultScoreLabel(status: GameStatus.blackWins),
      '0–1',
    );
    expect(gameResultScoreLabel(status: GameStatus.draw), '½–½');
    expect(
      gameResultScoreLabel(
        status: GameStatus.whiteWins,
        comparison: MatchComparison.oppositeOrder,
      ),
      '0–1',
    );
  });

  testWidgets('shows score overlay while a just-finished board is held', (
    tester,
  ) async {
    final container = await _pumpHost(
      tester,
      game: _game(status: GameStatus.whiteWins),
    );
    container.read(liveFocusFinishHoldProvider('tour-1').notifier).hold('g1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(liveFocusFinishOverlayKey), findsOneWidget);
    expect(find.byKey(liveFocusFinishScoreKey), findsOneWidget);
    expect(find.text('1–0'), findsOneWidget);
    expect(find.text('card'), findsOneWidget);
    container.read(liveFocusFinishHoldProvider('tour-1').notifier).reset();
  });

  testWidgets('live-to-finished transition holds the card and shows the score', (
    tester,
  ) async {
    final container = await _pumpHost(tester, game: _game());
    expect(find.byKey(liveFocusFinishOverlayKey), findsNothing);

    tester.state<_HostState>(find.byType(_Host)).finishAsWhite();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(liveFocusFinishOverlayKey), findsOneWidget);
    expect(find.text('1–0'), findsOneWidget);
    container.read(liveFocusFinishHoldProvider('tour-1').notifier).reset();
  });

  testWidgets('does not hold when Live First is off', (tester) async {
    final container = await _pumpHost(
      tester,
      game: _game(),
      mode: GameDisplayMode.all,
    );
    tester.state<_HostState>(find.byType(_Host)).finishAsWhite();
    await tester.pump();
    await tester.pump();

    expect(
      container.read(liveFocusFinishHoldProvider('tour-1')).heldIds,
      isEmpty,
    );
    expect(find.byKey(liveFocusFinishOverlayKey), findsNothing);
  });

  testWidgets('structured exit keeps the card held until collapse finishes', (
    tester,
  ) async {
    final container = await _pumpHost(
      tester,
      game: _game(status: GameStatus.whiteWins),
    );
    container.read(liveFocusFinishHoldProvider('tour-1').notifier).hold('g1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1–0'), findsOneWidget);

    await tester.pump(kLiveFocusFinishHoldDuration);
    expect(
      container.read(liveFocusFinishHoldProvider('tour-1')).phaseOf('g1'),
      LiveFocusFinishPhase.exiting,
    );
    expect(find.byKey(liveFocusFinishOverlayKey), findsOneWidget);

    await tester.pump(kLiveFocusFinishExitDuration);
    expect(
      container.read(liveFocusFinishHoldProvider('tour-1')).heldIds,
      isEmpty,
    );
    expect(find.byKey(liveFocusFinishOverlayKey), findsNothing);
    expect(find.text('card'), findsOneWidget);
  });
}
