import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chessever2/screens/feed/widgets/feed_deck.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// From this many likes the Like button shows the count instead of "Like".
const int kFeedLikeCountFloor = 3;

/// A count as the Feed shows it: whole, in at most five characters, so it
/// always fits under its mark. "999", "1.2K", "12.3K", "123K", "1.2M",
/// "12M", "123M", "1.2B". Rounded down, so it never claims what has not
/// happened yet (999,999 is "999K", never "1000K"), with ".0" dropped
/// ("12K").
String feedCompactCount(int count) {
  if (count < 1000) return '${math.max(0, count)}';
  String tenths(int unit, String suffix) {
    final t = count * 10 ~/ unit;
    final rest = t % 10;
    return rest == 0 ? '${t ~/ 10}$suffix' : '${t ~/ 10}.$rest$suffix';
  }

  if (count < 100000) return tenths(1000, 'K');
  if (count < 1000000) return '${count ~/ 1000}K';
  if (count < 10000000) return tenths(1000000, 'M');
  if (count < 1000000000) return '${count ~/ 1000000}M';
  if (count < 10000000000) return tenths(1000000000, 'B');
  return '${count ~/ 1000000000}B';
}

/// The Like button's word: the like count from [kFeedLikeCountFloor] up
/// ("12", "1.2K"), otherwise "Like". The heart's fill says whether the
/// viewer is among them.
String feedLikeLabel(int likes) =>
    likes >= kFeedLikeCountFloor ? feedCompactCount(likes) : 'Like';

/// The number under the rail's heart: the like count from
/// [kFeedLikeCountFloor] up ("12", "1.2K", "12.3K"), otherwise nothing (the
/// heart alone is the button). A screen reader hears the exact count
/// ([feedLikeSemantics]).
String? feedLikeCount(int likes) =>
    likes >= kFeedLikeCountFloor ? feedCompactCount(likes) : null;

/// What a screen reader hears on the Like button.
String feedLikeSemantics({required bool liked, required int likes}) {
  final state = liked ? 'Liked' : 'Like';
  return likes >= kFeedLikeCountFloor ? '$state, $likes likes' : state;
}

/// The Save button's word: "Saved" once the game is in one of the viewer's
/// databases.
String feedSaveLabel({required bool saved}) => saved ? 'Saved' : 'Save';

/// Analyze, Share, Save and Like down the right end of a post's chart: one
/// column of bare 24pt glyphs on a frosted backing ([FeedRailGlass]) while
/// the chart is under them, Like at the foot where the thumb rests and Save
/// over it, as on the board screen.
///
/// The cells stand at the foot of the rail's room ([FeedLayout.railTop] is
/// laid out for four, the zone's height): a post that cannot be saved or
/// liked drops that cell and the rest keep their order down to the foot, so
/// Like is always the last. The backing hugs the cells there are. My Space
/// lives in the post's long-press menu, not here.
class FeedActionRail extends StatelessWidget {
  const FeedActionRail({
    required this.cellHeight,
    required this.liked,
    this.likes = 0,
    this.shownLiked,
    this.shownLikes,
    this.heartPop = 0,
    this.saved = false,
    this.backing = true,
    required this.likeIconKey,
    this.onLike,
    required this.onShare,
    this.onSave,
    required this.onAnalyze,
    super.key,
  });

  /// Whether the frosted backing stands behind the marks: while the chart
  /// is under the rail. Off while the viewer's own line stands in the
  /// chart's place beside it ([FeedRailColumn.backing]).
  final bool backing;

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
    final likeCount = feedLikeCount(shownLikes ?? likes);
    final saveLabel = feedSaveLabel(saved: saved);

    Widget cell({
      required Key key,
      required Widget icon,
      required VoidCallback onTap,
      required String semanticsLabel,
      String? semanticsHint,
      bool? selected,
      Key? cellKey,
      String? count,
      bool haptic = true,
    }) => SizedBox(
      key: cellKey,
      height: cellHeight,
      width: FeedLayout.railWidth,
      child: FeedPressable(
        key: key,
        semanticsLabel: semanticsLabel,
        semanticsHint: semanticsHint,
        selected: selected,
        springPress: true,
        pressHaptic: haptic,
        onTap: onTap,
        child: FeedRailMark(icon: icon, count: count),
      ),
    );

    FeedGlyph glyph(String asset) => FeedGlyph(
      asset,
      width: FeedLayout.railGlyph,
      height: FeedLayout.railGlyph,
      color: ink,
    );

    return FeedRailColumn(
      backing: backing,
      children: [
        cell(
          key: const ValueKey('feed_analyze_button'),
          semanticsLabel: 'Analyze',
          semanticsHint: 'Open game on the board',
          onTap: onAnalyze,
          icon: glyph(FeedGlyphs.analyze),
        ),
        cell(
          key: const ValueKey('feed_share_button'),
          semanticsLabel: 'Share',
          onTap: onShare,
          icon: glyph(FeedGlyphs.share),
        ),
        if (save != null)
          cell(
            key: const ValueKey('feed_save_button'),
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
            count: likeCount,
            // The heart's landing has its own haptic.
            haptic: false,
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

/// A rail's cells stacked to the foot of its room, over the backing's
/// insets ([FeedLayout.railInsetTop], [FeedLayout.railInsetBottom]), so the
/// game and puzzle posts' rails and the skeleton's put every mark in the
/// same place and read as one object.
///
/// The frosted backing ([FeedRailGlass]) stands behind the cells only when
/// [backing] is on: over a chart, where the marks need it to read over the
/// curve. Over the page's own ground (a puzzle, the skeleton) the marks
/// stand bare, since a frosted plate with nothing behind it to frost is
/// only a grey pill.
class FeedRailColumn extends StatelessWidget {
  const FeedRailColumn({
    required this.children,
    this.backing = true,
    super.key,
  });

  final List<Widget> children;

  /// Whether the frosted backing stands behind the cells. When it changes
  /// (a game post's chart giving way to the viewer's line and coming back)
  /// it fades on a spring; the cells never move or rebuild.
  final bool backing;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: FeedRailGlass(
        shown: backing,
        child: Padding(
          padding: const EdgeInsets.only(
            top: FeedLayout.railInsetTop,
            bottom: FeedLayout.railInsetBottom,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// The rail's backing: a small vertical plate of the app's glass
/// ([GlassStyle]), cut to the rail's width with round ends, standing over
/// the chart's right end.
///
/// The chart shows through it, blurred, behind a plate tinted from the deck
/// it stands on, so the marks and the like count read over the curve while
/// the curve is still felt under them. The edge is the plate's own lit rim,
/// a hair brighter at the top; there is no shadow and no outline, so it
/// reads as a pane on the chart rather than a box beside it. The blur is
/// clipped to the plate and never reaches past it.
///
/// With [shown] off there is no plate: blur, tint and rim fade out together
/// on one spring (so nothing pops), and once gone the child is painted with
/// no backdrop layer and no clip at all. The tree under it never changes,
/// so the cells keep their state.
class FeedRailGlass extends StatelessWidget {
  const FeedRailGlass({required this.child, this.shown = true, super.key});

  final Widget child;

  /// Whether the plate stands behind [child].
  final bool shown;

  /// Below this the plate is gone: a spring settling on 0 leaves dust, and
  /// dust must not keep a backdrop layer alive.
  static const double _gone = 0.001;

  /// Round ends: the rail is one target wide.
  static const double radius = FeedLayout.railWidth / 2;

  /// Light enough that the curve under the plate still reads as a line.
  static const double blurSigma = 4;

  /// How much of the plate covers the blurred chart: enough that the marks
  /// read over the curve, little enough that the curve is still seen under
  /// them. Paper takes a little more, so the frost reads as white.
  static const double plateAlphaDark = 0.42;
  static const double plateAlphaLight = 0.5;

  /// Where on the deck the rail stands, as [FeedBottomDeck.toneAt] takes
  /// it: the chart's own ground.
  static const double deckDepth = 0.45;

  /// The plate's colour over [context]'s deck: the deck's tone, lifted a
  /// step toward the light (a little ink in dark, white on paper), at
  /// partial strength.
  static Color plateOf(BuildContext context) {
    final deck = FeedBottomDeck.toneAt(context, deckDepth);
    if (context.isLightTheme) {
      return Color.lerp(
        deck,
        const Color(0xFFFFFFFF),
        0.55,
      )!.withValues(alpha: plateAlphaLight);
    }
    return Color.lerp(
      deck,
      context.colors.textPrimary,
      0.1,
    )!.withValues(alpha: plateAlphaDark);
  }

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      value: shown ? 1.0 : 0.0,
      motion: const CupertinoMotion.smooth(),
      // With reduced motion the plate simply comes or goes; one tree either
      // way, so the setting changing never rebuilds the cells.
      active: !MediaQuery.disableAnimationsOf(context),
      child: child,
      builder: (context, t, child) =>
          _plate(context, t.clamp(0.0, 1.0), child!),
    );
  }

  /// The plate at [presence] (1 whole, 0 gone) behind [child]. One tree at
  /// every presence: only the paint changes.
  Widget _plate(BuildContext context, double presence, Widget child) {
    final style = GlassStyle.of(context);
    final plate = plateOf(context);
    final on = presence > _gone;
    return CustomPaint(
      key: const ValueKey('feed_rail_glass'),
      foregroundPainter: _RailRimPainter(
        top: style.rimTop,
        bottom: style.rimBottom,
        presence: on ? presence : 0,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: on ? Clip.antiAlias : Clip.none,
        child: BackdropFilter(
          enabled: on,
          filter: ui.ImageFilter.blur(
            sigmaX: blurSigma * presence,
            sigmaY: blurSigma * presence,
          ),
          child: ColoredBox(
            color: on
                ? plate.withValues(alpha: plate.a * presence)
                : const Color(0x00000000),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _RailRimPainter extends CustomPainter {
  const _RailRimPainter({
    required this.top,
    required this.bottom,
    required this.presence,
  });

  final Color top;
  final Color bottom;

  /// How much of the plate stands: the rim fades with it.
  final double presence;

  @override
  void paint(Canvas canvas, Size size) {
    if (presence <= 0) return;
    paintGlassRim(
      canvas,
      BorderRadius.circular(FeedRailGlass.radius).toRRect(Offset.zero & size),
      top.withValues(alpha: top.a * presence),
      bottom.withValues(alpha: bottom.a * presence),
    );
  }

  @override
  bool shouldRepaint(_RailRimPainter old) =>
      old.top != top || old.bottom != bottom || old.presence != presence;
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

/// One cell of a Feed rail: the bare glyph, centred in its target, with an
/// optional count under it (the heart's likes). No word: the marks are the
/// buttons, as in the bottom bar, and each says its name to a screen reader.
///
/// The count is always whole: compact ([feedCompactCount]), in tabular
/// figures, at the one size [feedRailCountFontSize] gives every count, which
/// keeps the widest of them inside [FeedLayout.railCountRoom], clear of the
/// backing's round end, at any text size.
class FeedRailMark extends StatelessWidget {
  const FeedRailMark({required this.icon, this.count, super.key});

  final Widget icon;
  final String? count;

  /// The count's size before text scaling.
  static const double countSize = 11;

  /// The count grows with the viewer's text size up to here; the rail is a
  /// fixed 44pt wide, so it cannot grow without end.
  static const double countMaxScale = 1.15;

  /// Every shape [feedCompactCount] can take at its widest, in figures that
  /// are all one width: the count's size is fitted to the widest of these.
  static const List<String> widestCounts = [
    '88.8K',
    '888K',
    '8.8M',
    '888M',
    '8.8B',
    '888B',
  ];

  /// The count's type at [fontSize]: set as the Text under it draws it,
  /// over the inherited default style, so what is measured is what is
  /// drawn (an inherited tracking would otherwise widen it unseen).
  static TextStyle countStyle(BuildContext context, double fontSize) =>
      DefaultTextStyle.of(context).style.merge(
        AppTypography.textXsMedium.copyWith(
          fontSize: fontSize,
          height: 13 / 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: context.colors.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: FeedLayout.railGlyph,
            child: Center(child: icon),
          ),
          if (count != null) ...[
            const SizedBox(height: FeedLayout.railGlyphGap),
            Text(
              count,
              key: const ValueKey('feed_rail_count'),
              maxLines: 1,
              softWrap: false,
              // Already scaled: [feedRailCountFontSize] read the viewer's
              // text size.
              textScaler: TextScaler.noScaling,
              style: countStyle(context, feedRailCountFontSize(context)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The size every like count is set at: [FeedRailMark.countSize] grown
/// with the viewer's text size (up to [FeedRailMark.countMaxScale]), or
/// less where the widest count the rail can show
/// ([FeedRailMark.widestCounts]) would not fit [FeedLayout.railCountRoom] at
/// that size. Every count is set at it, so "128" and "12.3K" are one size
/// and none is ever cut.
double feedRailCountFontSize(BuildContext context) {
  final size = MediaQuery.textScalerOf(context)
      .clamp(maxScaleFactor: FeedRailMark.countMaxScale)
      .scale(FeedRailMark.countSize);
  final style = FeedRailMark.countStyle(context, size);
  final key = (style.fontFamily, style.letterSpacing, size);
  final widest = _widestCountAt[key] ??= () {
    var widest = 0.0;
    for (final text in FeedRailMark.widestCounts) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }();
  const room = FeedLayout.railCountRoom;
  if (widest <= room) return size;
  // A hair under, so the widest count sits inside its room, not on its edge.
  return size * room / widest * 0.99;
}

/// The widest count's width per family and size: measured once, as the
/// rail rebuilds on every move of the replay.
final Map<(String?, double?, double), double> _widestCountAt = {};

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
    this.springPress = false,
    this.pressHaptic = true,
    super.key,
  });

  /// With [springPress], the selection haptic on a tap; off for an action
  /// with a haptic of its own (Like's heart lands with one).
  final bool pressHaptic;

  /// The bottom bar's press: the mark dips to 0.86 under the finger and
  /// springs back with a little overshoot, with the selection haptic. For
  /// the rails' bare glyphs; text buttons keep the quiet dim.
  final bool springPress;

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
        onTap: _enabled
            ? (widget.springPress && widget.pressHaptic
                  ? () {
                      HapticFeedbackService.selection();
                      widget.onTap!();
                    }
                  : widget.onTap)
            : null,
        child: widget.springPress && _enabled
            ? PressSpring(pressedScale: 0.86, child: widget.child)
            : reduceMotion
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
