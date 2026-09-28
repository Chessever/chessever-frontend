import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _pgn = '''[Event "St Louis Summer A"]
[Site "Saint Louis"]
[Date "2026.09.26"]
[Round "4.1"]
[Board "3"]
[White "Jumabayev, Rinat"]
[Black "Durarbayli, Vasif"]
[WhiteTitle "GM"]
[BlackTitle "GM"]
[WhiteElo "2621"]
[BlackElo "2618"]
[WhiteFederation "KAZ"]
[BlackFed "AZE"]
[WhiteFideId "13702619"]
[BlackFideId "13400795"]
[WhiteTeam "Club A"]
[BlackTeam "Club B"]
[TimeControl "40/5400+30:1800+30"]
[ECO "C60"]
[Opening "Ruy Lopez"]
[Result "0-1"]

1. e4 {[%clk 1:29:30] A mainline comment.} e5 {[%clk 1:29:00]}
2. Nf3 \$1 Nc6 (2... d6) 3. Bb5 {[%clk 1:28:20]} 0-1''';

void main() {
  test('collection PGN hydrates tournament card data and recorded clocks', () {
    final game = collectionGameModel('book-game', _pgn);
    expect(game.whitePlayer.name, 'Jumabayev, Rinat');
    expect(game.blackPlayer.name, 'Durarbayli, Vasif');
    expect(game.whitePlayer.title, 'GM');
    expect(game.blackPlayer.rating, 2618);
    expect(game.whitePlayer.countryCode, 'KAZ');
    expect(game.blackPlayer.countryCode, 'AZE');
    expect(game.whitePlayer.fideId, 13702619);
    expect(game.blackPlayer.fideId, 13400795);
    expect(game.whitePlayer.team, 'Club A');
    expect(game.blackPlayer.team, 'Club B');
    expect(game.boardNr, 3);
    expect(game.roundId, '4.1');
    expect(game.timeControl, 'standard');
    expect(game.timeControlText, '40/5400+30:1800+30');
    expect(game.whiteClockSeconds, 5300);
    expect(game.blackClockSeconds, 5340);
    expect(game.whiteTimeDisplay, '1:28:20');
    expect(game.gameDay, DateTime(2026, 9, 26));
    expect(game.eco, 'C60');
    expect(game.openingName, 'Ruy Lopez');
    expect(game.lastMove, 'f1b5');
    expect(game.gameStatus, GameStatus.blackWins);
    expect(game.pgn, _pgn, reason: 'Keep all comments, NAGs and variations.');
  });

  test(
    'an unfinished stored PGN never invents a result from absent clocks',
    () {
      final game = collectionGameModel(
        'unfinished',
        '[White "A"]\n[Black "B"]\n[Result "*"]\n\n1. e4 e5 *',
      );
      expect(game.gameStatus, GameStatus.ongoing);
      expect(game.effectiveGameStatus, GameStatus.ongoing);
      expect(game.whiteClockSeconds, isNull);
      expect(game.blackClockSeconds, isNull);
    },
  );

  test('a club name never becomes a federation flag', () {
    final game = collectionGameModel(
      'team',
      '[White "A"]\n[Black "B"]\n[WhiteTeam "Local Chess Club"]\n\n*',
    );
    expect(game.whitePlayer.countryCode, isEmpty);
    expect(game.whitePlayer.team, 'Local Chess Club');
  });

  test('a supplied starting position survives without any moves', () {
    const fen = '8/8/8/8/8/8/4K3/7k b - - 0 1';
    final game = collectionGameModel(
      'position',
      '[SetUp "1"]\n[FEN "$fen"]\n[Date "2026.02.31"]\n\n*',
    );
    expect(game.fen, fen);
    expect(game.lastMove, isNull);
    expect(game.lastMoveTime, isNull);
  });

  test('clock samples belong to their mover when a PGN starts with Black', () {
    final game = collectionGameModel('black-start', '''[SetUp "1"]
[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1"]
[Result "*"]

1... e5 {[%clk 0:10:00]} 2. Nf3 {[%clk 0:09:58]} *''');
    expect(game.blackClockSeconds, 600);
    expect(game.whiteClockSeconds, 598);
    expect(game.lastMove, 'g1f3');
    expect(game.effectiveGameStatus, GameStatus.ongoing);
  });

  test(
    'time-control filters use PGN seconds and respect category overrides',
    () {
      GamesTourModel from(String tc, {String category = '?'}) =>
          collectionGameModel(
            tc,
            '[TimeControl "$tc"]\n[TcCategory "$category"]\n\n*',
          );
      expect(from('180+2').timeControl, 'blitz');
      expect(from('60+30').timeControl, 'rapid');
      expect(from('900+10').timeControl, 'rapid');
      expect(from('3600').timeControl, 'standard');
      expect(from('5400+30', category: 'rapid').timeControl, 'rapid');
      expect(from('900+10', category: 'unrecognized').timeControl, 'rapid');
      expect(from('?').timeControl, isNull);
    },
  );

  test('unknown tags remain absent instead of appearing as card metadata', () {
    final game = collectionGameModel('unknown', '''[White "?"]
[WhiteTitle "-"]
[WhiteElo "?"]
[WhiteFed "?"]
[WhiteCountry "USA"]
[Board "?"]
[BoardNumber "7"]
[Date "2026.??.??"]

*''');
    expect(game.whitePlayer.name, 'White');
    expect(game.whitePlayer.title, isEmpty);
    expect(game.whitePlayer.rating, 0);
    expect(game.whitePlayer.countryCode, 'USA');
    expect(game.boardNr, 7);
    expect(game.gameDay, isNull);
  });
}
