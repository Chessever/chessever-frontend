import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets(
    'cold For You player-name tap carries explicit event games to scorecard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final games = [
        _game(id: 'round-1', opponent: 'Opponent One'),
        _game(id: 'round-2', opponent: 'Opponent Two'),
      ];
      final container = ProviderContainer(
        overrides: [
          boardSettingsProviderNew.overrideWith(_TestBoardSettingsNotifier.new),
          engineSettingsProviderNew.overrideWith(
            _TestEngineSettingsNotifier.new,
          ),
          playerTourScreenProvider.overrideWith(
            _EmptyPlayerTourScreenNotifier.new,
          ),
          eventNoSpoilersProvider.overrideWith(
            (ref, tourId) =>
                _TestEventNoSpoilersController(ref: ref, tourId: tourId),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(chessboardViewFromProviderNew),
        ChessboardView.tour,
        reason: 'the app starts with the legacy global default',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            routes: {
              '/scorecard_screen':
                  (_) => const Scaffold(body: Text('scorecard')),
            },
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: GameCardWrapperWidget(
                    game: games.first,
                    gamesData: GamesScreenModel(
                      gamesTourModels: games,
                      pinnedGamedIs: const [],
                    ),
                    gameIndex: 0,
                    isChessBoardVisible: true,
                    viewSource: ChessboardView.forYou,
                    streamEnabled: false,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.textContaining('Player One', findRichText: true).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('scorecard'), findsOneWidget);
      expect(container.read(scoreCardHasEventContextProvider), isTrue);
      expect(
        container
            .read(scoreCardGamesContextProvider)
            ?.map((game) => game.gameId)
            .toList(),
        ['round-1', 'round-2'],
      );
      expect(
        container.read(chessboardViewFromProviderNew),
        ChessboardView.forYou,
      );

      // Let the board's short keep-alive timer expire inside fake async.
      await tester.pump(const Duration(seconds: 3));
    },
  );
}

class _TestEventNoSpoilersController extends EventNoSpoilersController {
  _TestEventNoSpoilersController({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _EmptyPlayerTourScreenNotifier extends PlayerTourScreenNotifier {
  @override
  Future<List<PlayerStandingModel>> build() async => const [];
}

class _TestEngineSettingsNotifier extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false);
}

class _TestBoardSettingsNotifier extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

GamesTourModel _game({required String id, required String opponent}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: _player('Player One', fideId: 101),
    blackPlayer: _player(opponent, fideId: id.hashCode.abs()),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: id,
    roundSlug: id,
    tourId: 'cold-tour',
    tourSlug: 'cold-event',
    lastMove: 'e2e4',
    fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
  );
}

PlayerCard _player(String name, {required int fideId}) {
  return PlayerCard(
    name: name,
    federation: 'USA',
    title: 'GM',
    rating: 2500,
    countryCode: 'USA',
    fideId: fideId,
    team: null,
  );
}
