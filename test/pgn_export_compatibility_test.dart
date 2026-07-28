import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/utils/pgn_export_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonicalizePgnForExport', () {
    test(
      'writes Lichess-style identity headers first without changing movetext',
      () {
        const raw = '''[Black "So, Wesley"]
[BlackElo "2719"]
[Event "USA - Uzbekistan WR Chess Match"]
[Result "0-1"]
[Round "1.3"]
[Site "Miami, United States"]
[White "Madaminov, Mukhiddin"]
[WhiteElo "2501"]
[BroadcastURL "https://chessever.com/broadcast/example"]
[allowMainlineExtension "true"]
[isLiveGame "false"]

1. e4 {[%clk 0:15:16]} e5 {[%eval 0.20]} 2. Nf3 Nc6 0-1''';

        final exported = canonicalizePgnForExport(raw);

        expect(exported.split('\n').take(9).toList(), [
          '[Event "USA - Uzbekistan WR Chess Match"]',
          '[Site "Miami, United States"]',
          '[Date "????.??.??"]',
          '[Round "1.3"]',
          '[White "Madaminov, Mukhiddin"]',
          '[Black "So, Wesley"]',
          '[Result "0-1"]',
          '[WhiteElo "2501"]',
          '[BlackElo "2719"]',
        ]);
        expect(
          exported,
          contains('[BroadcastURL "https://chessever.com/broadcast/example"]'),
        );
        expect(exported, isNot(contains('allowMainlineExtension')));
        expect(exported, isNot(contains('isLiveGame')));
        expect(
          exported,
          endsWith('1. e4 {[%clk 0:15:16]} e5 {[%eval 0.20]} 2. Nf3 Nc6 0-1'),
        );
        expect(exported, contains('\n\n1. e4'));
      },
    );
  });

  group('notation PGN export', () {
    test('adds standard defaults and removes internal ChessEver metadata', () {
      final game = ChessGame.fromPgn('manual-analysis', '''[Result "*"]
[allowMainlineExtension "true"]
[isLiveGame "false"]
[gameEndingPlyIndex "2"]

1. e4 {[%clk 0:15:00]} e5 {[%eval 0.18]} *''');

      final exported = exportGameToPgn(game);

      expect(exported.split('\n').take(7).toList(), [
        '[Event "?"]',
        '[Site "?"]',
        '[Date "????.??.??"]',
        '[Round "?"]',
        '[White "?"]',
        '[Black "?"]',
        '[Result "*"]',
      ]);
      expect(exported, isNot(contains('allowMainlineExtension')));
      expect(exported, isNot(contains('isLiveGame')));
      expect(exported, isNot(contains('gameEndingPlyIndex')));
      expect(exported, contains('[%clk 0:15:00]'));
      expect(exported, contains('[%eval 0.18]'));
    });
  });

  group('Gamebase PGN export', () {
    test('writes the Seven Tag Roster before Gamebase metadata', () {
      final pgn = buildPgnFromGamebaseData({
        'md': {
          'Black': 'So, Wesley',
          'BlackElo': '2719',
          'Event': 'USA - Uzbekistan WR Chess Match',
          'Result': '0-1',
          'White': 'Madaminov, Mukhiddin',
          'WhiteElo': '2501',
        },
        'm': [
          {'u': 'e2e4', 'ct': '0:15:16'},
          {'u': 'e7e5', 'ct': '0:15:16'},
        ],
      });

      expect(pgn, isNotNull);
      expect(pgn!.split('\n').take(9).toList(), [
        '[Event "USA - Uzbekistan WR Chess Match"]',
        '[Site "?"]',
        '[Date "????.??.??"]',
        '[Round "?"]',
        '[White "Madaminov, Mukhiddin"]',
        '[Black "So, Wesley"]',
        '[Result "0-1"]',
        '[WhiteElo "2501"]',
        '[BlackElo "2719"]',
      ]);
      expect(pgn, contains('1. e4 {[%clk 0:15:16]} e5'));
    });
  });
}
