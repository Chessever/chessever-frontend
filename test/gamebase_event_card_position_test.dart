import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_game.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/live_game_position_resolver.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('virtual Gamebase event card displays the full game final position', () {
    final expectedPosition = resolveFinalPositionFromPgn(_fullPgn)!;

    final hydrated = hydrateGamebaseCardPosition(_virtualGame(), _fullPgn);

    expect(hydrated.pgn, _fullPgn.trim());
    expect(hydrated.fen, expectedPosition.fen);
    expect(hydrated.lastMove, expectedPosition.lastMoveUci);
    expect(
      hydrated.fen,
      isNot(startsWith('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR')),
    );
  });

  test(
    'visible Gamebase card provider fetches and applies its full PGN',
    () async {
      final container = ProviderContainer(
        overrides: [
          gameWithPgnByIdProvider.overrideWith((ref, gameId) async {
            expect(gameId, 'gamebase-game-1');
            return GamebaseGameWithPgn(
              id: gameId,
              date: DateTime.utc(2026, 1, 14),
              result: GameResult.whiteWins,
              timeControl: TimeControl.classical,
              pgn: _fullPgn,
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      final hydrated = await container.read(
        hydratedGamebaseCardProvider(_virtualGame()).future,
      );

      expect(hydrated.fen, resolveFinalPositionFromPgn(_fullPgn)!.fen);
      expect(hydrated.lastMove, 'a7a6');
    },
  );

  test('hydrates only finished Gamebase cards without a played position', () {
    final virtualGame = _virtualGame();

    expect(shouldHydrateGamebaseCard(virtualGame), isTrue);
    expect(
      shouldHydrateGamebaseCard(
        virtualGame.copyWith(source: GameSource.supabase),
      ),
      isFalse,
    );
    expect(
      shouldHydrateGamebaseCard(
        virtualGame.copyWith(gameStatus: GameStatus.ongoing),
      ),
      isFalse,
    );
    expect(
      shouldHydrateGamebaseCard(
        hydrateGamebaseCardPosition(virtualGame, _fullPgn),
      ),
      isFalse,
    );
  });
}

const _fullPgn = '''
[Event "Freestyle WCh Play-In Swiss 2026"]
[White "White Player"]
[Black "Black Player"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0
''';

GamesTourModel _virtualGame() {
  return GamesTourModel(
    gameId: 'gamebase-game-1',
    source: GameSource.gamebase,
    whitePlayer: _player('White Player'),
    blackPlayer: _player('Black Player'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: 'virtual-round-1',
    tourId: 'gamebase::Freestyle WCh Play-In Swiss 2026',
    pgn: buildHeaderOnlyPgn(
      whiteName: 'White Player',
      blackName: 'Black Player',
      result: '1-0',
      event: 'Freestyle WCh Play-In Swiss 2026',
    ),
  );
}

PlayerCard _player(String name) {
  return PlayerCard(
    name: name,
    federation: '',
    title: '',
    rating: 2500,
    countryCode: '',
    team: null,
  );
}
