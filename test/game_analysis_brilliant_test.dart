import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// Curated !! fixtures. Prefer high precision: ordinary gambits must not pass.
void main() {
  group('high-precision Brilliant (!!)', () {
    test(
      'genuine multi-ply piece sacrifice with PV edge receives brilliant',
      () {
        // Intent: TRUE brilliancy — queen offer accepted next move, then
        // continued check (not mate). Modest live evals so "decided" exclusion
        // does not fire. Multi-ply persistence via check after the reply.
        final game = ChessGame.fromPgn(
          'true-brilliant',
          '[FEN "4k3/8/8/8/1p6/8/3Q1R2/4K3 w - - 0 1"]\n\n'
          '1. Qc3 *',
        );
        final beforeFen = game.startingFen;
        final afterFen = game.mainline.first.fen;
        // Sanity: not mate after the queen move.
        expect(afterFen.contains(' k '), isFalse);
        final positions = [
          GameReportPosition(
            fen: beforeFen,
            lines: [
              // Played queen offer is PV1 with a live (not crushing) score.
              const GameReportLine(
                moves: ['d2c3', 'b4c3', 'f2f8', 'e8d7'],
                depth: 16,
                centipawns: 90,
              ),
              // Quiet alternative is clearly worse (gap for !! prestige).
              const GameReportLine(
                moves: ['d2d3'],
                depth: 16,
                centipawns: -40,
              ),
            ],
          ),
          GameReportPosition(
            fen: afterFen,
            // After Qc3: black takes, white checks with rook — multi-ply idea.
            lines: [
              const GameReportLine(
                moves: ['b4c3', 'f2f8', 'e8d7', 'f8f7'],
                depth: 16,
                centipawns: 80,
              ),
            ],
          ),
        ];
        final beforeWin = gameReportWinPercentage(positions[0].bestLine);
        final afterWin = gameReportWinPercentage(positions[1].bestLine);
        expect(beforeWin, lessThan(92), reason: 'live position, not decided');
        expect(afterWin, lessThan(95), reason: 'not a forced mate eval');

        final classification = classifyGameReportMove(
          index: 0,
          game: game,
          positions: positions,
          winPercentages: [beforeWin, afterWin],
        );
        expect(
          classification,
          GameMoveClassification.brilliant,
          reason: 'multi-ply piece sac with PV edge + continued check → !!',
        );
      },
    );

    test('quiet piece development is not material investment', () {
      // Intent: investment gate must reject ordinary Nc3-style moves.
      expect(
        isMeaningfulBrilliantInvestment(
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e3 0 1',
          'b1c3',
          const ['b8c6', 'g1f3', 'g8f6'],
        ),
        isFalse,
        reason: 'safe knight development is not a sacrifice',
      );
    });

    test(
      'protected piece on attacked square is not brilliant (fail-closed)',
      () {
        // Intent: Nc3 onto a square hit by ...b4, but protected by d2 — routine
        // under-attack development, not a !! investment even with MultiPV edge.
        final game = ChessGame.fromPgn(
          'protected-attacked',
          '[FEN "4k3/8/8/8/1p6/8/3P4/1N2K3 w - - 0 1"]\n\n'
          '1. Nc3 *',
        );
        expect(
          isMeaningfulBrilliantInvestment(
            game.startingFen,
            'b1c3',
            const ['b4c3', 'd2c3', 'e8d7'],
          ),
          isFalse,
          reason: 'pawn-takes-N, we recapture with pawn → not net-hanging sac',
        );
        final positions = [
          GameReportPosition(
            fen: game.startingFen,
            lines: [
              const GameReportLine(
                moves: ['b1c3', 'b4c3', 'd2c3'],
                depth: 16,
                centipawns: 100,
              ),
              const GameReportLine(
                moves: ['b1a3'],
                depth: 16,
                centipawns: -20,
              ),
            ],
          ),
          GameReportPosition(
            fen: game.mainline.first.fen,
            lines: [
              const GameReportLine(
                moves: ['b4c3', 'd2c3', 'e8d7'],
                depth: 16,
                centipawns: 90,
              ),
            ],
          ),
        ];
        final beforeWin = gameReportWinPercentage(positions[0].bestLine);
        final afterWin = gameReportWinPercentage(positions[1].bestLine);
        expect(
          classifyGameReportMove(
            index: 0,
            game: game,
            positions: positions,
            winPercentages: [beforeWin, afterWin],
          ),
          isNot(GameMoveClassification.brilliant),
          reason: 'protected piece to attacked square must not get !!',
        );
      },
    );

    test(
      'ordinary accepted pawn offer (false positive) is not brilliant',
      () {
        // Intent: FALSE POSITIVE for old rule — near-best pawn sac.
        final game = ChessGame.fromPgn(
          'pawn-offer',
          '[FEN "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"]\n\n'
          '2. f4 *',
        );
        final positions = [
          GameReportPosition(
            fen: game.startingFen,
            lines: [
              const GameReportLine(
                moves: ['f2f4', 'e5f4'],
                depth: 12,
                centipawns: 15,
              ),
              const GameReportLine(
                moves: ['g1f3'],
                depth: 12,
                centipawns: 20,
              ),
            ],
          ),
          GameReportPosition(
            fen: game.mainline.first.fen,
            lines: [
              const GameReportLine(
                moves: ['e5f4'],
                depth: 12,
                centipawns: 10,
              ),
            ],
          ),
        ];
        final beforeWin = gameReportWinPercentage(positions[0].bestLine);
        final afterWin = gameReportWinPercentage(positions[1].bestLine);
        final classification = classifyGameReportMove(
          index: 0,
          game: game,
          positions: positions,
          winPercentages: [beforeWin, afterWin],
        );
        expect(
          classification,
          isNot(GameMoveClassification.brilliant),
          reason: 'ordinary pawn gambit must not receive !!',
        );
        expect(
          isReportLikelyOpeningBookForBrilliant(0, game),
          isTrue,
          reason: 'early pawn gambit treated as opening/book for !!',
        );
      },
    );

    test(
      'immediate-reply sacrifice alone without multi-ply PV is not brilliant',
      () {
        // Intent: old isReportPieceSacrifice true, short PV → no !!.
        final game = ChessGame.fromPgn(
          'one-reply-sac',
          '[FEN "4k3/8/8/8/1p6/8/3Q4/4K3 w - - 0 1"]\n\n'
          '1. Qc3 *',
        );
        expect(
          isReportPieceSacrifice(
            game.startingFen,
            'd2c3',
            const ['b4c3'],
          ),
          isTrue,
          reason: 'fixture still triggers the low-level sacrifice helper',
        );
        final positions = [
          GameReportPosition(
            fen: game.startingFen,
            lines: [
              const GameReportLine(
                moves: ['d2c3', 'b4c3'],
                depth: 12,
                centipawns: 5,
              ),
              const GameReportLine(
                moves: ['d2d3'],
                depth: 12,
                centipawns: 0,
              ),
            ],
          ),
          GameReportPosition(
            fen: game.mainline.first.fen,
            lines: [
              // Only one reply ply — fails multi-ply persistence.
              const GameReportLine(moves: ['b4c3'], depth: 12, centipawns: -5),
            ],
          ),
        ];
        final beforeWin = gameReportWinPercentage(positions[0].bestLine);
        final afterWin = gameReportWinPercentage(positions[1].bestLine);
        final classification = classifyGameReportMove(
          index: 0,
          game: game,
          positions: positions,
          winPercentages: [beforeWin, afterWin],
        );
        expect(
          classification,
          isNot(GameMoveClassification.brilliant),
          reason: 'one-reply sac without multi-ply persistence → not !!',
        );
      },
    );

    test(
      'checking best-move with long PV but no investment is not brilliant',
      () {
        // Intent: persistence must not fire on the check from the move alone
        // (routine checks with a 3+ ply PV and no material sac).
        final game = ChessGame.fromPgn(
          'check-only',
          '[FEN "4k3/8/8/8/8/8/3Q4/4K3 w - - 0 1"]\n\n'
          '1. Qe2+ *',
        );
        final positions = [
          GameReportPosition(
            fen: game.startingFen,
            lines: [
              const GameReportLine(
                moves: ['d2e2', 'e8d8', 'e2d2', 'd8e8'],
                depth: 16,
                centipawns: 100,
              ),
              const GameReportLine(
                moves: ['d2d3'],
                depth: 16,
                centipawns: 20,
              ),
            ],
          ),
          GameReportPosition(
            fen: game.mainline.first.fen,
            lines: [
              const GameReportLine(
                moves: ['e8d8', 'e2d2', 'd8e8', 'd2e2'],
                depth: 16,
                centipawns: 100,
              ),
            ],
          ),
        ];
        final beforeWin = gameReportWinPercentage(positions[0].bestLine);
        final afterWin = gameReportWinPercentage(positions[1].bestLine);
        expect(
          isMeaningfulBrilliantInvestment(
            game.startingFen,
            'd2e2',
            positions[1].bestLine.moves,
          ),
          isFalse,
        );
        expect(
          classifyGameReportMove(
            index: 0,
            game: game,
            positions: positions,
            winPercentages: [beforeWin, afterWin],
          ),
          isNot(GameMoveClassification.brilliant),
        );
      },
    );

    test('forced recapture is never brilliant', () {
      final game = ChessGame.fromPgn(
        'recapture',
        '[FEN "4k3/8/2p5/3p4/4P3/8/8/4K3 w - - 0 1"]\n\n'
        '1. exd5 cxd5 *',
      );
      final positions = [
        GameReportPosition(
          fen: game.startingFen,
          lines: [
            const GameReportLine(moves: ['e4d5'], depth: 12, centipawns: 0),
          ],
        ),
        GameReportPosition(
          fen: game.mainline[0].fen,
          lines: [
            const GameReportLine(moves: ['c6d5'], depth: 12, centipawns: 0),
            const GameReportLine(moves: ['e8d7'], depth: 12, centipawns: -40),
          ],
        ),
        GameReportPosition(
          fen: game.mainline[1].fen,
          lines: [
            const GameReportLine(moves: ['e1d2'], depth: 12, centipawns: 0),
          ],
        ),
      ];
      final wp = [
        gameReportWinPercentage(positions[0].bestLine),
        gameReportWinPercentage(positions[1].bestLine),
        gameReportWinPercentage(positions[2].bestLine),
      ];
      expect(
        classifyGameReportMove(
          index: 1,
          game: game,
          positions: positions,
          winPercentages: wp,
        ),
        isNot(GameMoveClassification.brilliant),
      );
      expect(
        isSimpleReportRecapture(game.startingFen, 'e4d5', 'c6d5'),
        isTrue,
      );
    });

    test(
      'isBrilliantCandidate is true for deep-sac fixture, false for gambit',
      () {
        final brilliantGame = ChessGame.fromPgn(
          'cand-true',
          '[FEN "4k3/8/8/8/1p6/8/3Q1R2/4K3 w - - 0 1"]\n\n'
          '1. Qc3 *',
        );
        final brilliantPositions = [
          GameReportPosition(
            fen: brilliantGame.startingFen,
            lines: [
              const GameReportLine(
                moves: ['d2c3', 'b4c3', 'f2f8'],
                depth: 16,
                centipawns: 90,
              ),
              const GameReportLine(moves: ['d2d3'], depth: 16, centipawns: -40),
            ],
          ),
          GameReportPosition(
            fen: brilliantGame.mainline.first.fen,
            lines: [
              const GameReportLine(
                moves: ['b4c3', 'f2f8', 'e8d7'],
                depth: 16,
                centipawns: 80,
              ),
            ],
          ),
        ];
        final bWin = [
          gameReportWinPercentage(brilliantPositions[0].bestLine),
          gameReportWinPercentage(brilliantPositions[1].bestLine),
        ];
        expect(
          isBrilliantCandidate(
            index: 0,
            game: brilliantGame,
            positions: brilliantPositions,
            winPercentages: bWin,
          ),
          isTrue,
        );

        final gambit = ChessGame.fromPgn(
          'cand-false',
          '[FEN "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"]\n\n'
          '2. f4 *',
        );
        final gambitPositions = [
          GameReportPosition(
            fen: gambit.startingFen,
            lines: [
              const GameReportLine(moves: ['f2f4'], depth: 12, centipawns: 10),
              const GameReportLine(moves: ['g1f3'], depth: 12, centipawns: 15),
            ],
          ),
          GameReportPosition(
            fen: gambit.mainline.first.fen,
            lines: [
              const GameReportLine(moves: ['e5f4'], depth: 12, centipawns: 5),
            ],
          ),
        ];
        final gWin = [
          gameReportWinPercentage(gambitPositions[0].bestLine),
          gameReportWinPercentage(gambitPositions[1].bestLine),
        ];
        expect(
          isBrilliantCandidate(
            index: 0,
            game: gambit,
            positions: gambitPositions,
            winPercentages: gWin,
          ),
          isFalse,
          reason: 'early pawn gambit must not enter deep !! verification',
        );
      },
    );
  });
}
