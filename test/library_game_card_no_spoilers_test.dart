import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Regression (app feedback, 35.42.0): with No Spoilers on, the Favorites and
/// Countrymen list view still showed each game's result, while Today hid it.
/// Both lists draw broadcast games through [LibraryGameCard], which never
/// read the event's No Spoilers state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const startedFen =
      'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';

  GamesTourModel game({
    required GameStatus status,
    GameSource source = GameSource.supabase,
    int clockSeconds = 600,
  }) {
    return GamesTourModel(
      gameId: 'no-spoilers-card',
      source: source,
      whitePlayer: _player('Carlsen'),
      blackPlayer: _player('Nakamura'),
      whiteTimeDisplay: '10:00',
      blackTimeDisplay: '10:00',
      whiteClockCentiseconds: clockSeconds * 100,
      blackClockCentiseconds: clockSeconds * 100,
      whiteClockSeconds: clockSeconds,
      blackClockSeconds: clockSeconds,
      gameStatus: status,
      roundId: 'r1',
      tourId: 't1',
      fen: startedFen,
      lastMove: 'e7e5',
    );
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required GamesTourModel game,
    required bool noSpoilers,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          engineSettingsProviderNew.overrideWith(_TestEngineSettings.new),
          eventNoSpoilersProvider.overrideWith(
            (ref, tourId) => _TestNoSpoilers(
              ref: ref,
              tourId: tourId,
              loaded: EventNoSpoilersState(
                enabled: noSpoilers,
                isLoading: false,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: LibraryGameCard(
                  game: game,
                  eventName: 'Test Open',
                  onTap: () {},
                ),
              );
            },
          ),
        ),
      ),
    );
    // The second frame applies the overridden async settings and spoiler state.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('hides a finished broadcast result when No Spoilers is on', (
    tester,
  ) async {
    await pumpCard(
      tester,
      game: game(status: GameStatus.draw),
      noSpoilers: true,
    );

    expect(find.text('½'), findsNothing);
  });

  testWidgets('shows the result when No Spoilers is off', (tester) async {
    await pumpCard(
      tester,
      game: game(status: GameStatus.draw),
      noSpoilers: false,
    );

    expect(find.text('½'), findsNWidgets(2));
  });

  testWidgets('hides a result inferred from a flagged clock', (tester) async {
    // Stored status still says ongoing, but a clock at zero makes the card
    // infer a finished game before the DB catches up.
    await pumpCard(
      tester,
      game: game(status: GameStatus.ongoing, clockSeconds: 0),
      noSpoilers: true,
    );

    expect(find.text('½'), findsNothing);
  });

  testWidgets('shows LIVE instead of the eval bar for an ongoing game', (
    tester,
  ) async {
    await pumpCard(
      tester,
      game: game(status: GameStatus.ongoing),
      noSpoilers: true,
    );

    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('leaves archive games alone', (tester) async {
    await pumpCard(
      tester,
      game: game(status: GameStatus.draw, source: GameSource.gamebase),
      noSpoilers: true,
    );

    expect(find.text('½'), findsNWidgets(2));
  });
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

class _TestNoSpoilers extends EventNoSpoilersController {
  _TestNoSpoilers({
    required super.ref,
    required super.tourId,
    required this.loaded,
  });

  final EventNoSpoilersState loaded;

  @override
  Future<void> load() async {
    state = loaded;
  }
}

class _TestEngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();
}
