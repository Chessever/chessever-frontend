import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/notation/notation_pointer.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';

// ---------------------------------------------------------------------------
// Token types
// ---------------------------------------------------------------------------

enum NotationTokenType {
  move,
  openParen,
  closeParen,
  ellipsis,
  variationPlaceholder,
  comment,
  lichessComment,
}

// ---------------------------------------------------------------------------
// Token model
// ---------------------------------------------------------------------------

class NotationDisplayToken {
  final NotationTokenType type;
  final String text;
  final int depth;
  final String? pointerId;
  final int? moveIndex;
  final NotationMoveNode? node;
  final ChessMovePointer? pointer;
  final int? variationIndex;
  final bool isVariationHead;
  final ChessMovePointer? variationHeadPointer;
  final List<NotationMoveNode>? variationMoves;
  final NotationVariationNode? variation;
  final bool isCollapsed;
  final bool defaultsToCollapsed;
  final bool isForcedOpen;
  final String? heroineTag;
  final String? commentText;
  final String? variationColorKey;

  const NotationDisplayToken({
    required this.type,
    required this.text,
    required this.depth,
    this.pointerId,
    this.moveIndex,
    this.node,
    this.pointer,
    this.variationIndex,
    this.isVariationHead = false,
    this.variationHeadPointer,
    this.variationMoves,
    this.variation,
    this.isCollapsed = false,
    this.defaultsToCollapsed = false,
    this.isForcedOpen = false,
    this.heroineTag,
    this.commentText,
    this.variationColorKey,
  });
}

// ---------------------------------------------------------------------------
// Annotation presentation resolver
// ---------------------------------------------------------------------------

enum AnnotationPresentation {
  /// Evaluative annotation: inline symbol + optional inline comment.
  inlineSymbol,

  /// Book move: floating badge only, no inline symbol, no inline comment.
  badgeOnly,
}

AnnotationPresentation resolveAnnotationPresentation(
  LichessMoveAnnotationType type,
) {
  switch (type) {
    case LichessMoveAnnotationType.bookMove:
      return AnnotationPresentation.badgeOnly;
    case LichessMoveAnnotationType.brilliant:
    case LichessMoveAnnotationType.goodMove:
    case LichessMoveAnnotationType.bestMove:
    case LichessMoveAnnotationType.forced:
    case LichessMoveAnnotationType.inaccuracy:
    case LichessMoveAnnotationType.mistake:
    case LichessMoveAnnotationType.blunder:
    case LichessMoveAnnotationType.missedWin:
      return AnnotationPresentation.inlineSymbol;
  }
}

// ---------------------------------------------------------------------------
// Move text formatter
// ---------------------------------------------------------------------------

String formatMoveText(
  NotationMoveNode node, {
  bool suppressBlackMovePrefix = false,
}) {
  final buffer = StringBuffer();
  if (node.showMoveNumber) {
    final bool isNullMove = node.move.san == '--';
    final bool isFirstBlackInLine =
        !node.isWhiteMove && (node.showEllipsis || suppressBlackMovePrefix);
    if (isNullMove && !node.isWhiteMove) {
      buffer.write('${node.moveNumber}... ');
    } else if (isFirstBlackInLine) {
      // Still suppress for regular variation heads
    } else {
      final separator = node.isWhiteMove ? '. ' : '... ';
      buffer.write('${node.moveNumber}$separator');
    }
  }

  // We do NOT append NAGs here anymore. The UI will render them natively
  // with correct colors using the _getNagDisplay mapping in the view.
  // To avoid duplication, we also strip PGN-style text annotations (like !?)
  // from the end of the base SAN string.
  final cleanSan = node.move.san.replaceAll(RegExp(r'[!?]+$'), '');
  buffer.write(cleanSan);

  return buffer.toString();
}

// ---------------------------------------------------------------------------
// Collapse heuristic
// ---------------------------------------------------------------------------

// Only nesting depth decides the initial collapse state — line length never
// does, so long top-level analysis lines open in full instead of hiding
// behind a "... N moves" placeholder (Trello #959).
bool shouldCollapseByDefault(
  NotationVariationNode variation, {
  int autoCollapseDepth = 3,
}) {
  return variation.depth >= autoCollapseDepth;
}

// ---------------------------------------------------------------------------
// Token builder
// ---------------------------------------------------------------------------

List<NotationDisplayToken> buildNotationTokens(
  List<NotationMoveNode> moves, {
  required int depth,
  required int startingPly,
  NotationVariationNode? variationContext,
  required Map<String, NotationMoveNode> pointerMap,
  required Set<String> forcedOpenIds,
  required Map<String, String> variationComments,
  required Map<int, LichessMoveAnnotation> lichessAnnotations,
  required Set<String> collapsedVariationIds,
  required Set<String> expandedVariationIds,
  int autoCollapseDepth = 3,
  bool rawPgnMode = false,
}) {
  final tokens = <NotationDisplayToken>[];
  // A parsed variation belongs to the last common move in the game tree, but
  // visually it belongs after the following mainline move that it replaces.
  for (var i = 0; i < moves.length; i++) {
    final node = moves[i];
    final pointerList = List<Number>.of(node.pointer);
    final pointerId = NotationPointer.encode(pointerList);
    pointerMap[pointerId] = node;
    final isVariationHead = variationContext != null && i == 0;

    // CRITICAL FIX: Never suppress black move prefix for proper PGN notation
    // Variations starting with black moves MUST show ellipsis (e.g., "1... c5")
    final text = formatMoveText(node);
    final variationMovesList = variationContext?.moves;
    final variationHeadPointer =
        (variationMovesList?.isNotEmpty ?? false)
            ? List<Number>.of(variationMovesList!.first.pointer)
            : null;
    final moveIndex = node.ply - startingPly;
    tokens.add(
      NotationDisplayToken(
        type: NotationTokenType.move,
        text: text,
        depth: depth,
        pointerId: pointerId,
        moveIndex: moveIndex >= 0 ? moveIndex : null,
        node: node,
        pointer: pointerList,
        variationIndex: variationContext?.variationIndex,
        isVariationHead: isVariationHead,
        variationHeadPointer: variationHeadPointer,
        variationMoves: variationMovesList,
        variationColorKey: variationContext?.id,
      ),
    );

    // Analysis comments belong only to the original mainline. Variations can
    // reuse the same numeric ply, so indexing them into this map would attach
    // a mainline explanation to the wrong move. Book badges intentionally do
    // not create a prose block.
    final analysisAnnotation =
        !rawPgnMode && depth == 0 && moveIndex >= 0
            ? lichessAnnotations[moveIndex]
            : null;
    if (analysisAnnotation != null &&
        analysisAnnotation.comment.trim().isNotEmpty &&
        resolveAnnotationPresentation(analysisAnnotation.type) ==
            AnnotationPresentation.inlineSymbol) {
      tokens.add(
        NotationDisplayToken(
          type: NotationTokenType.lichessComment,
          text: analysisAnnotation.comment.trim(),
          depth: depth,
          pointerId: pointerId,
          moveIndex: moveIndex,
          node: node,
          pointer: pointerList,
        ),
      );
    }

    // Add PGN comments (skipped in raw PGN mode, or once the user has
    // overridden this move's comment — the override replaces the original
    // text rather than rendering beside it).
    if (!rawPgnMode &&
        node.move.comments != null &&
        !variationComments.containsKey(pointerId)) {
      for (final comment in node.move.comments!) {
        // Strip out Lichess extension tags from the comment text
        String cleanText =
            comment
                .replaceAll(RegExp(r'\[%clk\s+[^\]]+\]'), '')
                .replaceAll(RegExp(r'\[%eval\s+[^\]]+\]'), '')
                .replaceAll(RegExp(r'\[%cal\s+[^\]]+\]'), '')
                .replaceAll(RegExp(r'\[%csl\s+[^\]]+\]'), '')
                .replaceAll(RegExp(r'\[%emt\s+[^\]]+\]'), '')
                .replaceAll(RegExp(r'\[%tag\s+[^\]]+\]'), '')
                .trim();

        if (cleanText.isEmpty) {
          continue;
        }

        tokens.add(
          NotationDisplayToken(
            type: NotationTokenType.comment,
            text: cleanText,
            depth: depth,
            pointerId: pointerId,
            variation: variationContext,
            variationIndex: variationContext?.variationIndex,
            variationColorKey: variationContext?.id,
          ),
        );
      }
    }

    final moveComment = rawPgnMode ? null : variationComments[pointerId];
    if (moveComment != null && moveComment.isNotEmpty) {
      tokens.add(
        NotationDisplayToken(
          type: NotationTokenType.comment,
          text: moveComment,
          depth: depth,
          pointerId: pointerId,
          variation: variationContext,
          variationIndex: variationContext?.variationIndex,
          variationColorKey: variationContext?.id,
        ),
      );
    }

    final variationsToRender = <NotationVariationNode>[
      if (i > 0) ...moves[i - 1].variations,
      if (i == moves.length - 1) ...node.variations,
    ];
    for (final variation in variationsToRender) {
      final defaultCollapsed = shouldCollapseByDefault(
        variation,
        autoCollapseDepth: autoCollapseDepth,
      );
      final forcedOpen = forcedOpenIds.contains(variation.id);
      final manuallyCollapsed = collapsedVariationIds.contains(variation.id);
      final manuallyExpanded = expandedVariationIds.contains(variation.id);
      final variationHeroTagBase =
          'notation-variation-${variation.id}-${variation.depth}-${variation.variationIndex}';

      bool collapsed = defaultCollapsed;
      if (forcedOpen) {
        collapsed = false;
      } else if (defaultCollapsed) {
        if (manuallyExpanded) {
          collapsed = false;
        } else {
          collapsed = true;
        }
      } else {
        collapsed = manuallyCollapsed;
      }

      tokens.add(
        NotationDisplayToken(
          type: NotationTokenType.openParen,
          text: '(',
          depth: variation.depth,
          pointerId: null,
          variationIndex: variation.variationIndex,
          variation: variation,
          isCollapsed: collapsed,
          defaultsToCollapsed: defaultCollapsed,
          isForcedOpen: forcedOpen,
          variationHeadPointer:
              variation.moves.isNotEmpty
                  ? List<Number>.of(variation.moves.first.pointer)
                  : null,
          heroineTag: '$variationHeroTagBase-open',
          variationColorKey: variation.id,
        ),
      );
      if (collapsed) {
        tokens.add(
          NotationDisplayToken(
            type: NotationTokenType.variationPlaceholder,
            text: '... ${variation.moves.length} moves',
            depth: variation.depth,
            pointerId: null,
            variationIndex: variation.variationIndex,
            variation: variation,
            isCollapsed: true,
            defaultsToCollapsed: defaultCollapsed,
            isForcedOpen: forcedOpen,
            variationHeadPointer:
                variation.moves.isNotEmpty
                    ? List<Number>.of(variation.moves.first.pointer)
                    : null,
            heroineTag: '$variationHeroTagBase-placeholder',
            variationColorKey: variation.id,
          ),
        );
      } else {
        tokens.addAll(
          buildNotationTokens(
            variation.moves,
            depth: variation.depth,
            startingPly: startingPly,
            variationContext: variation,
            pointerMap: pointerMap,
            forcedOpenIds: forcedOpenIds,
            variationComments: variationComments,
            lichessAnnotations: lichessAnnotations,
            collapsedVariationIds: collapsedVariationIds,
            expandedVariationIds: expandedVariationIds,
            autoCollapseDepth: autoCollapseDepth,
            rawPgnMode: rawPgnMode,
          ),
        );
      }

      final variationComment =
          rawPgnMode ? null : variationComments[variation.id];
      if (variationComment != null && variationComment.isNotEmpty) {
        tokens.add(
          NotationDisplayToken(
            type: NotationTokenType.comment,
            text: variationComment,
            depth: variation.depth,
            variationIndex: variation.variationIndex,
            variation: variation,
            variationHeadPointer:
                variation.moves.isNotEmpty
                    ? List<Number>.of(variation.moves.first.pointer)
                    : null,
            commentText: variationComment,
            variationColorKey: variation.id,
          ),
        );
      }

      tokens.add(
        NotationDisplayToken(
          type: NotationTokenType.closeParen,
          text: ')',
          depth: variation.depth,
          pointerId: null,
          variationIndex: variation.variationIndex,
          variation: variation,
          isCollapsed: collapsed,
          defaultsToCollapsed: defaultCollapsed,
          isForcedOpen: forcedOpen,
          variationHeadPointer:
              variation.moves.isNotEmpty
                  ? List<Number>.of(variation.moves.first.pointer)
                  : null,
          heroineTag: '$variationHeroTagBase-close',
          variationColorKey: variation.id,
        ),
      );
    }
  }
  return tokens;
}
