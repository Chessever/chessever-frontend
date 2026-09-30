import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_classification.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:motor/motor.dart';

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// One move in the strip: "15.", "Nf3", its class.
@immutable
class FeedStripToken {
  const FeedStripToken({required this.san, this.number, this.moveClass});

  /// "15." before a White move, "15..." before a Black move that opens a
  /// run, null otherwise.
  final String? number;
  final String san;
  final MoveClass? moveClass;
}

/// The Feed's compact notation: the game's moves in one scrolling line under
/// the board, the one on the board set in full ink with its classification,
/// the rest dimmed. Any move is a tap target that jumps the board there; the
/// line keeps the current move in view as the clip plays, and keeps up with
/// a scrub move for move ([follow]).
///
/// [leading] and [trailing] sit either side of the scroller (the "Your line"
/// label, the eval, the step controls, "Back to game").
class FeedMoveStrip extends StatefulWidget {
  const FeedMoveStrip({
    required this.tokens,
    required this.current,
    required this.onTokenTap,
    required this.height,
    this.leading,
    this.trailing = const [],
    this.follow = false,
    super.key,
  });

  final List<FeedStripToken> tokens;

  /// Index of the token on the board; -1 when none is (the fork position of
  /// the viewer's own line).
  final int current;
  final ValueChanged<int> onTokenTap;
  final double height;
  final Widget? leading;
  final List<Widget> trailing;

  /// A finger is scrubbing the game: the line jumps with the current move
  /// instead of gliding. A glide restarted at every move a finger crosses
  /// never catches up, so the line would sit still until the finger did.
  final bool follow;

  @override
  State<FeedMoveStrip> createState() => _FeedMoveStripState();
}

class _FeedMoveStripState extends State<FeedMoveStrip> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _currentKey = GlobalKey();
  bool _revealQueued = false;

  static final Curve _settle = const CupertinoMotion.smooth().toCurve;

  @override
  void initState() {
    super.initState();
    _queueReveal(animate: false);
  }

  @override
  void didUpdateWidget(covariant FeedMoveStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current ||
        oldWidget.tokens.length != widget.tokens.length) {
      _queueReveal(animate: true);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Centres the current move once it has laid out.
  void _queueReveal({required bool animate}) {
    if (_revealQueued) return;
    _revealQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _revealQueued = false;
      if (!mounted) return;
      final target = _currentKey.currentContext;
      if (target == null) {
        if (widget.current < 0 && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.minScrollExtent);
        }
        return;
      }
      final box = target.findRenderObject();
      if (box is! RenderBox || !box.attached || !_scroll.hasClients) return;
      // Only this line scrolls: [Scrollable.ensureVisible] would also drag
      // the feed's own vertical PageView to centre the token.
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return;
      final position = _scroll.position;
      final offset = viewport
          .getOffsetToReveal(box, 0.5)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((offset - position.pixels).abs() < 0.5) return;
      final still =
          !animate || widget.follow || MediaQuery.disableAnimationsOf(context);
      if (still) {
        _scroll.jumpTo(offset);
      } else {
        _scroll.animateTo(
          offset,
          duration: const Duration(milliseconds: 260),
          curve: _settle,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = colors.background;
    return SizedBox(
      height: widget.height,
      child: Row(
        children: [
          if (widget.leading != null) widget.leading!,
          Expanded(
            child: ShaderMask(
              // Moves soften into the edges instead of being sliced by them.
              shaderCallback: (rect) => LinearGradient(
                colors: [
                  bg.withValues(alpha: 0),
                  bg,
                  bg,
                  bg.withValues(alpha: 0),
                ],
                stops: const [0, 0.06, 0.94, 1],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                // Clear of the edge fade, so the move at rest is never
                // half-dissolved.
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    for (var i = 0; i < widget.tokens.length; i++)
                      _Token(
                        key: i == widget.current ? _currentKey : null,
                        token: widget.tokens[i],
                        isCurrent: i == widget.current,
                        height: widget.height,
                        onTap: () => widget.onTokenTap(i),
                      ),
                  ],
                ),
              ),
            ),
          ),
          ...widget.trailing,
        ],
      ),
    );
  }
}

class _Token extends StatelessWidget {
  const _Token({
    required this.token,
    required this.isCurrent,
    required this.height,
    required this.onTap,
    super.key,
  });

  final FeedStripToken token;
  final bool isCurrent;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final moveClass = token.moveClass;
    final suffix = moveClass == null ? null : feedClassSuffix(moveClass);
    // The move on the board wears its full badge; the rest just their glyph.
    final showMark =
        isCurrent && moveClass != null && feedAnnotationType(moveClass) != null;
    final sanStyle = AppTypography.textSmBold.copyWith(
      fontSize: 15,
      height: 20 / 15,
      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
      color: isCurrent ? colors.textPrimary : colors.textPrimaryMuted,
      fontFeatures: _tabular,
    );

    return Semantics(
      button: true,
      selected: isCurrent,
      label: [
        if (token.number != null) token.number!,
        token.san,
        if (moveClass != null) feedClassLabel(moveClass),
      ].join(' '),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (token.number != null) ...[
                  Text(
                    token.number!,
                    maxLines: 1,
                    style: sanStyle.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 3),
                ],
                Text(token.san, maxLines: 1, style: sanStyle),
                if (showMark) ...[
                  const SizedBox(width: 5),
                  FeedClassMark(moveClass: moveClass, size: 16),
                ] else if (suffix != null)
                  Text(
                    suffix,
                    maxLines: 1,
                    style: sanStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      color: feedClassTextColorFor(context, moveClass!),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 44pt transport control in the strip (step back, play/pause, step
/// forward). Dims when there is nowhere to go; presses read as a dim, never
/// a jump.
class FeedStepButton extends StatefulWidget {
  const FeedStepButton({
    required this.glyph,
    required this.semanticsLabel,
    required this.onTap,
    this.size = 44,
    super.key,
  });

  final String glyph;
  final String semanticsLabel;

  /// Null disables the control.
  final VoidCallback? onTap;
  final double size;

  @override
  State<FeedStepButton> createState() => _FeedStepButtonState();
}

class _FeedStepButtonState extends State<FeedStepButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final ink = context.colors.textPrimary;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        child: SizedBox.square(
          dimension: widget.size,
          child: Center(
            child: FeedGlyph(
              widget.glyph,
              width: 20,
              height: 20,
              color: ink.withValues(
                alpha: !enabled ? 0.28 : (_pressed ? 0.5 : 0.92),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Back to game": leaves the viewer's own line for the game where it was.
/// A plain, solid control, never a pill. Its press is [FeedPressable]'s, the
/// one every Feed button shares: it gives a little and dims, on a spring.
class FeedBackToGameButton extends StatelessWidget {
  const FeedBackToGameButton({
    required this.onTap,
    required this.height,
    super.key,
  });

  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FeedPressable(
      key: const ValueKey('feed_back_to_game'),
      semanticsLabel: 'Back to game',
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Center(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.textPrimary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Back to game',
              maxLines: 1,
              style: AppTypography.textSmBold.copyWith(
                fontSize: 13,
                height: 1.2,
                color: colors.background,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
