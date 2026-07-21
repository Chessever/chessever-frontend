import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_move_line.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Najdorf-shaped line with O-O-O (same structure as the Liu–Acs repro):
/// ply 20 = before White's 11th (still FEN-indexed), ply 21 = after 11.Be3
/// (needs full line).
const _pgn =
    '1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 '
    '6. Bg5 e6 7. Qd2 Be7 8. O-O-O O-O 9. f3 Nc6 10. Nxc6 bxc6 '
    '11. Be3 d5 12. Kb1';

class _Cap extends GamebaseRepository {
  _Cap() : super(Dio(), apiKey: 'test');
  final calls = <List<String>>[];

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
    calls.add(List<String>.of(moves));
    final pos = Position.setupPosition(Rule.chess, Setup.parseFen(fen));
    final legal = <MoveAggregate>[];
    for (final e in pos.legalMoves.entries) {
      for (final to in e.value.squares) {
        final m = NormalMove(from: e.key, to: to);
        if (pos.isLegal(m)) {
          legal.add(
            MoveAggregate(uci: m.uci, white: 10, black: 5, draws: 5, total: 20),
          );
          if (legal.length >= 3) break;
        }
      }
      if (legal.length >= 3) break;
    }
    return GamebaseResponse(
      status: 'success',
      data: GamebaseData(moves: legal),
    );
  }

  @override
  Future<GamebaseSearchQueryResponse> getFenPositionGames({
    required String fen,
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    return const GamebaseSearchQueryResponse(
      status: 'success',
      data: [],
      metadata: GamebasePaginationMetadata(pageNumber: 0, pageSize: 1),
    );
  }
}

void main() {
  final game = ChessGame.fromPgn('t', _pgn);

  test('resolveExplorerMoveLine keeps castling path at ply 20 and 21', () {
    for (final ply in <int>[20, 21]) {
      final expected =
          game.mainline.take(ply).map((m) => m.uci).toList(growable: false);
      final state = AnalysisBoardState(
        position: Position.setupPosition(
          Rule.chess,
          Setup.parseFen(game.mainline[ply - 1].fen),
        ),
        startingPosition: Chess.initial,
        allMoves: expected.map(NormalMove.fromUci).toList(),
        game: game,
        movePointer: [ply - 1],
        currentMoveIndex: ply - 1,
      );
      final line = resolveExplorerMoveLine(state);
      expect(line, hasLength(ply), reason: 'ply $ply');
      expect(
        line.any((u) => u == 'e1a1' || u == 'e1c1'),
        isTrue,
        reason: 'must include queenside castling in the line',
      );
    }
  });

  test(
    'provider sends full line at ply 20 and still at ply 21 (Liu–Acs boundary)',
    () async {
      final cap = _Cap();
      final container = ProviderContainer(
        overrides: [gamebaseRepositoryProvider.overrideWithValue(cap)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        gamebaseExplorerProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      final notifier = container.read(gamebaseExplorerProvider.notifier);

      final line20 =
          game.mainline.take(20).map((m) => m.uci).toList(growable: false);
      final line21 =
          game.mainline.take(21).map((m) => m.uci).toList(growable: false);

      notifier.setPositionWithMoves(
        game.mainline[19].fen,
        line20,
        startingFen: Chess.initial.fen,
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(cap.calls.last, line20);
      expect(container.read(gamebaseExplorerProvider).moveAggregates, isNotEmpty);

      // One ply later — past MV_MAX_PLY. This is where mobile showed
      // "No move statistics" while desktop kept working.
      notifier.setPositionWithMoves(
        game.mainline[20].fen,
        line21,
        startingFen: Chess.initial.fen,
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(
        cap.calls.last,
        line21,
        reason: 'ply 21 fetch must send 21 UCIs including castling',
      );
      expect(
        container.read(gamebaseExplorerProvider).moveAggregates,
        isNotEmpty,
        reason: 'ply 21 must not settle empty ("no move statistics")',
      );
    },
  );
}
