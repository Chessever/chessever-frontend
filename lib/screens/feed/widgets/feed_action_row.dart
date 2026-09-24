import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Analyze · My Space · Share · Like under the board, Like on the far right
/// where the thumb rests.
class FeedActionRow extends StatelessWidget {
  const FeedActionRow({
    required this.height,
    required this.liked,
    required this.inSpace,
    required this.likeIconKey,
    required this.onLike,
    required this.onSpace,
    required this.onShare,
    required this.onAnalyze,
    super.key,
  });

  final double height;
  final bool liked;

  /// Null when this game cannot be saved to My Space; the button is dropped.
  final bool? inSpace;

  /// Landing spot for the heart that flies in after a double-tap like.
  final GlobalKey likeIconKey;
  final VoidCallback onLike;
  final VoidCallback onSpace;
  final VoidCallback onShare;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = colors.textPrimary;
    final space = inSpace;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: FeedPressable(
              key: const ValueKey('feed_analyze_button'),
              semanticsLabel: 'Analyze',
              semanticsHint: 'Open game on the board',
              onTap: onAnalyze,
              child: _Action(
                label: 'Analyze',
                icon: FeedGlyph(
                  FeedGlyphs.analyze,
                  width: 22,
                  height: 22,
                  color: ink,
                ),
              ),
            ),
          ),
          if (space != null)
            Expanded(
              child: FeedPressable(
                key: const ValueKey('feed_space_button'),
                semanticsLabel: 'My Space',
                semanticsHint: space
                    ? 'Remove from My Space'
                    : 'Add to My Space',
                selected: space,
                onTap: onSpace,
                child: _Action(
                  label: 'My Space',
                  icon: FeedGlyph(
                    space ? FeedGlyphs.mySpaceAdded : FeedGlyphs.mySpaceAdd,
                    width: 22,
                    height: 22,
                    color: ink,
                  ),
                ),
              ),
            ),
          Expanded(
            child: FeedPressable(
              key: const ValueKey('feed_share_button'),
              semanticsLabel: 'Share',
              onTap: onShare,
              child: _Action(
                label: 'Share',
                icon: FeedGlyph(
                  FeedGlyphs.share,
                  width: 22,
                  height: 22,
                  color: ink,
                ),
              ),
            ),
          ),
          Expanded(
            child: FeedPressable(
              key: const ValueKey('feed_like_button'),
              semanticsLabel: liked ? 'Liked' : 'Like',
              selected: liked,
              onTap: onLike,
              child: _Action(
                label: liked ? 'Liked' : 'Like',
                icon: FeedGlyph(
                  key: likeIconKey,
                  liked ? FeedGlyphs.heartFilled : FeedGlyphs.heartOutline,
                  width: 24,
                  height: 22,
                  color: liked ? colors.danger : ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.icon});

  final String label;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: 22, child: Center(child: icon)),
        const SizedBox(height: 5),
        // Never cut, never touching a neighbour: the label keeps 4pt clear
        // each side and shrinks before it would.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: AppTypography.textXsMedium.copyWith(
                fontSize: 12,
                height: 14 / 12,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A Feed control's press: it gives a little under the finger (0.97) on a
/// snappy spring and dims a step, and lets go the same way; interruptible,
/// so a quick tap never waits for the press to finish. With reduced motion it
/// only dims.
///
/// Its semantics node carries the tap itself, so TalkBack, Switch Access and
/// Voice Access can activate it. Keep [semanticsLabel] the visible word (Voice
/// Control users say what they see) and put any explanation in
/// [semanticsHint].
class FeedPressable extends StatefulWidget {
  const FeedPressable({
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
    this.semanticsHint,
    this.selected,
    this.inMutuallyExclusiveGroup,
    this.expanded,
    this.enabled = true,
    super.key,
  });

  final String semanticsLabel;

  /// What the tap does, read after the label, when the word alone doesn't say.
  final String? semanticsHint;

  /// On/off state of a toggle action (Like, My Space); null for plain ones.
  final bool? selected;

  /// True for one choice among several (a preset list), so [selected] reads
  /// as the pick of a group rather than a toggle.
  final bool? inMutuallyExclusiveGroup;

  /// Open or shut, for a control that shows more below it; null otherwise.
  final bool? expanded;
  final VoidCallback? onTap;
  final bool enabled;
  final Widget child;

  @override
  State<FeedPressable> createState() => _FeedPressableState();
}

class _FeedPressableState extends State<FeedPressable> {
  bool _pressed = false;

  bool get _enabled => widget.enabled && widget.onTap != null;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pressed = _pressed && _enabled;
    return Semantics(
      button: true,
      enabled: _enabled,
      selected: widget.selected,
      inMutuallyExclusiveGroup: widget.inMutuallyExclusiveGroup,
      expanded: widget.expanded,
      label: widget.semanticsLabel,
      hint: widget.semanticsHint,
      // excludeSemantics drops the GestureDetector's own tap action, so the
      // node has to carry it.
      onTap: _enabled ? widget.onTap : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => _setPressed(true) : null,
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: _enabled ? widget.onTap : null,
        child: reduceMotion
            ? Opacity(opacity: pressed ? 0.7 : 1, child: widget.child)
            : SingleMotionBuilder(
                value: pressed ? 1.0 : 0.0,
                motion: const CupertinoMotion.snappy(),
                child: widget.child,
                builder: (context, t, child) {
                  final p = t.clamp(0.0, 1.0);
                  return Opacity(
                    opacity: 1 - 0.2 * p,
                    child: Transform.scale(scale: 1 - 0.03 * p, child: child),
                  );
                },
              ),
      ),
    );
  }
}
