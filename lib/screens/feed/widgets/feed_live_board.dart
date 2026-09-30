import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/classification_fx/classification_fx.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/widgets/feed_board.dart';
import 'package:chessever2/screens/feed/widgets/feed_classification.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The playable Feed board: the board screen's interactive chessground
/// [Chessboard] in the viewer's own theme and piece set, with the game
/// cards' coordinate-free face and a 200ms piece animation, driven by
/// [controller] (position, last move, check square and who may move live in
/// its [GameData]).
///
/// While the clip plays, pieces move tap-tap (touch the piece, then its
/// square): a finger that travels over a moving clip is the Feed's vertical
/// swipe, never a piece drag. Once the viewer has the board ([allowDrag]:
/// paused, stepping, at the end, or in their own line) pieces also drag.
/// Promotions are picked on the board itself.
///
/// Drawn over the board, in a [Stack] that covers it exactly:
/// * the move's classification badge on its destination square;
/// * the classified-move landing ([ClassificationLanding]);
/// * on a decisive final position, the loser's king tipped over on a red
///   square (the controller then carries a FEN without that king).
class FeedLiveBoard extends ConsumerWidget {
  const FeedLiveBoard({
    required this.controller,
    required this.size,
    required this.onMove,
    required this.onTouchedSquare,
    this.orientation = Side.white,
    this.allowDrag = false,
    this.badgeSquare,
    this.badgeClass,
    this.badgeTrigger,
    this.landingSquare,
    this.landingClass,
    this.landingTrigger,
    this.fallenSquare,
    this.fallenSide,
    super.key,
  });

  final ChessboardController controller;
  final double size;
  final Side orientation;

  /// Pieces drag as well as tap-tap; see the class doc.
  final bool allowDrag;

  /// A legal move the viewer made (promotion already resolved).
  final void Function(Move move, {bool? viaDragAndDrop}) onMove;

  /// Fires on pointer-down over a square, before the board acts on it.
  final void Function(Square square) onTouchedSquare;

  final Square? badgeSquare;
  final MoveClass? badgeClass;
  final Object? badgeTrigger;

  final Square? landingSquare;
  final MoveClass? landingClass;
  final Object? landingTrigger;

  /// Where the loser's king stood, and whose it is, on a decisive ending.
  final Square? fallenSquare;
  final Side? fallenSide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(boardSettingsProviderNew).valueOrNull ??
        const BoardSettingsNew();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final landing = landingClass != null ? landingSquare : null;

    final board = Chessboard(
      size: size,
      controller: controller,
      orientation: orientation,
      onMove: onMove,
      onTouchedSquare: onTouchedSquare,
      // The landed piece of a classified move settles on its square, keyed
      // like the [ClassificationLanding] overlay below.
      landingSquare: landing,
      landingKey: landing != null ? landingTrigger : null,
      settings: ChessboardSettings(
        colorScheme: settings.colorScheme,
        pieceAssets: settings.pieceAssets,
        // The game cards' face: no coordinates on a card-sized board.
        enableCoordinates: false,
        animationDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
        pieceShiftMethod: allowDrag
            ? PieceShiftMethod.either
            : PieceShiftMethod.tapTwoSquares,
        autoQueenPromotionOnPremove: false,
        enablePremoves: false,
        pieceOrientationBehavior: PieceOrientationBehavior.facingUser,
      ),
    );

    final square = size / 8;
    final flipped = orientation == Side.black;
    final fallen = fallenSquare;
    final fallenImage = fallenSide == null
        ? null
        : settings.pieceAssets[fallenSide == Side.white
              ? PieceKind.whiteKing
              : PieceKind.blackKing];
    final badgeAt = badgeSquare;
    final badgeKind = badgeClass;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          board,
          if (fallen != null) ...[
            Positioned(
              left: (flipped ? 7 - fallen.file : fallen.file) * square,
              top: (flipped ? fallen.rank : 7 - fallen.rank) * square,
              width: square,
              height: square,
              child: const IgnorePointer(
                child: ColoredBox(color: kFeedFallenSquare),
              ),
            ),
            if (fallenImage != null)
              Positioned(
                left: (flipped ? 7 - fallen.file : fallen.file) * square,
                top: (flipped ? fallen.rank : 7 - fallen.rank) * square,
                width: square,
                height: square,
                child: IgnorePointer(child: FeedFallenKing(image: fallenImage)),
              ),
          ],
          // Keyed so the conditional fallen-king tiles above, which appear in
          // the same build as a decisive game's last classified move, cannot
          // shift this slot: unkeyed, the Stack would reuse this Positioned
          // for the red tile and inflate a fresh landing with no latched
          // trigger, and that final landing would never play.
          Positioned.fill(
            key: const ValueKey('feed_landing'),
            child: IgnorePointer(
              child: ClassificationLanding(
                square: landingSquare,
                moveClass: landingClass,
                orientation: orientation,
                trigger: landingTrigger,
              ),
            ),
          ),
          if (badgeAt != null && badgeKind != null)
            FeedBoardBadge(
              key: const ValueKey('feed_badge'),
              square: badgeAt,
              moveClass: badgeKind,
              boardSize: size,
              orientation: orientation,
              trigger: badgeTrigger,
            ),
        ],
      ),
    );
  }
}
