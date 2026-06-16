import 'package:chessever2/utils/pgn_link_rebrand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rebrandPgnLinks', () {
    test('swaps lichess host in Site/GameURL/BroadcastURL, preserves paths', () {
      const pgn = '[Event "FIDE Candidates 2026"]\n'
          '[Site "https://lichess.org/broadcast/fide-candidates-2026-open/round-3/SDizieNR/AaJLmuxI"]\n'
          '[BroadcastURL "https://lichess.org/broadcast/superfinal-2025-men/round-4/XRLkQSZo"]\n'
          '[GameURL "https://lichess.org/broadcast/x/round-7/efqWGqz4/K4cjG7Tz"]\n\n'
          '1. d4 d5 *';

      final out = rebrandPgnLinks(pgn);

      expect(out.contains('lichess.org'), isFalse);
      expect(
        out,
        contains(
          '[Site "https://chessever.com/broadcast/fide-candidates-2026-open/round-3/SDizieNR/AaJLmuxI"]',
        ),
      );
      expect(out, contains('https://chessever.com/broadcast/superfinal-2025-men/round-4/XRLkQSZo'));
      // Paths and move text untouched.
      expect(out, contains('round-7/efqWGqz4/K4cjG7Tz'));
      expect(out, contains('1. d4 d5 *'));
    });

    test('also rewrites the lichess.dev staging host and @/user links', () {
      const pgn = '[Annotator "https://lichess.dev/@/AAArmstark"]\n\n*';
      expect(
        rebrandPgnLinks(pgn),
        contains('[Annotator "https://chessever.com/@/AAArmstark"]'),
      );
    });

    test('is idempotent and leaves lichess-free PGN unchanged', () {
      const pgn = '[Event "Local Game"]\n[Site "chessever.com"]\n\n1. e4 e5 *';
      expect(rebrandPgnLinks(pgn), pgn);
      expect(rebrandPgnLinks(rebrandPgnLinks(pgn)), rebrandPgnLinks(pgn));
    });
  });
}
