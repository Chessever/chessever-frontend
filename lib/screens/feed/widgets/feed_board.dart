import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Loser's king square on a decisive final position.
const Color kFeedFallenSquare = Color(0xCCF53236);

/// Marks drawn straight onto the board's squares (the paused triangle, the
/// 2x sheen, the hold ring, a caption without a class colour). They sit on
/// the viewer's board theme, which does not follow the app theme, so they
/// do not either: light marks with a tight dark shadow read on every board.
const Color kFeedOnBoardInk = Color(0xFFFFFFFF);

/// The dim laid over the board while the viewer has paused the clip.
const Color kFeedOnBoardScrim = Color(0x2E000000);

/// The Feed board: the app's non-interactive [StaticChessboard] in the
/// viewer's own board theme, with pieces sliding 200ms between plies.
///
/// When [loser] is set the position is final and decisive: that side's king
/// leaves the board and is redrawn tipped over on a red square, the same
/// ending the game cards use.
class FeedBoard extends ConsumerWidget {
  const FeedBoard({
    required this.size,
    required this.fen,
    this.lastMove,
    this.loser,
    super.key,
  });

  final double size;
  final String fen;
  final Move? lastMove;
  final Side? loser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(boardSettingsProviderNew).valueOrNull ??
        const BoardSettingsNew();

    var displayFen = fen;
    Square? fallenSquare;
    final loserSide = loser;
    if (loserSide != null) {
      final removed = feedWithoutKing(fen, loserSide);
      if (removed != null) {
        displayFen = removed.fen;
        fallenSquare = removed.square;
      }
    }

    final board = StaticChessboard(
      size: size,
      orientation: Side.white,
      fen: displayFen,
      lastMove: lastMove,
      settings: StaticChessboardSettings(
        colorScheme: settings.colorScheme,
        pieceAssets: settings.pieceAssets,
        enableCoordinates: false,
        animationDuration: const Duration(milliseconds: 200),
      ),
    );

    if (fallenSquare == null || loserSide == null) {
      return SizedBox.square(dimension: size, child: board);
    }

    final square = size / 8;
    final left = fallenSquare.file * square;
    final top = (7 - fallenSquare.rank) * square;
    final image =
        settings.pieceAssets[loserSide == Side.white
            ? PieceKind.whiteKing
            : PieceKind.blackKing];

    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          board,
          Positioned(
            left: left,
            top: top,
            width: square,
            height: square,
            child: const ColoredBox(color: kFeedFallenSquare),
          ),
          if (image != null)
            Positioned(
              left: left,
              top: top,
              width: square,
              height: square,
              child: FeedFallenKing(image: image),
            ),
        ],
      ),
    );
  }
}

/// [fen] with [side]'s king lifted off the board, and the square it stood
/// on — the decisive-ending display, where the king is redrawn tipped over.
({String fen, Square square})? feedWithoutKing(String fen, Side side) {
  try {
    final parts = fen.trim().split(RegExp(r'\s+'));
    final board = Board.parseFen(parts.first);
    final king = board.kingOf(side);
    if (king == null) return null;
    final rest = parts.skip(1).join(' ');
    final placement = board.removePieceAt(king).fen;
    return (fen: rest.isEmpty ? placement : '$placement $rest', square: king);
  } catch (_) {
    return null;
  }
}

/// The losing king, tipping over once the mating move has landed. With
/// reduced motion it is simply drawn already down.
class FeedFallenKing extends StatefulWidget {
  const FeedFallenKing({required this.image, super.key});

  final ImageProvider image;

  @override
  State<FeedFallenKing> createState() => _FeedFallenKingState();
}

class _FeedFallenKingState extends State<FeedFallenKing> {
  static const double _tipped = -math.pi / 4;

  double _angle = 0;
  Timer? _tip;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _tip?.cancel();
      _tip = null;
      _angle = _tipped;
      return;
    }
    if (_angle == _tipped || _tip != null) return;
    // Let the last move finish sliding before the king goes down.
    _tip = Timer(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _angle = _tipped);
    });
  }

  @override
  void dispose() {
    _tip?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final king = Image(image: widget.image, fit: BoxFit.contain);
    if (MediaQuery.disableAnimationsOf(context)) {
      return Transform.rotate(angle: _tipped, child: king);
    }
    return SingleMotionBuilder(
      value: _angle,
      motion: const CupertinoMotion.bouncy(),
      builder: (context, angle, child) =>
          Transform.rotate(angle: angle, child: child),
      child: king,
    );
  }
}

/// Dim + bare play glyph shown while the viewer has paused the clip. No
/// disc behind it: the triangle stands on the board by itself, lifted by a
/// tight shadow cast straight down (the same one [FeedCaption] uses).
class FeedPausedOverlay extends StatelessWidget {
  const FeedPausedOverlay({super.key});

  // 26x30 viewBox, drawn larger now that no disc frames it.
  static const double _glyphWidth = 30;
  static const double _glyphHeight = _glyphWidth * 30 / 26;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        key: const ValueKey('feed_paused'),
        children: [
          const Positioned.fill(child: ColoredBox(color: kFeedOnBoardScrim)),
          Center(
            child: Semantics(
              label: 'Paused',
              // The glyph's viewBox already carries the triangle's optical
              // offset, so it is centred as-is.
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Transform.translate(
                    offset: const Offset(0, 1),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                      child: const FeedGlyph(
                        FeedGlyphs.play,
                        width: _glyphWidth,
                        height: _glyphHeight,
                        color: Color(0x73000000),
                      ),
                    ),
                  ),
                  const FeedGlyph(
                    FeedGlyphs.play,
                    width: _glyphWidth,
                    height: _glyphHeight,
                    color: kFeedOnBoardInk,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Right-side sheen and the "2×" status while the right third is held.
class FeedFastOverlay extends StatelessWidget {
  const FeedFastOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.textPrimary;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerRight,
              widthFactor: 0.46,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kFeedOnBoardInk.withValues(alpha: 0),
                      kFeedOnBoardInk.withValues(alpha: 0.1),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                label: 'Playing at double speed',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.popup.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '2×',
                        style: AppTypography.textSmBold.copyWith(
                          fontSize: 13,
                          height: 1.2,
                          color: ink,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const _NudgingChevrons(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The double chevron drifts 3px right and back while 2x is held, the same
/// small push the design animates, driven by a spring ping-pong.
class _NudgingChevrons extends StatefulWidget {
  const _NudgingChevrons();

  @override
  State<_NudgingChevrons> createState() => _NudgingChevronsState();
}

class _NudgingChevronsState extends State<_NudgingChevrons> {
  double _dx = 0;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: the chevrons hold still, no ping-pong timer at all.
    if (MediaQuery.disableAnimationsOf(context)) {
      _timer?.cancel();
      _timer = null;
      _dx = 0;
      return;
    }
    _timer ??= Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (mounted) setState(() => _dx = _dx == 0 ? 3 : 0);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glyph = FeedGlyph(
      FeedGlyphs.fast,
      width: 18,
      height: 12,
      color: context.colors.textPrimary,
    );
    if (MediaQuery.disableAnimationsOf(context)) return glyph;
    return SingleMotionBuilder(
      value: _dx,
      motion: const CupertinoMotion.smooth(),
      builder: (context, dx, child) =>
          Transform.translate(offset: Offset(dx, 0), child: child),
      child: glyph,
    );
  }
}

/// Ring that blooms under the finger when the 2x hold engages.
class FeedHoldRipple extends StatelessWidget {
  const FeedHoldRipple({required this.center, this.onBoard = true, super.key});

  final Offset center;

  /// Blooming over the board's squares (on-board ink) rather than the page.
  final bool onBoard;

  @override
  Widget build(BuildContext context) {
    final ink = onBoard ? kFeedOnBoardInk : context.colors.textPrimary;
    const size = 72.0;
    // On the squares the light ring carries a crisp dark rim, so it reads on
    // light and dark squares of any board theme alike.
    final inner = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ink.withValues(alpha: 0.1),
        border: Border.all(color: ink.withValues(alpha: 0.85), width: 2),
      ),
    );
    final ring = onBoard
        ? DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x66000000)),
            ),
            child: Padding(padding: const EdgeInsets.all(1), child: inner),
          )
        : inner;
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        // Reduced motion: no bloom, the ring simply sits at its open state.
        child: MediaQuery.disableAnimationsOf(context)
            ? Opacity(
                opacity: 0.35,
                child: Transform.scale(scale: 1.25, child: ring),
              )
            : SingleMotionBuilder(
                from: 0.6,
                value: 1.25,
                motion: const CupertinoMotion.smooth(),
                builder: (context, scale, child) {
                  // Fade tracks the bloom: 0.9 at the press, 0.35 once open.
                  final t = ((scale - 0.6) / 0.65).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: 0.9 - 0.55 * t,
                    child: Transform.scale(scale: scale, child: child),
                  );
                },
                child: ring,
              ),
      ),
    );
  }
}

/// Headline caption drawn straight onto the board ("Brilliant", "Checkmate").
/// No chip: the word carries its classification colour over a dark stroke,
/// so its edge clears 3:1 on light and dark squares of every board theme
/// (a blur shadow alone left white at 2.35:1 on the grey light square).
class FeedCaption extends StatelessWidget {
  const FeedCaption({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  // Shared so the stroke layer's style compares equal across rebuilds.
  // Round joins keep the halo from spiking on the corners of 'f' and 'k'.
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeJoin = StrokeJoin.round
    ..color = const Color(0xB3000000);

  @override
  Widget build(BuildContext context) {
    final base = AppTypography.displayXsBold.copyWith(
      fontSize: 28,
      height: 1.1,
      letterSpacing: 0.3,
    );
    Text layer(TextStyle style) => Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 1,
      softWrap: false,
      style: style,
    );
    // Long labels ("Queen sacrifice", "Underpromotion") at the Feed's larger
    // text scales outgrow a small board: shrink to fit, never clip. Both
    // layers scale together inside the one FittedBox, so they stay registered.
    final text = FittedBox(
      fit: BoxFit.scaleDown,
      child: Stack(
        children: [
          // The stroke is read once, by the fill above it.
          ExcludeSemantics(
            child: layer(
              base.copyWith(
                foreground: _stroke,
                shadows: const [
                  Shadow(
                    color: Color(0x66000000),
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          layer(base.copyWith(color: color)),
        ],
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return IgnorePointer(child: text);
    }
    return IgnorePointer(
      child: SingleMotionBuilder(
        key: ValueKey(label),
        from: 0.86,
        value: 1,
        motion: const CupertinoMotion.bouncy(),
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: text,
      ),
    );
  }
}
