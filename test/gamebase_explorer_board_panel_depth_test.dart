// Depth coverage for the swipe-to-explorer panel used by
// chess_board_screen_new.dart, at positions past the backend's fast indexed
// window (20 played plies) where the explorer used to misbehave.
//
// The real GamebaseRepository against the live server, driven through the
// same provider the swipe panel drives. Proves the server answers at these
// depths and the response survives the whole client pipeline.
//
// The widget-layer counterpart (the panel shipping the full line at these
// depths) lives in gamebase_explorer_view_fen_test.dart. The two are kept
// apart on purpose: a widget test runs under FakeAsync, so a real HTTP
// request started there can never have its completion delivered.
//
// Skipped unless a key is supplied:
//   flutter test --dart-define=GB_KEY=<key> <this file>
//
// This does not replace on-device verification of the swipe gesture itself.
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _gbKey = String.fromEnvironment('GB_KEY');

/// Depths past the ply-20 boundary, i.e. move 12 through move 40.
const _deepPlies = <int>[24, 40, 60, 80];

/// A real broadcast game, 91 plies, including queenside castling (a move the
/// backend and dartchess spell differently, so the line has to survive that).
const _pgn =
    '1. e4 c5 2. Nf3 e6 3. d4 cxd4 4. Nxd4 Nc6 5. Nc3 Qc7 6. Be3 a6 '
    '7. Qf3 Nf6 8. O-O-O h5 9. Nxc6 dxc6 10. h3 b5 11. e5 Nd5 12. Bf4 Bb7 '
    '13. Nxd5 cxd5 14. Bd3 Rc8 15. Kb1 Be7 16. Rhg1 g6 17. Rc1 Qc6 18. g4 h4 '
    '19. Rge1 Qc7 20. Bd2 Bc6 21. Qe2 Qb7 22. f4 d4 23. f5 gxf5 24. gxf5 Bd5 '
    '25. Qg4 Qb6 26. Be4 Qc6 27. fxe6 fxe6 28. Bg6+ Kd7 29. Qxd4 Qc4 '
    '30. Qxc4 Rxc4 31. Bd3 Rcc8 32. Rg1 Rhg8 33. Be2 Bc5 34. Rxg8 Rd8 '
    '35. Rf8 Rxf8 36. Bg4 Rg8 37. Re1 Bf2 38. Rf1 Bg3 39. Rf7+ Ke8 40. Bh5 Kd8 '
    '41. Bb4 Bxe5 42. Rf8+ Rxf8 43. Bxf8 Bg3 44. b3 e5 45. Bc5 Be6 46. Bd1 0-1';

void main() {
  final game = ChessGame.fromPgn('deep', _pgn);

  group(
    'live server answers at depth through the explorer pipeline',
    skip: _gbKey.isEmpty ? 'no GB_KEY provided' : null,
    () {
      for (final ply in _deepPlies) {
        test('ply $ply returns moves', () async {
          final container = ProviderContainer(
            overrides: [
              gamebaseRepositoryProvider.overrideWithValue(
                GamebaseRepository(
                  Dio(
                    BaseOptions(
                      connectTimeout: const Duration(seconds: 15),
                      receiveTimeout: const Duration(seconds: 30),
                    ),
                  ),
                  apiKey: _gbKey,
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          final sub = container.listen(
            gamebaseExplorerProvider,
            (_, __) {},
            fireImmediately: true,
          );
          addTearDown(sub.close);

          final line =
              game.mainline.take(ply).map((m) => m.uci).toList(growable: false);
          container
              .read(gamebaseExplorerProvider.notifier)
              .setPositionWithMoves(
                game.mainline[ply - 1].fen,
                line,
                startingFen: Chess.initial.fen,
              );

          for (var i = 0; i < 60; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            if (i > 2 && !container.read(gamebaseExplorerProvider).isLoading) {
              break;
            }
          }

          final explorer = container.read(gamebaseExplorerProvider);
          expect(explorer.exploredMoves, line);
          expect(explorer.error, isNull);
          expect(
            explorer.moveAggregates,
            isNotEmpty,
            reason: 'live server returned no moves at ply $ply',
          );
        });
      }
    },
  );
}
