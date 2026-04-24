import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dio adapter that captures outbound requests and returns a scripted success.
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  Map<String, dynamic>? lastBody;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (options.data is Map<String, dynamic>) {
      lastBody = Map<String, dynamic>.from(options.data as Map);
    }
    return ResponseBody.fromString(
      '{"status":"success","data":{"moves":[]}}',
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }
}

void main() {
  group('getMoveAggregates castling UCI normalization', () {
    test(
      'rewrites dartchess king-to-rook castling to standard king-to-g/c form',
      () async {
        final adapter = _CapturingAdapter();
        final dio = Dio()..httpClientAdapter = adapter;
        final repo = GamebaseRepository(
          dio,
          baseUrl: 'http://test',
          apiKey: 'test',
        );

        // Ruy Lopez Breyer main line, 22 plies.
        // Both castling moves use dartchess king-to-rook UCI: e1h1 and e8h8.
        const fen =
            'r2q1rk1/1bpnbppp/p2p1n2/1p2p3/3PP3/1BP2N1P/PP1N1PP1/R1BQR1K1 w - - 3 12';
        final chess960CastlingMoves = <String>[
          'e2e4',
          'e7e5',
          'g1f3',
          'b8c6',
          'f1b5',
          'a7a6',
          'b5a4',
          'g8f6',
          'e1h1',
          'f8e7',
          'f1e1',
          'b7b5',
          'a4b3',
          'd7d6',
          'c2c3',
          'e8h8',
          'h2h3',
          'c6b8',
          'd2d4',
          'b8d7',
          'b1d2',
          'c8b7',
        ];

        await repo.getMoveAggregates(fen: fen, moves: chess960CastlingMoves);

        expect(adapter.lastBody, isNotNull);
        final sentMoves = (adapter.lastBody!['moves'] as List).cast<String>();

        expect(sentMoves.length, 22);
        // Castling UCIs must be rewritten to the king-target form for chess.js.
        expect(
          sentMoves[8],
          'e1g1',
          reason: 'white O-O must be sent as e1g1, not e1h1',
        );
        expect(
          sentMoves[15],
          'e8g8',
          reason: 'black O-O must be sent as e8g8, not e8h8',
        );
        // Non-castling moves should be untouched.
        expect(sentMoves[0], 'e2e4');
        expect(sentMoves[21], 'c8b7');
      },
    );

    test('leaves non-castling lines unchanged', () async {
      final adapter = _CapturingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final repo = GamebaseRepository(
        dio,
        baseUrl: 'http://test',
        apiKey: 'test',
      );

      const fen =
          'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';
      final moves = <String>['e2e4', 'c7c5', 'g1f3'];

      await repo.getMoveAggregates(fen: fen, moves: moves);

      final sentMoves = (adapter.lastBody!['moves'] as List).cast<String>();
      expect(sentMoves, moves);
    });

    test('returns empty moves if line does not replay to fen', () async {
      final adapter = _CapturingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final repo = GamebaseRepository(
        dio,
        baseUrl: 'http://test',
        apiKey: 'test',
      );

      const fen =
          'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';
      // Intentionally wrong line for the fen.
      final bogusMoves = <String>['d2d4', 'd7d5', 'c2c4'];

      await repo.getMoveAggregates(fen: fen, moves: bogusMoves);

      final sentMoves = (adapter.lastBody!['moves'] as List).cast<String>();
      expect(sentMoves, isEmpty);
    });

    test('keeps a full 62-ply deep line in aggregate requests', () async {
      final adapter = _CapturingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final repo = GamebaseRepository(
        dio,
        baseUrl: 'http://test',
        apiKey: 'test',
      );

      final moves = <String>[];
      Position position = Chess.initial;

      void play(String uci) {
        final move = NormalMove.fromUci(uci);
        expect(position.isLegal(move), isTrue, reason: '$uci must be legal');
        moves.add(uci);
        position = position.play(move);
      }

      // 15 full knight-shuffle cycles = 60 plies, then two more plies.
      // This intentionally crosses the old shallow boundary and the new
      // 30-full-move indexed boundary without relying on a specific database
      // game being present.
      for (var i = 0; i < 15; i++) {
        play('g1f3');
        play('g8f6');
        play('f3g1');
        play('f6g8');
      }
      play('g1f3');
      play('g8f6');

      await repo.getMoveAggregates(fen: position.fen, moves: moves);

      expect(
        adapter.lastRequest?.path,
        endsWith('/api/game-position/aggregates/query'),
      );
      final sentMoves = (adapter.lastBody!['moves'] as List).cast<String>();
      expect(sentMoves.length, 62);
      expect(sentMoves, moves);
    });
  });
}
