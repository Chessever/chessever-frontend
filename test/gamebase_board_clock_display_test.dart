import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new_worker.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets(
    'Gamebase game displays available player clocks when initially opened',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      const rawPgn =
          '[White "White Player"]\n[Black "Black Player"]\n'
          '[Result "1-0"]\n\n1. e4 e5 2. Nf3 Nc6 1-0';
      final pgn =
          selectGamebaseBoardPgn(
            rawPgn: rawPgn,
            data: {
              'md': {
                'White': 'White Player',
                'Black': 'Black Player',
                'Result': '1-0',
              },
              'm': [
                {'u': 'e2e4', 'ct': '1:30:55'},
                {'u': 'e7e5', 'ct': '1:30:17'},
                {'u': 'g1f3', 'ct': '1:29:42'},
                {'u': 'b8c6', 'ct': '1:29:07'},
              ],
            },
          )!;
      final parsed = parsePgnWorker(pgn);
      final game = _game(pgn);
      final state = ChessBoardStateNew(
        game: game,
        position: parsed.finalPos,
        startingPosition: parsed.startingPos,
        lastMove: parsed.lastMove,
        allMoves: parsed.allMoves,
        moveSans: parsed.moveSans,
        currentMoveIndex: -1,
        pgnData: pgn,
        isLoadingMoves: false,
        isAnalysisMode: true,
        moveTimes: parsed.moveTimes,
        analysisState: AnalysisBoardState(
          startingPosition: parsed.startingPos,
          position: parsed.startingPos,
          currentMoveIndex: -1,
          allMoves: parsed.allMoves,
          moveSans: parsed.moveSans,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineSettingsProviderNew.overrideWith(
              _TestEngineSettingsNotifier.new,
            ),
            eventNoSpoilersProvider.overrideWith(
              (ref, tourId) =>
                  _TestEventNoSpoilersController(ref: ref, tourId: tourId),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: Column(
                    children: [
                      PlayerFirstRowDetailWidget(
                        playerView: PlayerView.boardView,
                        isWhitePlayer: true,
                        gamesTourModel: game,
                        chessBoardState: state,
                      ),
                      PlayerFirstRowDetailWidget(
                        playerView: PlayerView.boardView,
                        isWhitePlayer: false,
                        gamesTourModel: game,
                        chessBoardState: state,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1:30:55'), findsOneWidget);
      expect(find.text('1:30:17'), findsOneWidget);
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

class _TestEngineSettingsNotifier extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false);
}

GamesTourModel _game(String pgn) {
  return GamesTourModel(
    gameId: 'gamebase-clock-game',
    source: GameSource.gamebase,
    whitePlayer: _player('White Player', fideId: 1),
    blackPlayer: _player('Black Player', fideId: 2),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: 'gamebase_search',
    roundSlug: '1',
    tourId: 'Gamebase',
    pgn: pgn,
    fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
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
