import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// From this many likes the Like button shows the count instead of "Like".
const int kFeedLikeCountFloor = 3;

/// The Like button's word: the like count from [kFeedLikeCountFloor] up
/// ("12", "1.2K"), otherwise "Like". The heart's fill says whether the
/// viewer is among them.
String feedLikeLabel(int likes) =>
    likes >= kFeedLikeCountFloor ? formatCompactCount(likes) : 'Like';

/// What a screen reader hears on the Like button.
String feedLikeSemantics({required bool liked, required int likes}) {
  final state = liked ? 'Liked' : 'Like';
  return likes >= kFeedLikeCountFloor ? '$state, $likes likes' : state;
}

/// The Save button's word: "Saved" once the game is in one of the viewer's
/// databases.
String feedSaveLabel({required bool saved}) => saved ? 'Saved' : 'Save';

/// Analyze, Share, Save and Like down the right of a post, beside its
/// chart: one column of cells, each a 24pt glyph over its word, Like at the
/// foot where the thumb rests and Save over it, as on the board screen.
///
/// The cells stand at the foot of the rail's room ([FeedLayout.railTop] is
/// laid out for four): a post that cannot be saved or liked drops that cell
/// and the rest keep their order down to the foot, so Like is always the
/// last. My Space lives in the post's long-press menu, not here.
class FeedActionRail extends StatelessWidget {
  const FeedActionRail({
    required this.cellHeight,
    required this.liked,
    this.likes = 0,
    this.shownLiked,
    this.shownLikes,
    this.heartPop = 0,
    this.saved = false,
    required this.likeIconKey,
    this.onLike,
    required this.onShare,
    this.onSave,
    required this.onAnalyze,
    super.key,
  });

  /// One cell's height ([FeedLayout.railCell]); its width is the rail's.
  final double cellHeight;

  /// Whether the viewer likes the game: what the button says to a screen
  /// reader and the state it toggles.
  final bool liked;

  /// How many people like the game, the viewer included; shown on the
  /// button from [kFeedLikeCountFloor] up, "Like" below that.
  final int likes;

  /// What the button draws, when it differs from [liked] / [likes] for a
  /// moment: a like's heart is still flying in, and the button fills when
  /// it lands.
  final bool? shownLiked;
  final int? shownLikes;

  /// Bumped when a heart lands on the button: the filled heart pops once.
  final int heartPop;

  /// The game is in one of the viewer's databases: Save shows its tick.
  final bool saved;

  /// Landing spot for the heart that flies in after a double-tap like.
  final GlobalKey likeIconKey;

  /// Null when the game cannot be liked; the cell is dropped.
  final VoidCallback? onLike;
  final VoidCallback onShare;

  /// Null when the game's moves stay where they are (licensed content the
  /// board does not export either); the cell is dropped.
  final VoidCallback? onSave;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = colors.textPrimary;
    final like = onLike;
    final save = onSave;
    final likeLabel = feedLikeLabel(shownLikes ?? likes);
    final saveLabel = feedSaveLabel(saved: saved);
    final fontSize = feedRailFontSize(
      context,
      labels: [
        'Analyze',
        'Share',
        if (save != null) saveLabel,
        if (like != null) likeLabel,
      ],
    );

    Widget cell({
      required Key key,
      required String label,
      required Widget icon,
      required VoidCallback onTap,
      required String semanticsLabel,
      String? semanticsHint,
      bool? selected,
      Key? cellKey,
    }) => SizedBox(
      key: cellKey,
      height: cellHeight,
      width: FeedLayout.railWidth,
      child: FeedPressable(
        key: key,
        semanticsLabel: semanticsLabel,
        semanticsHint: semanticsHint,
        selected: selected,
        onTap: onTap,
        child: FeedActionLabel(
          fontSize: fontSize,
          label: label,
          glyphExtent: FeedLayout.railGlyph,
          glyphGap: FeedLayout.railGlyphGap,
          icon: icon,
        ),
      ),
    );

    FeedGlyph glyph(String asset) => FeedGlyph(
      asset,
      width: FeedLayout.railGlyph,
      height: FeedLayout.railGlyph,
      color: ink,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        cell(
          key: const ValueKey('feed_analyze_button'),
          label: 'Analyze',
          semanticsLabel: 'Analyze',
          semanticsHint: 'Open game on the board',
          onTap: onAnalyze,
          icon: glyph(FeedGlyphs.analyze),
        ),
        cell(
          key: const ValueKey('feed_share_button'),
          label: 'Share',
          semanticsLabel: 'Share',
          onTap: onShare,
          icon: glyph(FeedGlyphs.share),
        ),
        if (save != null)
          cell(
            key: const ValueKey('feed_save_button'),
            label: saveLabel,
            semanticsLabel: saveLabel,
            semanticsHint: saved
                ? 'Choose the databases it is saved in'
                : 'Save to a database',
            selected: saved,
            onTap: save,
            // The tick says saved, in ink: the heart stays the rail's one
            // colour.
            icon: glyph(saved ? FeedGlyphs.saved : FeedGlyphs.save),
          ),
        if (like != null)
          cell(
            cellKey: const ValueKey('feed_like_action'),
            key: const ValueKey('feed_like_button'),
            label: likeLabel,
            semanticsLabel: feedLikeSemantics(liked: liked, likes: likes),
            selected: liked,
            onTap: like,
            icon: _LikeGlyph(
              glyphKey: likeIconKey,
              filled: shownLiked ?? liked,
              pop: heartPop,
              ink: ink,
              fill: colors.danger,
              scale: FeedLayout.railGlyph / 24,
            ),
          ),
      ],
    );
  }
}

/// The size every word of the rail is set at: [FeedActionLabel.restSize],
/// or less when the widest of [labels] would not fit a rail cell at the
/// viewer's text size. The words shrink together, never one alone.
double feedRailFontSize(BuildContext context, {required List<String> labels}) =>
    feedActionFontSize(
      context,
      rowWidth: FeedLayout.railWidth * labels.length,
      labels: labels,
    );

/// The Like button's heart. When a flying heart lands on it ([pop] moves
/// on) it gives under the landing and springs back past its size, the way
/// the board screen's badge takes its heart; with reduced motion it simply
/// fills.
class _LikeGlyph extends StatefulWidget {
  const _LikeGlyph({
    required this.glyphKey,
    required this.filled,
    required this.pop,
    required this.ink,
    required this.fill,
    this.scale = 1,
  });

  /// Of the row's 24 by 22 heart: the rail draws it a step larger.
  final double scale;

  /// The flight's target: the glyph's own box, never the scaled one.
  final GlobalKey glyphKey;
  final bool filled;
  final int pop;
  final Color ink;
  final Color fill;

  @override
  State<_LikeGlyph> createState() => _LikeGlyphState();
}

class _LikeGlyphState extends State<_LikeGlyph>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _scale = SingleMotionController(
    motion: const CupertinoMotion.bouncy(),
    vsync: this,
    initialValue: 1,
  );

  @override
  void didUpdateWidget(_LikeGlyph old) {
    super.didUpdateWidget(old);
    if (widget.pop != old.pop && !MediaQuery.disableAnimationsOf(context)) {
      // Pressed in by the landing heart, then back up past its size.
      _scale.value = 0.72;
      unawaited(_scale.animateTo(1));
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glyph = FeedGlyph(
      key: widget.glyphKey,
      widget.filled ? FeedGlyphs.heartFilled : FeedGlyphs.heartOutline,
      width: 24 * widget.scale,
      height: 22 * widget.scale,
      color: widget.filled ? widget.fill : widget.ink,
    );
    return AnimatedBuilder(
      animation: _scale,
      child: glyph,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
    );
  }
}

/// One Feed action: its glyph over its word. Shared by the game and puzzle
/// posts' rails so they read as one system.
class FeedActionLabel extends StatelessWidget {
  const FeedActionLabel({
    required this.label,
    required this.icon,
    this.fontSize = restSize,
    this.glyphExtent = 22,
    this.glyphGap = 5,
    super.key,
  });

  final String label;
  final Widget icon;

  /// The word's size before text scaling; see [feedActionFontSize].
  final double fontSize;

  /// The glyph's line, and the space between it and the word: 22 and 5 in
  /// a row, 24 and 4 in the rail ([FeedLayout.railGlyph]).
  final double glyphExtent;
  final double glyphGap;

  /// The words' size before text scaling, when they fit.
  static const double restSize = 12;

  /// Space reserved per side when sizing labels to their action cells.
  static const double gutter = 4;

  static TextStyle styleOf(BuildContext context, double fontSize) =>
      AppTypography.textXsMedium.copyWith(
        fontSize: fontSize,
        height: 14 / 12,
        color: context.colors.textPrimary,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: glyphExtent,
          child: Center(widthFactor: 1, child: icon),
        ),
        SizedBox(height: glyphGap),
        // Font sizing reserves space between neighbouring labels while
        // each icon and word stay centered in the same full tap target.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, style: styleOf(context, fontSize)),
        ),
      ],
    );
  }
}

/// The size every word of an action row is set at: [FeedActionLabel.
/// restSize], or less when the widest of [labels] would not fit its share
/// of [rowWidth] at the viewer's text size. The words then shrink together,
/// never one of them alone, so the row keeps one size.
double feedActionFontSize(
  BuildContext context, {
  required double rowWidth,
  required List<String> labels,
}) {
  const rest = FeedActionLabel.restSize;
  if (labels.isEmpty || !rowWidth.isFinite) return rest;
  final room = rowWidth / labels.length - 2 * FeedActionLabel.gutter;
  if (room <= 0) return rest;
  final scaler = MediaQuery.textScalerOf(context);
  final style = FeedActionLabel.styleOf(context, rest);
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  if (widest <= room) return rest;
  // A hair under, so the widest word sits inside its column rather than on
  // its edge.
  return rest * room / widest * 0.99;
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
