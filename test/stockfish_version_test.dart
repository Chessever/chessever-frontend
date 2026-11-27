import 'package:chessever2/screens/chessboard/provider/stockfish_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stockfishVersionFromUciLine', () {
    test('reads release numbers from the UCI id name reply', () {
      expect(stockfishVersionFromUciLine('id name Stockfish 19'), '19');
      expect(stockfishVersionFromUciLine('id name Stockfish 17.1'), '17.1');
      expect(stockfishVersionFromUciLine('id name Stockfish 18 '), '18');
    });

    test('reads the startup banner', () {
      expect(
        stockfishVersionFromUciLine(
          'Stockfish 18 by the Stockfish developers (see AUTHORS file)',
        ),
        '18',
      );
    });

    test('development builds read as dev', () {
      expect(
        stockfishVersionFromUciLine('id name Stockfish dev-20260905-abcdef12'),
        'dev',
      );
      expect(stockfishVersionFromUciLine('id name Stockfish 280924'), 'dev');
    });

    test('ignores every other line', () {
      expect(
        stockfishVersionFromUciLine('id author the Stockfish developers'),
        isNull,
      );
      expect(stockfishVersionFromUciLine('uciok'), isNull);
      expect(stockfishVersionFromUciLine('id name Fairy-Stockfish 14'), isNull);
      expect(stockfishVersionFromUciLine('info depth 20 score cp 31'), isNull);
    });
  });

  group('stockfishShortLabel', () {
    test('names the engine the way Lichess does', () {
      expect(stockfishShortLabel('19'), 'SF 19');
      expect(stockfishShortLabel('17.1'), 'SF 17.1');
      expect(stockfishShortLabel('dev'), 'SF dev');
    });

    test('falls back to the bundled version', () {
      expect(stockfishShortLabel(), 'SF $kBundledStockfishVersion');
      expect(stockfishShortLabel('  '), 'SF $kBundledStockfishVersion');
    });
  });
}
