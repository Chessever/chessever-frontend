import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/twic_player_enrichment.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerCard _card(String title, int fideId) => PlayerCard(
  name: 'Player $fideId',
  federation: 'NOR',
  title: title,
  rating: 2400,
  countryCode: 'NOR',
  team: null,
  fideId: fideId,
);

GamesTourModel _game(String white, String black, GameSource source) =>
    GamesTourModel(
      gameId: 'g',
      whitePlayer: _card(white, 1),
      blackPlayer: _card(black, 2),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.fromString('1-0'),
      roundId: 'r',
      tourId: 't',
      source: source,
    );

// chess_players holds today's titles: both players are GMs now.
const _today = {
  1: ChessPlayer(fideid: 1, name: 'Player 1', title: 'GM'),
  2: ChessPlayer(fideid: 2, name: 'Player 2', title: 'GM'),
};

void main() {
  group('list rows', () {
    test('a settled row keeps an empty side empty: untitled then', () {
      final row = <String, dynamic>{'whiteTitle': null, 'blackTitle': 'IM'};
      expect(
        ChessTitleUtils.listRowTitle(row, isWhite: true, fallback: 'GM'),
        '',
      );
      expect(
        ChessTitleUtils.listRowTitle(row, isWhite: false, fallback: 'GM'),
        'IM',
      );
    });

    test("a row with no titles at all takes today's title", () {
      final row = <String, dynamic>{'whiteTitle': null, 'blackTitle': '-'};
      expect(
        ChessTitleUtils.listRowTitle(row, isWhite: true, fallback: 'gm'),
        'GM',
      );
    });
  });

  group('chess_players enrichment', () {
    test('does not fill a settled archive game with today\'s title', () {
      final enriched = enrichGameWithChessPlayers(
        _game('', 'IM', GameSource.gamebase),
        _today,
      );
      expect(enriched.whitePlayer.title, '');
      expect(enriched.blackPlayer.title, 'IM');
    });

    test('still fills an archive game that carries no titles', () {
      final enriched = enrichGameWithChessPlayers(
        _game('', '', GameSource.twic),
        _today,
      );
      expect(enriched.whitePlayer.title, 'GM');
      expect(enriched.blackPlayer.title, 'GM');
    });

    test('still fills a live broadcast card', () {
      final enriched = enrichGameWithChessPlayers(
        _game('', 'IM', GameSource.supabase),
        _today,
      );
      expect(enriched.whitePlayer.title, 'GM');
    });

    test('a settled search row keeps its titles', () {
      final row = enrichSearchRowWithChessPlayers({
        'whiteFideId': 1,
        'blackFideId': 2,
        'whiteTitle': '',
        'blackTitle': 'FM',
      }, _today);
      expect(row['whiteTitle'], '');
      expect(row['blackTitle'], 'FM');
    });
  });
}
