import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/widgets/gamebase_explorer_view.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository()
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  @override
  Future<GamebaseResponse> getMoveAggregates({
    required String fen,
    List<String> moves = const [],
    String? playerId,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
    String? color,
    String? result,
    int? yearFrom,
    int? yearTo,
    bool? isOnline,
  }) async {
    return const GamebaseResponse(
      status: 'success',
      data: GamebaseData(moves: []),
    );
  }
}

GamesTourModel _dummyGame() {
  final white = PlayerCard(
    name: 'White',
    federation: 'TR',
    title: '',
    rating: 0,
    countryCode: 'TR',
    team: null,
  );
  final black = PlayerCard(
    name: 'Black',
    federation: 'TR',
    title: '',
    rating: 0,
    countryCode: 'TR',
    team: null,
  );

  return GamesTourModel(
    gameId: 'g1',
    whitePlayer: white,
    blackPlayer: black,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'r1',
    tourId: 't1',
  );
}

void main() {
  testWidgets('GamebaseExplorerView uses analysis position FEN', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        gamebaseRepositoryProvider.overrideWithValue(_FakeGamebaseRepository()),
      ],
    );
    addTearDown(container.dispose);

    const analysisFen =
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
    final position = Chess.fromSetup(Setup.parseFen(analysisFen));

    final state = ChessBoardStateNew(
      game: _dummyGame(),
      isAnalysisMode: true,
      position: null,
      analysisState: AnalysisBoardState(position: position),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: GamebaseExplorerView(
                  state: state,
                  onMoveSelected: (_) {},
                ),
              );
            },
          ),
        ),
      ),
    );

    // useEffect schedules setPosition via a microtask.
    await tester.pump();

    expect(container.read(gamebaseExplorerProvider).currentFen, analysisFen);

    // Let the debounced fetch timer complete to avoid pending timers.
    await tester.pump(const Duration(milliseconds: 250));
  });
}
