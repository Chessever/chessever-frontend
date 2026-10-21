import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Regression (app feedback, 35.42.0): Favorites and Countrymen list their
/// games through [LibraryGameCard], which printed the result of a finished
/// broadcast game even with the event's No Spoilers on. The Today page, drawn
/// with the event's own game card, hid it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const off = EventNoSpoilersState(enabled: false, isLoading: false);
  const on = EventNoSpoilersState(enabled: true, isLoading: false);
  const loading = EventNoSpoilersState();

  Future<void> pumpCard(
    WidgetTester tester, {
    required GamesTourModel game,
    required EventNoSpoilersState spoilers,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          engineSettingsProviderNew.overrideWith(
            () => _TestEngineSettingsNotifier(const EngineSettings()),
          ),
          eventNoSpoilersProvider.overrideWith(
            (ref, tourId) => _TestEventNoSpoilersController(
              ref: ref,
              tourId: tourId,
              loadedState: spoilers,
            ),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 360,
                    child: LibraryGameCard(game: game, onTap: () {}),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a finished broadcast game hides its result under No Spoilers', (
    tester,
  ) async {
    await pumpCard(tester, game: _game(GameStatus.draw), spoilers: on);

    expect(find.text('½'), findsNothing);
  });

  testWidgets(
    'a finished broadcast game stays hidden while the setting loads',
    (tester) async {
      await pumpCard(
        tester,
        game: _game(GameStatus.whiteWins),
        spoilers: loading,
      );

      expect(find.text('1'), findsNothing);
      expect(find.text('0'), findsNothing);
    },
  );

  testWidgets(
    'a finished broadcast game shows its result with No Spoilers off',
    (tester) async {
      await pumpCard(tester, game: _game(GameStatus.draw), spoilers: off);

      expect(find.text('½'), findsNWidgets(2));
    },
  );

  testWidgets('an archive game keeps its result: No Spoilers is per event', (
    tester,
  ) async {
    await pumpCard(
      tester,
      game: _game(GameStatus.draw, source: GameSource.gamebase),
      spoilers: on,
    );

    expect(find.text('½'), findsNWidgets(2));
  });

  testWidgets('a live broadcast game shows LIVE instead of its evaluation', (
    tester,
  ) async {
    await pumpCard(
      tester,
      game: _game(GameStatus.ongoing, hasStarted: true),
      spoilers: on,
    );

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.byType(ChessProgressBar), findsNothing);
  });
}

GamesTourModel _game(
  GameStatus status, {
  GameSource source = GameSource.supabase,
  bool hasStarted = true,
}) {
  return GamesTourModel(
    gameId: 'no-spoilers-list-row',
    source: source,
    whitePlayer: _player('Carlsen, Magnus'),
    blackPlayer: _player('Nakamura, Hikaru'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    // Clocks left on so a live game is not read as lost on time.
    whiteClockCentiseconds: 60000,
    blackClockCentiseconds: 60000,
    whiteClockSeconds: 600,
    blackClockSeconds: 600,
    gameStatus: status,
    roundId: 'r1',
    tourId: 't1',
    fen: hasStarted
        ? 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2'
        : 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    lastMove: hasStarted ? 'e7e5' : null,
  );
}

PlayerCard _player(String name) {
  return PlayerCard(
    name: name,
    federation: 'NOR',
    title: 'GM',
    rating: 2830,
    countryCode: 'NOR',
    team: null,
  );
}

class _TestEventNoSpoilersController extends EventNoSpoilersController {
  _TestEventNoSpoilersController({
    required super.ref,
    required super.tourId,
    required this.loadedState,
  });

  final EventNoSpoilersState loadedState;

  @override
  Future<void> load() async {
    state = loadedState;
  }
}

class _TestEngineSettingsNotifier extends EngineSettingsNotifierNew {
  _TestEngineSettingsNotifier(this.settings);

  final EngineSettings settings;

  @override
  Future<EngineSettings> build() async => settings;
}
