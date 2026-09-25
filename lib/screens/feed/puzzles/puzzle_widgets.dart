import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle_model.dart';
import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:motor/motor.dart';

/// Lichess theme keys that describe the puzzle's length or source rather
/// than its idea; the header leaves them out.
const Set<String> _metaThemes = {
  'short',
  'long',
  'veryLong',
  'oneMove',
  'master',
  'masterVsMaster',
  'superGM',
};

const Map<String, String> _themeNames = {
  'attackingF2F7': 'Attacking f2/f7',
  'enPassant': 'En passant',
  'underPromotion': 'Underpromotion',
  'xRayAttack': 'X-ray attack',
  'kingsideAttack': 'Kingside attack',
  'queensideAttack': 'Queenside attack',
};

/// "mateIn2" → "Mate in 2", "advancedPawn" → "Advanced pawn".
String puzzleThemeName(String key) {
  final known = _themeNames[key];
  if (known != null) return known;
  final words = key
      .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z0-9])'), (_) => ' ')
      .toLowerCase()
      .trim();
  if (words.isEmpty) return key;
  return words[0].toUpperCase() + words.substring(1);
}

/// Up to [max] theme names for the header, the idea first ("Mate in 2",
/// "Fork") and the game phase last; `mate` is dropped when a mate-in-N says
/// the same thing more precisely.
List<String> puzzleThemeNames(List<String> themes, {int max = 3}) {
  const phases = {'opening', 'middlegame', 'endgame'};
  final hasMateIn = themes.any((t) => t.startsWith('mateIn'));
  final ideas = <String>[];
  final phase = <String>[];
  for (final t in themes) {
    if (_metaThemes.contains(t)) continue;
    if (t == 'mate' && hasMateIn) continue;
    (phases.contains(t) ? phase : ideas).add(t);
  }
  ideas.sort((a, b) {
    final am = a.startsWith('mateIn') ? 0 : 1;
    final bm = b.startsWith('mateIn') ? 0 : 1;
    return am.compareTo(bm);
  });
  return [...ideas, ...phase].take(max).map(puzzleThemeName).toList();
}

/// Words Lichess's opening tags spell without their apostrophe.
const Map<String, String> _openingWords = {
  'Kings': "King's",
  'Queens': "Queen's",
  'Bishops': "Bishop's",
  'Petrovs': "Petrov's",
  'Vant': "Van't",
};

/// The opening family a puzzle came from, from Lichess's opening tags
/// ("Sicilian_Defense", "Sicilian_Defense_Najdorf_Variation", ...): the first,
/// broadest tag, readable ("Kings_Pawn_Game" -> "King's Pawn Game"). Null
/// without tags.
String? puzzleOpeningName(List<String> tags) {
  for (final tag in tags) {
    final words = [
      for (final w in tag.split('_'))
        if (w.isNotEmpty) _openingWords[w] ?? w,
    ];
    if (words.isNotEmpty) return words.join(' ');
  }
  return null;
}

/// Sits where a game page's eval bar sits: one segment per move the solver
/// has to find, filling from the bottom as they are found. Moves shown by
/// "Solution" fill in a quieter tone.
class PuzzleProgressRail extends StatelessWidget {
  const PuzzleProgressRail({
    required this.total,
    required this.found,
    required this.shown,
    required this.height,
    this.width = 20,
    super.key,
  });

  /// Moves the solver has to find.
  final int total;

  /// Found by the viewer.
  final int found;

  /// Found plus shown by the solution (>= [found]).
  final int shown;
  final double height;
  final double width;

  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final light = context.isLightTheme;
    final n = total < 1 ? 1 : total;
    final segment = (height - _gap * (n - 1)) / n;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: shown > found
          ? 'Solution shown, $found of $n moves found'
          : '$found of $n moves found',
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            for (var i = 0; i < n; i++)
              Positioned(
                left: 0,
                right: 0,
                bottom: i * (segment + _gap),
                height: segment,
                // Found moves in full ink, shown ones a step quieter, the
                // rest a recessed well; each clears 3:1 against the page in
                // either theme (the light eval white would vanish on paper).
                child: _RailSegment(
                  filled: i < shown,
                  fill: i < found
                      ? (light ? colors.textPrimary : colors.evalWhite)
                      : colors.textTertiary,
                  empty: light ? colors.surfaceRecessed : colors.surface,
                  instant: reduceMotion,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One rail segment. The fill grows from the segment's floor on a spring,
/// a clipped rectangle, so its edges never change shape mid-motion.
class _RailSegment extends StatelessWidget {
  const _RailSegment({
    required this.filled,
    required this.fill,
    required this.empty,
    required this.instant,
  });

  final bool filled;
  final Color fill;
  final Color empty;
  final bool instant;

  @override
  Widget build(BuildContext context) {
    Widget paint(double t) => ColoredBox(
      color: empty,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: t.clamp(0.0, 1.0),
          widthFactor: 1,
          child: ColoredBox(color: fill),
        ),
      ),
    );
    if (instant) return paint(filled ? 1 : 0);
    return SingleMotionBuilder(
      value: filled ? 1.0 : 0.0,
      motion: const CupertinoMotion.smooth(),
      builder: (context, t, _) => paint(t),
    );
  }
}

/// A player line above or below the puzzle board: the side's king, then
/// title, Lichess name and rating when the puzzle carries players, else just
/// the side ("White"). On paper the king comes from the viewer's piece set;
/// in the dark a set's black king is black on black, so both sides draw one
/// ink king instead, filled for White and hollow for Black.
class PuzzlePlayerRow extends StatelessWidget {
  const PuzzlePlayerRow({
    required this.player,
    required this.side,
    required this.pieceAssets,
    required this.height,
    this.isSolver = false,
    super.key,
  });

  final FeedPuzzlePlayer? player;
  final Side side;
  final PieceAssets pieceAssets;
  final double height;

  /// The viewer plays this side (read out to screen readers; the board's
  /// orientation already says it on screen).
  final bool isSolver;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The game cards' row type (their list rows set 10pt, title in the
    // title accent, rating muted), so a puzzle page's rows read like a game
    // page's.
    final base = AppTypography.textXsMedium.copyWith(
      fontSize: 10,
      height: 1.15,
      fontWeight: FontWeight.w500,
      color: colors.textPrimary,
    );
    final p = player;
    final sideName = side == Side.white ? 'White' : 'Black';
    final ink = !context.isLightTheme;
    final king = ink
        ? null
        : pieceAssets[side == Side.white
              ? PieceKind.whiteKing
              : PieceKind.blackKing];
    final title = p?.title?.trim() ?? '';
    return SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Center(
              child: ink
                  ? CustomPaint(
                      size: const Size.square(14),
                      painter: _SideKingPainter(
                        ink: colors.textPrimary,
                        filled: side == Side.white,
                      ),
                    )
                  : king == null
                  ? null
                  : Image(
                      image: king,
                      width: 14,
                      height: 14,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (p == null)
                    TextSpan(text: sideName)
                  else ...[
                    if (title.isNotEmpty)
                      TextSpan(
                        text: '$title ',
                        style: base.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.titleAccent,
                        ),
                      ),
                    TextSpan(text: p.name),
                    if (p.rating != null)
                      TextSpan(
                        text: ' ${p.rating}',
                        style: base.copyWith(color: colors.textPrimaryMuted),
                      ),
                  ],
                ],
              ),
              style: base,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              semanticsLabel:
                  '$sideName: ${p?.name ?? sideName}'
                  '${p?.rating != null ? ', rated ${p!.rating}' : ''}'
                  '${isSolver ? ', your side' : ''}',
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark theme's side king in a 24-unit square: one contour (crown,
/// body, base) under a stroked cross, so the same shape reads filled or
/// hollow at the same size.
final Path _sideKingContour = Path()
  ..moveTo(5.4, 22.8)
  ..lineTo(18.6, 22.8)
  ..lineTo(18.6, 19.4)
  ..lineTo(16.2, 19.4)
  ..lineTo(14.8, 13.6)
  ..lineTo(17.0, 13.6)
  ..lineTo(18.8, 6.6)
  ..lineTo(5.2, 6.6)
  ..lineTo(7.0, 13.6)
  ..lineTo(9.2, 13.6)
  ..lineTo(7.8, 19.4)
  ..lineTo(5.4, 19.4)
  ..close();

/// Paints [_sideKingContour] and its cross in [ink]: [filled] for White,
/// the outline alone for Black, so the page shows through as the black
/// piece's body.
class _SideKingPainter extends CustomPainter {
  const _SideKingPainter({required this.ink, required this.filled});

  final Color ink;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24);
    if (filled) canvas.drawPath(_sideKingContour, Paint()..color = ink);
    canvas
      ..drawPath(_sideKingContour, line)
      ..drawLine(const Offset(12, 1.2), const Offset(12, 6.6), line)
      ..drawLine(const Offset(9.6, 3.6), const Offset(14.4, 3.6), line)
      ..restore();
  }

  @override
  bool shouldRepaint(_SideKingPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.filled != filled;
}

/// Flat 44px button in the Feed's end-card language: the press is
/// [FeedPressable]'s (it gives a little and dims), nothing jumps. A null
/// [onTap] dims it.
class PuzzleButton extends StatelessWidget {
  const PuzzleButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.semanticsLabel,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;

  /// Inverse fill (ink on the page colour) for the one forward action.
  final bool primary;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    final fill = primary ? colors.textPrimary : colors.surfaceRecessed;
    final ink = !enabled
        ? colors.textSecondary.withValues(alpha: 0.72)
        : primary
        ? colors.background
        : colors.textPrimary;
    return FeedPressable(
      semanticsLabel: semanticsLabel ?? label,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
        ),
        // Scales down rather than cutting a label at large text sizes.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: AppTypography.textSmMedium.copyWith(
              fontSize: 14,
              height: 1.2,
              fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// The classification badge the board screen draws on a classified move's
/// square (top-right corner, clamped inside the board), for puzzle moves.
class PuzzleMoveBadge extends StatelessWidget {
  const PuzzleMoveBadge({
    required this.square,
    required this.moveClass,
    required this.boardSize,
    required this.orientation,
    super.key,
  });

  final Square square;
  final MoveClass moveClass;
  final double boardSize;
  final Side orientation;

  static LichessMoveAnnotationType? _typeOf(MoveClass c) => switch (c) {
    MoveClass.brilliant => LichessMoveAnnotationType.brilliant,
    MoveClass.great => LichessMoveAnnotationType.goodMove,
    MoveClass.best => LichessMoveAnnotationType.bestMove,
    MoveClass.inaccuracy => LichessMoveAnnotationType.inaccuracy,
    MoveClass.mistake => LichessMoveAnnotationType.mistake,
    MoveClass.blunder => LichessMoveAnnotationType.blunder,
    MoveClass.missedWin => LichessMoveAnnotationType.missedWin,
    MoveClass.book => LichessMoveAnnotationType.bookMove,
    MoveClass.interesting => null,
  };

  /// The classification's text colour, for words that echo the badge.
  static Color? colorOf(MoveClass c) {
    final type = _typeOf(c);
    return type == null ? null : moveAnnotationColor(type);
  }

  @override
  Widget build(BuildContext context) {
    final type = _typeOf(moveClass);
    if (type == null) return const SizedBox.shrink();
    final sq = boardSize / 8;
    final file = orientation == Side.white ? square.file : 7 - square.file;
    final row = orientation == Side.white ? 7 - square.rank : square.rank;
    final size = sq * 0.40;
    final left = (file * sq + sq - size / 2).clamp(0.0, boardSize - size);
    final top = (row * sq - size / 2 + sq * 0.04).clamp(0.0, boardSize - size);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final badge = DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: SvgPicture.asset(
        moveAnnotationIconAsset(type),
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: IgnorePointer(
        child: reduceMotion
            ? badge
            : SingleMotionBuilder(
                key: ValueKey(Object.hash(square, moveClass)),
                from: 0.6,
                value: 1,
                motion: const CupertinoMotion.bouncy(),
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: badge,
              ),
      ),
    );
  }
}
