import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      anonKey: 'placeholder-anon-key',
    );
  });

  test(
    'event game navigation hydrates the tapped game with the latest PGN/FEN',
    () async {
      final moveTime = DateTime.utc(2026, 7, 7, 15);
      const stalePgn = '''
[Event "Titled Tuesday"]

1. e4 *
''';
      const finalPgn = '''
[Event "Titled Tuesday"]

1. e4 e5 2. Nf3 Nc6 1-0
''';
      const staleFen =
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
      const finalFen =
          'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';

      final staleCardGame = GamesTourModel.fromGame(
        _game(
          id: 'game-1',
          fen: staleFen,
          pgn: stalePgn,
          lastMove: 'e2e4',
          status: '*',
          lastMoveTime: moveTime,
        ),
      );
      final repository = _HydratingGameRepository(
        _game(
          id: 'game-1',
          fen: finalFen,
          pgn: finalPgn,
          lastMove: 'b8c6',
          status: '1-0',
          lastMoveTime: moveTime,
        ),
      );

      final container = ProviderContainer(
        overrides: [gameRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final (games, index) = await container
          .read(gameCardWrapperProvider)
          .debugResolveNavigation(
            orderedGames: [staleCardGame],
            gameIndex: 0,
            viewSource: ChessboardView.tour,
          );

      expect(repository.requests, ['game-1']);
      expect(index, 0);
      expect(games.single.pgn, finalPgn);
      expect(games.single.fen, finalFen);
      expect(games.single.lastMove, 'b8c6');
      expect(games.single.gameStatus, GameStatus.whiteWins);
    },
  );

  test(
    'event game navigation keeps a newer streamed card over an older fetched row',
    () async {
      final moveTime = DateTime.utc(2026, 7, 7, 15);
      const currentPgn = '''
[Event "Titled Tuesday"]

1. e4 e5 2. Nf3 Nc6 *
''';
      const olderPgn = '''
[Event "Titled Tuesday"]

1. e4 *
''';
      const currentFen =
          'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';
      const olderFen =
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';

      final currentCardGame = GamesTourModel.fromGame(
        _game(
          id: 'game-1',
          fen: currentFen,
          pgn: currentPgn,
          lastMove: 'b8c6',
          status: '*',
          lastMoveTime: moveTime,
        ),
      );
      final repository = _HydratingGameRepository(
        _game(
          id: 'game-1',
          fen: olderFen,
          pgn: olderPgn,
          lastMove: 'e2e4',
          status: '*',
          lastMoveTime: moveTime.subtract(const Duration(minutes: 1)),
        ),
      );

      final container = ProviderContainer(
        overrides: [gameRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final (games, index) = await container
          .read(gameCardWrapperProvider)
          .debugResolveNavigation(
            orderedGames: [currentCardGame],
            gameIndex: 0,
            viewSource: ChessboardView.tour,
          );

      expect(repository.requests, ['game-1']);
      expect(index, 0);
      expect(games.single.pgn, currentPgn);
      expect(games.single.fen, currentFen);
      expect(games.single.lastMove, 'b8c6');
    },
  );

  test('all live-card view sources hydrate through the same resolver', () async {
    final moveTime = DateTime.utc(2026, 7, 7, 15);
    const stalePgn = '''
[Event "Titled Tuesday"]

1. e4 *
''';
    const finalPgn = '''
[Event "Titled Tuesday"]

1. e4 e5 2. Nf3 Nc6 1-0
''';
    const staleFen =
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
    const finalFen =
        'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';

    for (final viewSource in [
      ChessboardView.tour,
      ChessboardView.forYou,
      ChessboardView.countryman,
      ChessboardView.favScorecard,
    ]) {
      final staleCardGame =
          GamesTourModel.fromGame(
            _game(
              id: 'game-1',
              fen: staleFen,
              pgn: stalePgn,
              lastMove: 'e2e4',
              status: '*',
              lastMoveTime: moveTime,
            ),
          ).copyWith(tourId: viewSource == ChessboardView.forYou ? '' : null);
      final repository = _HydratingGameRepository(
        _game(
          id: 'game-1',
          fen: finalFen,
          pgn: finalPgn,
          lastMove: 'b8c6',
          status: '1-0',
          lastMoveTime: moveTime,
        ),
      );
      final container = ProviderContainer(
        overrides: [gameRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final (games, index) = await container
          .read(gameCardWrapperProvider)
          .debugResolveNavigation(
            orderedGames: [staleCardGame],
            gameIndex: 0,
            viewSource: viewSource,
          );

      expect(repository.requests, ['game-1']);
      expect(index, 0);
      expect(
        games.single.pgn,
        finalPgn,
        reason: '$viewSource must not open the stale card PGN',
      );
      expect(games.single.fen, finalFen);
    }
  });
}

class _HydratingGameRepository extends GameRepository {
  _HydratingGameRepository(this.latestGame);

  final Games latestGame;
  final List<String> requests = [];

  @override
  Future<Games> getGameWithPGN(String gameId) async {
    requests.add(gameId);
    return latestGame;
  }
}

Games _game({
  required String id,
  required String fen,
  required String pgn,
  required String lastMove,
  required String status,
  required DateTime lastMoveTime,
}) {
  return Games(
    id: id,
    roundId: 'round-1',
    roundSlug: 'round-1',
    tourId: 'tour-1',
    tourSlug: 'tour-1',
    players: [_player(name: 'White'), _player(name: 'Black', fideId: 2)],
    fen: fen,
    pgn: pgn,
    lastMove: lastMove,
    status: status,
    lastMoveTime: lastMoveTime,
    boardNr: 1,
  );
}

Player _player({required String name, int fideId = 1}) {
  return Player(
    name: name,
    title: 'GM',
    rating: 2700,
    fideId: fideId,
    fed: 'USA',
    clock: 0,
    team: '',
  );
}
