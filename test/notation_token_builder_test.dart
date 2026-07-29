import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/notation/notation_pointer.dart';
import 'package:chessever2/screens/chessboard/notation/notation_token_builder.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

ChessMove _move(
  String san, {
  List<ChessLine>? variations,
  List<String>? comments,
}) {
  return ChessMove(
    num: 1,
    fen: 'fen',
    san: san,
    uci: san,
    turn: ChessColor.white,
    variations: variations,
    comments: comments,
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
  Set<String> collapsedVariationIds = const {},
  Set<String> expandedVariationIds = const {},
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
    collapsedVariationIds: collapsedVariationIds,
    expandedVariationIds: expandedVariationIds,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('variation collapse defaults', () {
    test('keeps long first- and second-level variations expanded', () {
      final move = _treeFromSans(['e4']).mainline.first;

      for (final depth in [1, 2]) {
        final variation = NotationVariationNode(
          id: 'long-depth-$depth',
          parentPointer: const [0],
          variationIndex: 0,
          depth: depth,
          moves: List<NotationMoveNode>.filled(34, move),
        );

        expect(
          shouldCollapseByDefault(variation),
          isFalse,
          reason: 'Depth-$depth variations should open regardless of length.',
        );
      }
    });

    test('still collapses deeply nested variations', () {
      final variation = NotationVariationNode(
        id: 'deep-variation',
        parentPointer: const [0, 0, 0],
        variationIndex: 0,
        depth: 3,
        moves: const [],
      );

      expect(shouldCollapseByDefault(variation), isTrue);
    });

    test('manual collapse and expand override the defaults', () {
      final tree = _treeFromSans(
        ['e4'],
        variation: [
          _move(
            'd4',
            variations: [
              [
                _move(
                  'd5',
                  variations: [
                    [_move('c4')],
                  ],
                ),
              ],
            ],
          ),
        ],
      );
      final depthOne = tree.mainline.single.variations.single;
      final depthTwo = depthOne.moves.single.variations.single;
      final depthThree = depthTwo.moves.single.variations.single;

      final manuallyCollapsed = _buildTokens(
        tree,
        collapsedVariationIds: {depthOne.id},
      );
      final collapsedToken = manuallyCollapsed.firstWhere(
        (token) =>
            token.type == NotationTokenType.openParen &&
            token.variation?.id == depthOne.id,
      );
      expect(collapsedToken.isCollapsed, isTrue);

      final manuallyExpanded = _buildTokens(
        tree,
        expandedVariationIds: {depthThree.id},
      );
      final expandedToken = manuallyExpanded.firstWhere(
        (token) =>
            token.type == NotationTokenType.openParen &&
            token.variation?.id == depthThree.id,
      );
      expect(expandedToken.isCollapsed, isFalse);
    });
  });

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

  group('resolveNotationClassification (data present ⇒ markers)', () {
    test(
      'non-empty annotation map attaches inline presentation for mainline indices',
      () {
        final annotations = <int, LichessMoveAnnotation>{
          0: const LichessMoveAnnotation(
            type: LichessMoveAnnotationType.bookMove,
            comment: 'Book',
          ),
          3: const LichessMoveAnnotation(
            type: LichessMoveAnnotationType.blunder,
            comment: 'Blunder. d5 was best.',
          ),
          7: const LichessMoveAnnotation(
            type: LichessMoveAnnotationType.inaccuracy,
            comment: 'Inaccuracy.',
          ),
        };

        for (final entry in annotations.entries) {
          final resolved = resolveNotationClassification(
            rawPgnMode: false,
            isMainline: true,
            moveIndex: entry.key,
            annotations: annotations,
          );
          expect(resolved, isNotNull, reason: 'index ${entry.key}');
          expect(resolved!.type, entry.value.type);
          expect(
            resolveAnnotationPresentation(resolved.type),
            entry.value.type == LichessMoveAnnotationType.bookMove
                ? AnnotationPresentation.badgeOnly
                : AnnotationPresentation.inlineSymbol,
          );
        }

        expect(
          resolveNotationClassification(
            rawPgnMode: false,
            isMainline: true,
            moveIndex: 1,
            annotations: annotations,
          ),
          isNull,
        );
      },
    );

    test(
      'once annotations become non-empty, a subsequent resolve exposes them '
      'without any UI gesture',
      () {
        var annotations = const <int, LichessMoveAnnotation>{};
        expect(
          resolveNotationClassification(
            rawPgnMode: false,
            isMainline: true,
            moveIndex: 2,
            annotations: annotations,
          ),
          isNull,
        );

        annotations = {
          2: const LichessMoveAnnotation(
            type: LichessMoveAnnotationType.mistake,
            comment: 'Mistake. Nf3 was best.',
          ),
        };
        final after = resolveNotationClassification(
          rawPgnMode: false,
          isMainline: true,
          moveIndex: 2,
          annotations: annotations,
        );
        expect(after, isNotNull);
        expect(after!.type, LichessMoveAnnotationType.mistake);
        expect(
          resolveAnnotationPresentation(after.type),
          AnnotationPresentation.inlineSymbol,
        );
      },
    );

    test('raw PGN mode suppresses Lichess classifications on pure path', () {
      final annotations = <int, LichessMoveAnnotation>{
        0: const LichessMoveAnnotation(
          type: LichessMoveAnnotationType.brilliant,
          comment: '!!',
        ),
      };
      expect(
        resolveNotationClassification(
          rawPgnMode: true,
          isMainline: true,
          moveIndex: 0,
          annotations: annotations,
        ),
        isNull,
      );
    });

    test('quality NAGs suppress Lichess; evaluation NAGs do not', () {
      final annotations = <int, LichessMoveAnnotation>{
        0: const LichessMoveAnnotation(
          type: LichessMoveAnnotationType.blunder,
          comment: 'Blunder.',
        ),
      };
      expect(
        resolveNotationClassification(
          rawPgnMode: false,
          isMainline: true,
          moveIndex: 0,
          annotations: annotations,
          nags: const [2], // quality ?
        ),
        isNull,
      );
      expect(
        resolveNotationClassification(
          rawPgnMode: false,
          isMainline: true,
          moveIndex: 0,
          annotations: annotations,
          nags: const [14], // evaluation ⩲
        ),
        isNotNull,
      );
    });

    test('mainline moveIndex matches board pointer[0] / ply mapping', () {
      final tree = _treeFromSans(['e4', 'e5', 'Nf3', 'Nc6']);
      for (var i = 0; i < tree.mainline.length; i++) {
        final node = tree.mainline[i];
        final index = resolveMainlineMoveIndex(
          isMainline: node.isMainline,
          tokenMoveIndex: null,
          pointer: node.pointer,
          ply: node.ply,
          startingPly: tree.startingPly,
        );
        expect(index, i, reason: 'SAN ${node.move.san}');
        expect(node.pointer.first, i);
        expect(node.ply - tree.startingPly, i);
      }
    });

    test('buildNotationTokens moveIndex aligns with annotation keys', () {
      final tree = _treeFromSans(['e4', 'e5', 'Nf3', 'Nc6', 'Bb5']);
      final annotations = <int, LichessMoveAnnotation>{
        4: const LichessMoveAnnotation(
          type: LichessMoveAnnotationType.goodMove,
          comment: 'Good move.',
        ),
      };
      final tokens = _buildTokens(tree, lichessAnnotations: annotations);
      final moves =
          tokens.where((t) => t.type == NotationTokenType.move).toList();
      expect(moves.length, 5);
      for (var i = 0; i < moves.length; i++) {
        expect(moves[i].moveIndex, i);
        final resolved = resolveNotationClassification(
          rawPgnMode: false,
          isMainline: moves[i].node?.isMainline ?? false,
          moveIndex: moves[i].moveIndex,
          annotations: annotations,
        );
        if (i == 4) {
          expect(resolved?.type, LichessMoveAnnotationType.goodMove);
        } else {
          expect(resolved, isNull);
        }
      }
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
    test('variation header names the mainline move it replaces, not the last '
        'common move', () {
      const pgn = r'''
[Annotator "Durarbayli"]
[Black "Andrew"]
[BlackElo "2279"]
[Date "2025.06.07"]
[PlyCount "66"]
[Result "0-1"]
[White "Ruben"]
[WhiteElo "1930"]

1. e4 Nc6 2. Nf3 e5 3. Bc4 Bc5 4. d3 d6 5. O-O Nf6 6. c3 a5
7. Nbd2 Ba7 8. Re1 O-O 9. Nf1 Bd7 10. Bb3
(10. Ng3 a4 11. Bb5 a3 12. b4) 10... Ne7 11. Ng3 (11. a4)
11... a4 12. Bc2 Ng6 13. Be3 $2
{[%c_effect e3;square;e3;type;Mistake;persistent;true]}
(13. d4 Bg4) (13. h3 Re8 (13... c5 $2) 14. d4 exd4 15. cxd4)
13... Bxe3 14. fxe3 c5 15. Qd2 b5 16. d4 Qb6 17. Rad1 Rfd8
18. Qf2 Ng4 19. Qd2 Rac8 20. h3 Nf6 21. Qf2 (21. Nf5)
(21. Rf1 cxd4 22. exd4 b4) (21. Kh2 $5) 21... cxd4 22. exd4 b4
23. cxb4 Qxb4 24. Bb1 (24. b3 $1 24... a3) 24... Re8 25. Nf5 Rb8
26. Rd2 (26. Nxd6 $6 26... Ng4 $3 27. hxg4 Qxd6 28. dxe5 Qe7
29. g5 Bg4) 26... exd4 27. Qxd4 (27. Rxd4 Qxb2 28. Nxd6 Qxf2+
29. Kxf2 Rb2+ 30. Nd2 Reb8 31. e5 Ne8 32. N6c4 R2b7 33. Be4 Rc7)
27... Bxf5 28. Qxb4 Rxb4 29. exf5 Rxe1+ 30. Nxe1 Nf8 31. Nf3
(31. Nd3 Rd4 (31... Rb6) 32. Rd1 N8d7) 31... N8d7 32. Kf1 Kf8
33. Ke2 Ke7 0-1
''';
      final game = ChessGame.fromPgn('variation-label', pgn);
      final tree = NotationTreeBuilder.build(game);
      final pointerMap = <String, NotationMoveNode>{};
      final tokens = buildNotationTokens(
        tree.mainline,
        depth: 0,
        startingPly: tree.startingPly,
        pointerMap: pointerMap,
        forcedOpenIds: const {},
        variationComments: const {},
        lichessAnnotations: const {},
        collapsedVariationIds: const {},
        expandedVariationIds: const {},
      );
      final openVariationTokens =
          tokens
              .where((token) => token.type == NotationTokenType.openParen)
              .toList();
      final variation = openVariationTokens.first.variation!;

      final replacementMoveIndex = tokens.indexWhere(
        (token) =>
            token.type == NotationTokenType.move &&
            token.node?.move.san == 'Bb3' &&
            token.depth == 0,
      );
      final variationIndex = tokens.indexWhere(
        (token) => token.type == NotationTokenType.openParen,
      );
      final nextMainlineMoveIndex = tokens.indexWhere(
        (token) =>
            token.type == NotationTokenType.move &&
            token.node?.move.san == 'Ne7' &&
            token.depth == 0,
      );

      expect(
        variationAlternativeToText(variation, pointerMap),
        'Alt to 10.Bb3',
      );
      expect(variationIndex, greaterThan(replacementMoveIndex));
      expect(variationIndex, lessThan(nextMainlineMoveIndex));
      expect(
        variationAlternativeToText(variation, pointerMap),
        isNot(contains('Bd7')),
      );

      final expectedLabelsByVariationHead = <String, String>{
        'Ng3': 'Alt to 10.Bb3',
        'a4': 'Alt to 11.Ng3',
        'd4': 'Alt to 13.Be3',
        'h3': 'Alt to 13.Be3',
        'c5': 'Alt to 13...Re8',
        'Nf5': 'Alt to 21.Qf2',
        'Rf1': 'Alt to 21.Qf2',
        'Kh2': 'Alt to 21.Qf2',
        'b3': 'Alt to 24.Bb1',
        'Nxd6': 'Alt to 26.Rd2',
        'Rxd4': 'Alt to 27.Qxd4',
        'Nd3': 'Alt to 31.Nf3',
        'Rb6': 'Alt to 31...Rd4',
      };
      expect(
        openVariationTokens,
        hasLength(expectedLabelsByVariationHead.length),
      );

      for (final token in openVariationTokens) {
        final currentVariation = token.variation!;
        final headSan = currentVariation.moves.first.move.san;
        expect(
          variationAlternativeToText(currentVariation, pointerMap),
          expectedLabelsByVariationHead[headSan],
          reason: 'Incorrect alternative label for $headSan',
        );

        final replacementPointer = List<Number>.of(
          currentVariation.parentPointer,
        );
        replacementPointer[replacementPointer.length - 1]++;
        final replacementIndex = tokens.indexWhere(
          (candidate) =>
              candidate.pointerId == NotationPointer.encode(replacementPointer),
        );
        expect(replacementIndex, greaterThanOrEqualTo(0));
        expect(
          tokens.indexOf(token),
          greaterThan(replacementIndex),
          reason: '$headSan must render after the move it replaces',
        );
      }
    });

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

    test(
      'user override replaces the original PGN comment instead of appending '
      'a second one beside it',
      () {
        final tree = _treeFromSans(['e4', 'e5']);
        final original = tree.mainline.first;
        // Simulate importing a PGN whose e4 move already carries a comment,
        // e.g. `1. e4 {Great move!} e5`.
        final commentedNode = NotationMoveNode(
          move: _move('e4', comments: ['Great move!']),
          pointer: original.pointer,
          ply: original.ply,
          moveNumber: original.moveNumber,
          isWhiteMove: original.isWhiteMove,
          showMoveNumber: original.showMoveNumber,
          showEllipsis: original.showEllipsis,
          isMainline: original.isMainline,
          depth: original.depth,
          variations: original.variations,
        );
        final withComment = NotationTree(
          startingPly: tree.startingPly,
          mainline: [commentedNode, tree.mainline[1]],
        );

        final pointerId = NotationPointer.encode(commentedNode.pointer);

        // Before any override: the original PGN comment renders.
        final beforeOverride = _buildTokens(withComment);
        final beforeComments =
            beforeOverride
                .where((t) => t.type == NotationTokenType.comment)
                .toList();
        expect(beforeComments, hasLength(1));
        expect(beforeComments.first.text, 'Great move!');

        // After the user overrides it via updateVariationComment: only the
        // new text should render — not both, beside each other.
        final afterOverride = _buildTokens(
          withComment,
          variationComments: {pointerId: 'Edited comment'},
        );
        final afterComments =
            afterOverride
                .where((t) => t.type == NotationTokenType.comment)
                .toList();
        expect(afterComments, hasLength(1));
        expect(afterComments.first.text, 'Edited comment');
      },
    );

    test(
      'identical analysis and PGN comment text emits only the brighter '
      'PGN comment token',
      () {
        // Reproduce the stacked-duplicate bug: Lichess/report analysis and
        // the imported PGN both carry the same prose for one move. Only the
        // brighter NotationTokenType.comment block should survive.
        const shared =
            'This is a mistake. Black should play 7... O-O instead.';
        final tree = _treeFromSans(['e4', 'e5', 'Nf3']);
        final original = tree.mainline[1];
        final commentedNode = NotationMoveNode(
          move: _move('e5', comments: [shared]),
          pointer: original.pointer,
          ply: original.ply,
          moveNumber: original.moveNumber,
          isWhiteMove: original.isWhiteMove,
          showMoveNumber: original.showMoveNumber,
          showEllipsis: original.showEllipsis,
          isMainline: original.isMainline,
          depth: original.depth,
          variations: original.variations,
        );
        final withComment = NotationTree(
          startingPly: tree.startingPly,
          mainline: [tree.mainline[0], commentedNode, tree.mainline[2]],
        );
        final annotations = <int, LichessMoveAnnotation>{
          1: const LichessMoveAnnotation(
            type: LichessMoveAnnotationType.mistake,
            comment: shared,
          ),
        };

        final tokens = _buildTokens(
          withComment,
          lichessAnnotations: annotations,
        );

        final proseForMove =
            tokens
                .where(
                  (t) =>
                      (t.type == NotationTokenType.lichessComment ||
                          t.type == NotationTokenType.comment) &&
                      t.text == shared,
                )
                .toList();
        expect(
          proseForMove,
          hasLength(1),
          reason: 'Duplicate analysis+PGN prose must not stack two blocks',
        );
        expect(proseForMove.single.type, NotationTokenType.comment);
        expect(
          tokens.where((t) => t.type == NotationTokenType.lichessComment),
          isEmpty,
        );
      },
    );

    test(
      'analysis-only comment still emits lichessComment when there is no '
      'PGN twin',
      () {
        final tree = _treeFromSans(['e4', 'e5']);
        final annotations = <int, LichessMoveAnnotation>{
          1: const LichessMoveAnnotation(
            type: LichessMoveAnnotationType.blunder,
            comment: 'Blunder. d5 was best.',
          ),
        };
        final tokens = _buildTokens(tree, lichessAnnotations: annotations);

        expect(
          tokens.where((t) => t.type == NotationTokenType.lichessComment),
          hasLength(1),
        );
        expect(
          tokens.where((t) => t.type == NotationTokenType.comment),
          isEmpty,
        );
      },
    );

    test(
      'distinct analysis and PGN comments both emit when texts differ',
      () {
        final tree = _treeFromSans(['e4', 'e5']);
        final original = tree.mainline[1];
        final commentedNode = NotationMoveNode(
          move: _move('e5', comments: ['Opening theory note.']),
          pointer: original.pointer,
          ply: original.ply,
          moveNumber: original.moveNumber,
          isWhiteMove: original.isWhiteMove,
          showMoveNumber: original.showMoveNumber,
          showEllipsis: original.showEllipsis,
          isMainline: original.isMainline,
          depth: original.depth,
          variations: original.variations,
        );
        final withComment = NotationTree(
          startingPly: tree.startingPly,
          mainline: [tree.mainline[0], commentedNode],
        );
        final annotations = <int, LichessMoveAnnotation>{
          1: const LichessMoveAnnotation(
            type: LichessMoveAnnotationType.mistake,
            comment: 'Mistake. Black should castle.',
          ),
        };

        final tokens = _buildTokens(
          withComment,
          lichessAnnotations: annotations,
        );

        final lichess = tokens
            .where((t) => t.type == NotationTokenType.lichessComment)
            .toList();
        final pgn = tokens
            .where((t) => t.type == NotationTokenType.comment)
            .toList();
        expect(lichess, hasLength(1));
        expect(lichess.single.text, 'Mistake. Black should castle.');
        expect(pgn, hasLength(1));
        expect(pgn.single.text, 'Opening theory note.');
      },
    );

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
