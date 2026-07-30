import 'package:chessever2/utils/pgn_link_rebrand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rebrandPgnLinks', () {
    test('maps broadcast game URLs to /games/<id>', () {
      const pgn =
          '[Event "FIDE Candidates 2026"]\n'
          '[Site "https://lichess.org/broadcast/fide-candidates-2026-open/round-3/SDizieNR/AaJLmuxI"]\n'
          '[GameURL "https://lichess.org/broadcast/x/round-7/efqWGqz4/K4cjG7Tz"]\n\n'
          '1. d4 d5 *';

      final out = rebrandPgnLinks(pgn);

      expect(out.contains('lichess.org'), isFalse);
      expect(
        out,
        contains('[Site "https://chessever.com/games/AaJLmuxI"]'),
      );
      expect(
        out,
        contains('[GameURL "https://chessever.com/games/K4cjG7Tz"]'),
      );
      // Must not leave 4-segment Lichess broadcast paths on chessever.com.
      expect(out, isNot(contains('/round-3/')));
      expect(out, isNot(contains('/round-7/')));
      expect(out, contains('1. d4 d5 *'));
    });

    test('maps broadcast round/event URLs to /broadcast/<slug>/<id>', () {
      const pgn =
          '[BroadcastURL "https://lichess.org/broadcast/superfinal-2025-men/round-4/XRLkQSZo"]\n\n*';

      final out = rebrandPgnLinks(pgn);

      expect(
        out,
        contains(
          '[BroadcastURL "https://chessever.com/broadcast/superfinal-2025-men/XRLkQSZo"]',
        ),
      );
      expect(out, isNot(contains('/round-4/')));
    });

    test('maps direct Lichess game URLs to /games/<id>', () {
      const pgn = '[Site "https://lichess.org/AbCdEf12"]\n\n1. e4 *';
      final out = rebrandPgnLinks(pgn);
      expect(out, contains('[Site "https://chessever.com/games/AbCdEf12"]'));
      expect(out, isNot(contains('lichess.org')));
    });

    test('repairs already host-swapped broken chessever paths', () {
      const broken =
          '[Site "https://chessever.com/broadcast/tour/round-1/AAAA1111/BBBB2222"]\n'
          '[BroadcastURL "https://chessever.com/broadcast/tour/round-1/CCCC3333"]\n'
          '[GameURL "https://chessever.com/DDDD4444"]\n\n*';

      final out = rebrandPgnLinks(broken);

      expect(out, contains('[Site "https://chessever.com/games/BBBB2222"]'));
      expect(
        out,
        contains('[BroadcastURL "https://chessever.com/broadcast/tour/CCCC3333"]'),
      );
      expect(out, contains('[GameURL "https://chessever.com/games/DDDD4444"]'));
    });

    test('also rewrites the lichess.dev staging host', () {
      const pgn = '[Annotator "https://lichess.dev/@/AAArmstark"]\n\n*';
      expect(
        rebrandPgnLinks(pgn),
        contains('[Annotator "https://chessever.com/@/AAArmstark"]'),
      );
    });

    test('is idempotent and leaves correct ChessEver game URLs unchanged', () {
      const pgn =
          '[Event "Local Game"]\n'
          '[Site "https://chessever.com/games/AbCdEf12"]\n'
          '[BroadcastURL "https://chessever.com/broadcast/my-event/QXavbhIZ"]\n\n'
          '1. e4 e5 *';
      expect(rebrandPgnLinks(pgn), pgn);
      expect(rebrandPgnLinks(rebrandPgnLinks(pgn)), rebrandPgnLinks(pgn));
    });

    test('leaves plain non-link Site text alone aside from host swap', () {
      const pgn = '[Event "OTB"]\n[Site "Local Club"]\n\n1. e4 *';
      expect(rebrandPgnLinks(pgn), pgn);
    });
  });
}
