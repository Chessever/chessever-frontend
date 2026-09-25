import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
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
  /// already keeps clear of the label (a pixel object in the top-right
  /// corner) goes without.
  final bool ramp;

  /// Long-press, for tiles that lift into the focus menu.
  final GestureLongPressStartCallback? onLongPressStart;

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
      child: tile,
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
/// Light: a paper card on the page, its artwork washed into paper at the
/// label. Dark: the media tile.
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

  @override
  Widget build(BuildContext context) {
    final isLight = context.isLightTheme;
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
    final shadowed = !isLight && mark == null;
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
    final titleStyle = AppTypography.textMdBold.copyWith(
      fontSize: 16.f,
      color: onTile,
      letterSpacing: 0.3,
      shadows: shadow(0.45, 4, const Offset(0, 1)),
    );
    final captionSize = 12.f;
    final captionStyle = AppTypography.textXsRegular.copyWith(
      fontSize: captionSize,
      color: quiet,
      shadows: shadow(0.4, 3),
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
    final captionRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            caption,
            style: captionStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // A cut caption measures to its ellipsis, so the arrow follows
            // the visible words at the same gap as after a whole caption.
            textWidthBasis: TextWidthBasis.longestLine,
          ),
        ),
        SizedBox(width: 4.w),
        // The page's one navigation arrow (See all's), sized from the
        // caption it ends so the two grow together.
        SpaceGlyph(
          SpaceGlyphKind.arrowUpRight,
          size: (captionSize * 0.8).roundToDouble(),
          // The glyph paints opaque ink, so the caption's veiled white is
          // flattened onto the tile's dark foot first.
          ink: Color.alphaBlend(quiet, isLight ? base : Colors.black),
        ),
      ],
    );

    final markWidget = mark;
    final body = markWidget == null
        ? Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(child: artwork!),
              // One ramp in both themes: it grades the tile's own artwork
              // down to its own ink, and never touches the page behind it.
              if (ramp)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
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
      height: 108.sp,
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

/// Press feedback for a hub tile: it settles to 0.97 under the finger on a
/// spring and springs back on release, so the tap is felt before the route
/// pushes. No scale under reduced motion.
class HubTilePress extends StatefulWidget {
  const HubTilePress({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

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
        value: _pressed && !reduce ? 0.97 : 1.0,
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
