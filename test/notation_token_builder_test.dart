import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/notation/notation_token_builder.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

ChessMove _move(String san, {List<ChessLine>? variations}) {
  return ChessMove(
    num: 1,
    fen: 'fen',
    san: san,
    uci: san,
    turn: ChessColor.white,
    variations: variations,
  );
}

/// Build a simple game with the given mainline SANs and return its
/// NotationTree. Starting position is standard (ply 0).
NotationTree _treeFromSans(List<String> sans, {ChessLine? variation}) {
  final moves = <ChessMove>[];
  for (var i = 0; i < sans.length; i++) {
    final isFirst = i == 0 && variation != null;
    moves.add(_move(sans[i], variations: isFirst ? [variation] : null));
  }
  final game = ChessGame(
    gameId: 'test',
    startingFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    metadata: const {},
    mainline: moves,
  );
  return NotationTreeBuilder.build(game);
}

/// Convenience: run the token builder with defaults and return the token list.
List<NotationDisplayToken> _buildTokens(
  NotationTree tree, {
  Map<int, LichessMoveAnnotation> lichessAnnotations = const {},
  Map<String, String> variationComments = const {},
}) {
  final pointerMap = <String, NotationMoveNode>{};
  return buildNotationTokens(
    tree.mainline,
    depth: 0,
    startingPly: tree.startingPly,
    pointerMap: pointerMap,
    forcedOpenIds: const {},
    variationComments: variationComments,
    lichessAnnotations: lichessAnnotations,
    collapsedVariationIds: const {},
    expandedVariationIds: const {},
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('resolveAnnotationPresentation', () {
    test('evaluative types resolve to inlineSymbol', () {
      const evaluativeTypes = [
        LichessMoveAnnotationType.brilliant,
        LichessMoveAnnotationType.goodMove,
        LichessMoveAnnotationType.bestMove,
        LichessMoveAnnotationType.inaccuracy,
        LichessMoveAnnotationType.mistake,
        LichessMoveAnnotationType.blunder,
        LichessMoveAnnotationType.missedWin,
      ];
      for (final type in evaluativeTypes) {
        expect(
          resolveAnnotationPresentation(type),
          AnnotationPresentation.inlineSymbol,
          reason: '${type.name} should be inlineSymbol',
        );
      }
    });

    test('bookMove resolves to badgeOnly', () {
      expect(
        resolveAnnotationPresentation(LichessMoveAnnotationType.bookMove),
        AnnotationPresentation.badgeOnly,
      );
    });
  });

  group('formatMoveText', () {
    test('white move gets number prefix', () {
      final tree = _treeFromSans(['e4']);
      final node = tree.mainline.first;
      expect(formatMoveText(node), '1. e4');
    });

    test('black move as continuation omits prefix', () {
      final tree = _treeFromSans(['e4', 'e5']);
      // Second move is black; showMoveNumber is false for continuation
      final node = tree.mainline[1];
      final text = formatMoveText(node);
      expect(text, 'e5');
    });
  });

  group('buildNotationTokens', () {
    test('non-annotated moves produce only move tokens', () {
      final tree = _treeFromSans(['e4', 'e5', 'Nf3']);
      final tokens = _buildTokens(tree);

      final moveTokens =
          tokens.where((t) => t.type == NotationTokenType.move).toList();
      expect(moveTokens.length, 3);
      expect(moveTokens[0].text, '1. e4');
      expect(moveTokens[1].text, 'e5');
      expect(moveTokens[2].text, '2. Nf3');

      // No lichessComment tokens
      final lichessComments = tokens.where(
        (t) => t.type == NotationTokenType.lichessComment,
      );
      expect(lichessComments, isEmpty);
    });

    test(
      'evaluative annotation with comment inserts lichessComment token after move',
      () {
        final tree = _treeFromSans(['e4', 'e5', 'Nf3']);
        final annotations = <int, LichessMoveAnnotation>{
          1: const LichessMoveAnnotation(
            type: LichessMoveAnnotationType.blunder,
            comment: 'Blunder. d5 was best.',
          ),
        };
        final tokens = _buildTokens(tree, lichessAnnotations: annotations);

        final lichessComments =
            tokens
                .where((t) => t.type == NotationTokenType.lichessComment)
                .toList();
        expect(lichessComments.length, 1);
        expect(lichessComments.first.text, 'Blunder. d5 was best.');

        // Verify it appears right after the annotated move (moveIndex 1 = e5)
        final annotatedMoveIdx = tokens.indexWhere(
          (t) => t.type == NotationTokenType.move && t.moveIndex == 1,
        );
        expect(annotatedMoveIdx, greaterThanOrEqualTo(0));
        expect(
          tokens[annotatedMoveIdx + 1].type,
          NotationTokenType.lichessComment,
        );
      },
    );

    test(
      'evaluative annotation with empty comment does not insert lichessComment',
      () {
        final tree = _treeFromSans(['e4', 'e5']);
        final annotations = <int, LichessMoveAnnotation>{
          0: const LichessMoveAnnotation(
            type: LichessMoveAnnotationType.bestMove,
            comment: '',
          ),
        };
        final tokens = _buildTokens(tree, lichessAnnotations: annotations);

        final lichessComments = tokens.where(
          (t) => t.type == NotationTokenType.lichessComment,
        );
        expect(lichessComments, isEmpty);
      },
    );

    test('bookMove does not insert lichessComment token', () {
      final tree = _treeFromSans(['e4', 'e5']);
      final annotations = <int, LichessMoveAnnotation>{
        0: const LichessMoveAnnotation(
          type: LichessMoveAnnotationType.bookMove,
          comment: 'Book move.',
        ),
      };
      final tokens = _buildTokens(tree, lichessAnnotations: annotations);

      final lichessComments = tokens.where(
        (t) => t.type == NotationTokenType.lichessComment,
      );
      expect(lichessComments, isEmpty);
    });

    test('variation moves do not receive Lichess annotation tokens', () {
      final variationLine = [_move('d5')];
      final tree = _treeFromSans(['e4', 'e5'], variation: variationLine);
      // Annotate every move index
      final annotations = <int, LichessMoveAnnotation>{
        0: const LichessMoveAnnotation(
          type: LichessMoveAnnotationType.brilliant,
          comment: 'Brilliant!',
        ),
        1: const LichessMoveAnnotation(
          type: LichessMoveAnnotationType.mistake,
          comment: 'Mistake.',
        ),
      };
      final tokens = _buildTokens(tree, lichessAnnotations: annotations);

      // Only mainline moves (depth 0) should get lichessComment tokens
      final lichessComments =
          tokens
              .where((t) => t.type == NotationTokenType.lichessComment)
              .toList();
      // Both mainline moves are annotated with non-empty comments
      expect(lichessComments.length, 2);
      // Ensure all lichessComment tokens are at depth 0
      for (final comment in lichessComments) {
        expect(comment.depth, 0);
      }
    });

    test('move formatting preserves white/black number prefixes', () {
      final tree = _treeFromSans(['e4', 'e5', 'Nf3', 'Nc6', 'Bb5']);
      final tokens = _buildTokens(tree);
      final moves =
          tokens.where((t) => t.type == NotationTokenType.move).toList();

      expect(moves[0].text, '1. e4');
      expect(moves[1].text, 'e5');
      expect(moves[2].text, '2. Nf3');
      expect(moves[3].text, 'Nc6');
      expect(moves[4].text, '3. Bb5');
    });
  });

  group('exportGameToPgn', () {
    test('round-trips variations that start with a black move', () {
      final game = ChessGame(
        gameId: 'test',
        startingFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        metadata: const {},
        mainline: [
          _move(
            'e4',
            variations: [
              [_move('c5')],
            ],
          ),
          _move('e5'),
          _move('Nf3'),
        ],
      );

      final pgn = exportGameToPgn(game);
      expect(pgn, contains('1... c5'));

      final reparsed = ChessGame.fromPgn('round_trip', pgn);
      expect(reparsed.mainline, hasLength(3));
      expect(reparsed.mainline.first.variations, isNotNull);
      expect(reparsed.mainline.first.variations, hasLength(1));
      expect(reparsed.mainline.first.variations!.first, hasLength(1));
      expect(reparsed.mainline.first.variations!.first.first.san, 'c5');
    });
  });
}
