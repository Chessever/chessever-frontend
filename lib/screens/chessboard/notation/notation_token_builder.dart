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
  buffer.write(node.move.san);
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// Collapse heuristic
// ---------------------------------------------------------------------------

bool shouldCollapseByDefault(
  NotationVariationNode variation, {
  int autoCollapseDepth = 3,
  int autoCollapseMoveThreshold = 12,
}) {
  if (variation.depth >= autoCollapseDepth) return true;
  if (variation.moves.length >= autoCollapseMoveThreshold) return true;
  return false;
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
  int autoCollapseMoveThreshold = 12,
}) {
  final tokens = <NotationDisplayToken>[];
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

    // Insert Lichess annotation comment for mainline moves only
    if (node.isMainline && moveIndex >= 0) {
      final annotation = lichessAnnotations[moveIndex];
      if (annotation != null &&
          resolveAnnotationPresentation(annotation.type) ==
              AnnotationPresentation.inlineSymbol &&
          annotation.comment.isNotEmpty) {
        tokens.add(
          NotationDisplayToken(
            type: NotationTokenType.lichessComment,
            text: annotation.comment,
            depth: depth,
            pointerId: pointerId,
          ),
        );
      }
    }

    final moveComment = variationComments[pointerId];
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

    for (final variation in node.variations) {
      final defaultCollapsed = shouldCollapseByDefault(
        variation,
        autoCollapseDepth: autoCollapseDepth,
        autoCollapseMoveThreshold: autoCollapseMoveThreshold,
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
            autoCollapseMoveThreshold: autoCollapseMoveThreshold,
          ),
        );
      }

      final variationComment = variationComments[variation.id];
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
