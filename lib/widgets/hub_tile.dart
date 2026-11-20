import 'dart:math' as math;

import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/discovery_dot.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// What a hub tile says under its title unless it says something else.
const String kHubTileCaption = 'Tap to view';

/// Opaque ink the hub tiles are printed on.
///
/// These tiles are a **media surface**, not a page surface: artwork (the
/// photo mosaic, the country flag, a pixel object) under a dark ramp with
/// white type on top. That composition only works over a dark base, so the
/// base, and every ink inside the tile, is pinned here rather than resolved
/// from [AppColors]. Same value as the dark scaffold, so dark mode reads as
/// one surface.
const Color kHubTileInk = Color(0xFF0C0C0E);

/// On-media ink. White-based because it always sits on [kHubTileInk] or on
/// darkened artwork.
const Color kHubTileOnMedia = Color(0xFFFFFFFF);

/// Ink drawn ON a tile's artwork: white on the dark media tile, the page's
/// own ink on the light paper tile.
Color hubTileOnTile(BuildContext context) =>
    context.isLightTheme ? context.colors.textPrimary : kHubTileOnMedia;

/// Tile artwork that brings its own light drawing (a pale ground, its subject
/// in deep tones, the label's corner kept clear), so on the light tile it is
/// shown as drawn: no paper veil is laid over it. Artwork without its own
/// light drawing (a photo mosaic, a flag) keeps the veil.
abstract interface class HubPaperArtwork {}

/// Side gutter of the hub pages (My Space, Discovery): the design's 16 on
/// phones, and on tablets the For You header's own inset (its search field
/// and segments sit at 32.sp), so tiles, titles and cards start on the
/// header's left edge.
double get hubGutter => ResponsiveHelper.adaptive(phone: 16.sp, tablet: 32.sp);

/// The tile Today opens with (Favorites, Countrymen), as a building block:
/// a 108-tall card with the title and "Tap to view" in its bottom-left
/// corner. My Space and Discovery open with the same pair.
///
/// Its picture is either [artwork], filling the card behind the label (the
/// photo mosaic, the flag), or a [mark], an object set in a square slot of
/// its own on the right with a fixed gap to the label, so the two never
/// touch however long the title or caption is.
class HubTile extends StatelessWidget {
  const HubTile({
    super.key,
    required this.title,
    this.artwork,
    this.mark,
    required this.onTap,
    this.caption = kHubTileCaption,
    this.titleIcon,
    this.ramp = true,
    this.onLongPressStart,
    this.dotId,
  }) : assert(
         (artwork == null) != (mark == null),
         'A hub tile has either full-bleed artwork or a mark.',
       );

  final String title;

  /// The quiet line under the title, led into its arrow.
  final String caption;

  /// A glyph set before the title at its size ("+" on a tile that adds).
  final IconData? titleIcon;

  /// Fills the tile behind the label.
  final Widget? artwork;

  /// Sits beside the label in its own square slot.
  final Widget? mark;
  final VoidCallback onTap;

  /// Grades the artwork down to the tile's ink under the label. Artwork that
  /// already keeps clear of the label, or a tile with no artwork, goes without.
  final bool ramp;

  /// Long-press, for tiles that lift into the focus menu.
  final GestureLongPressStartCallback? onLongPressStart;

  /// Discovery-dot anchor id, so the admin console can point at this tile.
  final String? dotId;

  @override
  Widget build(BuildContext context) {
    final tile = HubTilePress(
      onTap: onTap,
      child: HubTileFace(
        title: title,
        artwork: artwork,
        mark: mark,
        ramp: ramp,
        caption: caption,
        titleIcon: titleIcon,
      ),
    );
    final longPress = onLongPressStart;
    // The caption is part of what the tile says ("My Likes, 128 games"), so
    // a screen reader hears the same line a sighted viewer reads.
    final semantic = Semantics(
      button: true,
      label: '$title, $caption',
      excludeSemantics: true,
      onTap: onTap,
      child: dotId == null
          ? tile
          : DiscoveryDotAnchor(
              id: dotId,
              offset: const Offset(-12, 12),
              // The tile opens a page, so a bubble would point at nothing.
              message: DiscoveryDotMessage.snack,
              child: tile,
            ),
    );
    if (longPress == null) return semantic;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onLongPressStart: longPress,
      child: semantic,
    );
  }
}

/// Two [HubTile]s side by side, as Today sets Favorites and Countrymen.
class HubTileRow extends StatelessWidget {
  const HubTileRow({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 20.sp),
      child: Row(
        children: [
          Expanded(child: left),
          SizedBox(width: 12.sp),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// The tile itself: base ink, artwork, the readability ramp and the label.
/// Light: a paper card on the page; artwork with its own light drawing
/// ([HubPaperArtwork]) is shown as drawn, any other is washed into paper at
/// the label. Dark: the media tile.
class HubTileFace extends StatelessWidget {
  const HubTileFace({
    super.key,
    required this.title,
    this.artwork,
    this.mark,
    this.ramp = true,
    this.caption = kHubTileCaption,
    this.titleIcon,
  }) : assert(
         (artwork == null) != (mark == null),
         'A hub tile has either full-bleed artwork or a mark.',
       );

  final String title;
  final Widget? artwork;
  final Widget? mark;
  final bool ramp;
  final String caption;
  final IconData? titleIcon;

  /// Between the title and the mark beside it.
  static double get markGap => 12.sp;

  /// The mark's square, the same on every tile so a pair always matches.
  static double get markSide => 44.sp;

  /// The label's inset from the tile's edges.
  static double get labelInset => 14.sp;

  /// The title's type, its ink aside.
  static TextStyle titleType() =>
      AppTypography.textMdBold.copyWith(fontSize: 16.f, letterSpacing: 0.3);

  /// The caption's type, its ink aside.
  static TextStyle captionType() =>
      AppTypography.textXsRegular.copyWith(fontSize: 12.f);

  /// [text] set on one line in [style] at the reader's text size: its width
  /// and its height rounded up, as the tile measures its label.
  static Size _line(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final size = Size(painter.width, painter.height.ceilToDouble());
    painter.dispose();
    return size;
  }

  /// How far from the tile's left edge a tile's label ([title] over
  /// [caption] and its arrow) reaches, at the reader's text size: artwork
  /// that stands beside the label keeps to the right of it.
  static double labelRight(
    BuildContext context, {
    required String title,
    String caption = kHubTileCaption,
  }) {
    final arrow = MediaQuery.textScalerOf(
      context,
    ).scale((12.f * 0.8).roundToDouble());
    final captionWidth =
        _line(context, caption, captionType()).width + 4.w + arrow;
    return labelInset +
        math.max(_line(context, title, titleType()).width, captionWidth);
  }

  /// Where a text-only tile's label ([title] over [caption]) begins, from
  /// the top of an artwork box [height] tall, at the reader's text size:
  /// artwork above the label keeps clear of it.
  static double labelTop(
    BuildContext context, {
    required String title,
    String caption = kHubTileCaption,
    required double height,
  }) {
    final label =
        _line(context, title, titleType()).height +
        2.sp +
        _line(context, caption, captionType()).height;
    return height - labelInset - label;
  }

  /// Inter's cap height, as a share of its size (1490 of 2048 units).
  static const double _capHeight = 1490 / 2048;

  /// Where the top of the title's capitals sits, from the top of an artwork
  /// box [height] tall, at the reader's text size: artwork composed above
  /// the label ends a little above it, so the label sits on calm ground.
  static double labelCapTop(
    BuildContext context, {
    required String title,
    String caption = kHubTileCaption,
    required double height,
  }) {
    // As the title's Text lays it out: over the ambient text style, whose
    // leading distribution decides where the baseline falls in the line.
    final style = DefaultTextStyle.of(context).style.merge(titleType());
    final scaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(text: title, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.dispose();
    final top = labelTop(
      context,
      title: title,
      caption: caption,
      height: height,
    );
    return top + baseline - scaler.scale(style.fontSize ?? 16) * _capHeight;
  }

  @override
  Widget build(BuildContext context) {
    final isLight = context.isLightTheme;
    // Light artwork drawn for paper already keeps the label's corner clear
    // on a ground of the tile's own tone, so it is shown as drawn.
    final paperArt = isLight && artwork is HubPaperArtwork;
    final onTile = hubTileOnTile(context);
    // On paper the tile sits a half step above the page, not on the cards'
    // bright white: a full-white slab (and a ramp fading into it) glares
    // next to the page's own tone.
    final base = isLight
        ? Color.lerp(context.colors.background, context.colors.surface, 0.45)!
        : kHubTileInk;
    final quiet = isLight
        ? context.colors.textSecondary
        : kHubTileOnMedia.withValues(alpha: 0.85);
    // On paper the type needs no help; on the media tile a pale photo can
    // land right under the label, so the type carries its own contrast. A
    // mark never sits under the type, so its label needs no shadow either.
    final shadowed = !isLight && mark == null && ramp;
    List<Shadow>? shadow(double alpha, double blur, [Offset? offset]) =>
        shadowed
        ? [
            Shadow(
              color: Colors.black.withValues(alpha: alpha),
              blurRadius: blur,
              offset: offset ?? Offset.zero,
            ),
          ]
        : null;

    // Sized on the type scale here, at build, so the tile's words grow with
    // the tile on a tablet exactly as the section titles beside it do.
    final titleStyle = titleType().copyWith(
      color: onTile,
      shadows: shadow(0.45, 4, const Offset(0, 1)),
    );
    final captionSize = 12.f;
    final captionStyle = captionType().copyWith(
      color: quiet,
      shadows: shadow(0.4, 3),
    );
    final scaler = MediaQuery.textScalerOf(context);
    double measuredHeight(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final height = painter.height.ceilToDouble();
      painter.dispose();
      return height;
    }

    final titleHeight = math.max(
      measuredHeight(title, titleStyle),
      mark != null ? markSide : (titleIcon != null ? 18.sp : 0.0),
    );
    final captionHeight = measuredHeight(caption, captionStyle);
    // Grow both one-line tiles by the same type metrics at accessibility
    // sizes. Keep the text clear of the padding and the two border pixels.
    final height = math.max(
      108.sp,
      (30.sp + titleHeight + captionHeight + 2).ceilToDouble(),
    );

    final titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (titleIcon != null) ...[
          Icon(
            titleIcon,
            size: 18.sp,
            color: onTile,
            shadows: shadow(0.45, 4, const Offset(0, 1)),
          ),
          SizedBox(width: 4.w),
        ],
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
      ],
    );
    // Keep the original one-line slot and baseline. Scale the whole caption
    // row down only when needed, so every word and its arrow remain visible.
    final captionRow = SizedBox(
      height: captionHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                caption,
                style: captionStyle,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
              SizedBox(width: 4.w),
              SpaceGlyph(
                SpaceGlyphKind.arrowUpRight,
                size: (captionSize * 0.8).roundToDouble(),
                ink: Color.alphaBlend(quiet, isLight ? base : Colors.black),
              ),
            ],
          ),
        ),
      ),
    );

    final markWidget = mark;
    final body = markWidget == null
        ? Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(child: artwork!),
              // One ramp in both themes: it grades the tile's own artwork
              // down to its own ink, and never touches the page behind it.
              // Paper artwork gets no veil across it, only a faint breath
              // of the tile's own tone in the label's corner.
              if (ramp)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: paperArt
                          ? LinearGradient(
                              begin: Alignment.bottomLeft,
                              end: Alignment.topRight,
                              colors: [
                                base.withValues(alpha: 0.5),
                                base.withValues(alpha: 0),
                              ],
                              stops: const [0.0, 0.45],
                            )
                          : LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              // Paper: the veil fades into the tile's own
                              // page-toned paper, never bright white, so the
                              // words get a calm backing without a white glow.
                              colors: isLight
                                  ? [
                                      base.withValues(alpha: 0),
                                      base.withValues(alpha: 0.74),
                                      base.withValues(alpha: 0.92),
                                    ]
                                  : [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.6),
                                      Colors.black.withValues(alpha: 0.95),
                                    ],
                              stops: isLight
                                  ? const [0.2, 0.6, 1.0]
                                  : const [0.0, 0.5, 1.0],
                            ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(14.sp),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    titleRow,
                    SizedBox(height: 2.sp),
                    captionRow,
                  ],
                ),
              ),
            ],
          )
        : Padding(
            padding: EdgeInsets.all(14.sp),
            // The mark stands beside the title, bottom-aligned with it, and
            // the caption runs the tile's full width under both: the longer
            // line never shares its row with the mark, and the title gives
            // way (truncating) before it could reach the mark.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: titleRow,
                      ),
                    ),
                    SizedBox(width: markGap),
                    SizedBox.square(dimension: markSide, child: markWidget),
                  ],
                ),
                SizedBox(height: 2.sp),
                captionRow,
              ],
            ),
          );

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(14.br),
        // The edge is the only part of the tile that meets the page. On dark
        // the page and the tile share an ink, so a divider-toned lip
        // separates them; on light the paper tile sits one tonal step above
        // the page and a faint self-coloured ink lip draws its edge.
        border: Border.all(
          color: isLight
              ? context.colors.textPrimary.withValues(alpha: 0.08)
              : context.colors.divider,
          width: 1,
        ),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(14.br), child: body),
    );
  }
}

/// One of My Space's pixel objects (the heart, the bookmarked board...) as a
/// hub tile's [HubTile.mark]: fitted and centred in the square slot the tile
/// gives it, drawn for the theme's paper or black.
class HubPixelArtwork extends StatelessWidget {
  const HubPixelArtwork({super.key, required this.section});

  /// Whose door art to draw.
  final SpaceSection section;

  @override
  Widget build(BuildContext context) {
    final tone = PixelTone.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
        return PixelArtView(
          scene: PixelScene.mark(PixelArt.door(section, tone: tone), size),
        );
      },
    );
  }
}

/// The My Likes heart as a card's mark: the animated pixel heart in a
/// [size] square, for the My Likes card wherever it is drawn (the Library
/// list, a My Space tile), so the destination wears one heart everywhere.
///
/// [PixelScene.mark] keeps [headroom] clear above the heart for
/// the hearts that drift off it, which would sit the heart itself that much
/// low in the slot. The mark is lifted by half of it, so the heart's body is
/// what centres on the slot and the drifting hearts rise past its top edge.
class LikesHeartMark extends StatelessWidget {
  const LikesHeartMark({super.key, required this.size});

  /// The room [PixelScene.mark] leaves above an art with embers.
  static const double headroom = 10;

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Transform.translate(
        offset: const Offset(0, -headroom / 2),
        child: SizedBox.square(
          dimension: size,
          child: const HubPixelArtwork(section: SpaceSection.likes),
        ),
      ),
    );
  }
}

/// [LikesHeartMark] at a title's glyph size, for the head of the My Likes
/// page: the same heart, smaller.
///
/// The pixel grid wants whole blocks a few pixels wide, which a glyph-sized
/// slot cannot give it (the blocks would be thinner than their own gaps). So
/// the mark is laid out at the size the Library card draws it and scaled
/// down into the [size] square, blocks, pulse and all.
class LikesHeartGlyph extends StatelessWidget {
  const LikesHeartGlyph({super.key, required this.size});

  /// The slot the mark is laid out in before it is scaled: the Library
  /// card's own, where the heart's blocks are five pixels wide.
  static const double _drawn = 64;

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const FittedBox(child: LikesHeartMark(size: _drawn)),
    );
  }
}

/// Press feedback for a hub tile: it settles to [pressedScale] under the
/// finger on a spring and springs back on release, so the tap is felt before
/// the route pushes. The same depth as every other My Space card's press
/// (`TappableScale`'s 0.96). No scale under reduced motion.
class HubTilePress extends StatefulWidget {
  const HubTilePress({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  /// How far a held tile settles.
  static const double pressedScale = 0.96;

  @override
  State<HubTilePress> createState() => _HubTilePressState();
}

class _HubTilePressState extends State<HubTilePress> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _pressed && !reduce ? HubTilePress.pressedScale : 1.0,
        builder: (context, value, child) {
          // A spring only asymptotes to 1; settle on exact identity so the
          // artwork is never resampled a hair soft at rest.
          final scale = (value - 1).abs() < 0.001 ? 1.0 : value;
          return Transform.scale(scale: scale, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

/// A section title on the hub pages (My Space, Discovery): one line, the
/// page's ink, with at most one control on the far side.
class HubSectionHeader extends StatelessWidget {
  const HubSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final end = trailing;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 44.w),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textSmMedium.copyWith(
                  fontSize: 17.f,
                  height: 22 / 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
          if (end != null) ...[SizedBox(width: 12.w), end],
        ],
      ),
    );
  }
}
