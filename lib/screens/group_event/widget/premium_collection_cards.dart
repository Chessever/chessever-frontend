import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/countrymen/countrymen_tab_screen.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/premium_games/premium_games_screen.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/flag_pole_scene.dart';
import 'package:chessever2/widgets/card_context_menu.dart';

import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/light_media_art.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// On-media ink and the tile's own ink, from the shared hub tile.
const Color _kOnTile = kHubTileOnMedia;

Color _onTile(BuildContext context) => hubTileOnTile(context);

/// Collection cards displayed at the top of For You tab.
/// Shows "Favorites" and "Countrymen" cards that navigate to combined game lists.
class PremiumCollectionCards extends StatelessWidget {
  const PremiumCollectionCards({super.key});

  @override
  Widget build(BuildContext context) {
    return const HubTileRow(
      left: _PremiumCollectionCard(
        type: PremiumGamesType.favorites,
        title: 'Favorites',
      ),
      right: _PremiumCollectionCard(
        type: PremiumGamesType.countrymen,
        title: 'Countrymen',
      ),
    );
  }
}

class _PremiumCollectionCard extends ConsumerWidget {
  const _PremiumCollectionCard({required this.type, required this.title});

  final PremiumGamesType type;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = HubTilePress(
      onTap: () => _handleTap(context, ref),
      child: _buildTile(context, ref),
    );
    // Favorites has no My Space kind of its own; Countrymen pins the
    // federation on the tile.
    if (type != PremiumGamesType.countrymen) return tile;
    return Builder(
      builder: (anchorContext) => GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onLongPressStart: (details) =>
            _showCountrymenMenu(anchorContext, ref, details.globalPosition),
        child: tile,
      ),
    );
  }

  /// Long-press on the Countrymen tile: it lifts into the shared focus menu
  /// to open Countrymen or pin the federation it shows into My Space.
  void _showCountrymenMenu(
    BuildContext anchorContext,
    WidgetRef ref,
    Offset origin,
  ) {
    final country = ref.read(countryDropdownProvider).valueOrNull;
    final code = country?.countryCode.trim() ?? '';
    CardContextMenu.open(
      anchorContext,
      actions: (menuContext) => [
        LibraryMenuAction(
          icon: Icons.open_in_new_rounded,
          label: 'Open Countrymen',
          onSelected: () => _handleTap(anchorContext, ref),
        ),
        if (country != null && code.isNotEmpty)
          spaceMenuAction(
            context: menuContext,
            ref: ref,
            // Same shortcut the Countrymen screen pins, so the two
            // dedupe: targetId is the federation code.
            draft: SpaceShortcut.draft(
              kind: SpaceShortcutKind.countrymen,
              targetId: code,
              title: country.name,
              subtitle: 'Countrymen',
              params: {'name': country.name},
            ),
          ),
      ],
      previewBuilder: (_) => _buildTile(anchorContext, ref),
      onPreviewTap: () => _handleTap(anchorContext, ref),
      // A screen reader's long-press action reports no position.
      origin: origin == Offset.zero ? null : origin,
    );
  }

  Widget _buildTile(BuildContext context, WidgetRef ref) {
    // Light: the tile's own drawing in the light hub style (the stands the
    // favourites glide across, the pole the federation's flag flies from),
    // with the photos and the flag at full strength in a region of their
    // own, clear of the label. Nothing is laid over them.
    if (context.isLightTheme) {
      return HubTileFace(
        title: title,
        ramp: false,
        artwork: type == PremiumGamesType.favorites
            ? _FavoritesPaperArt(title: title)
            : _CountrymenPaperArt(ref: ref, title: title),
      );
    }
    // Full background: the player grid for Favorites, the flag for
    // Countrymen.
    final artwork = type == PremiumGamesType.favorites
        ? const _FavoritePlayersGridBackground()
        : _FlagFullBackground(ref: ref);
    return HubTileFace(title: title, ramp: true, artwork: artwork);
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    HapticFeedbackService.cardTap();

    // Navigate freely - paywall is shown on actions (tapping games, saving to book)
    // This creates FOMO by letting users see what they're missing
    if (type == PremiumGamesType.favorites) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const FavoritesTabScreen()));
    } else {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CountrymenTabScreen()));
    }
  }
}

/// Auto-scrolling irregular player photo grid background for Favorites card.
/// Creates a visually interesting mosaic of player photos that scrolls indefinitely.
class _FavoritePlayersGridBackground extends HookConsumerWidget {
  const _FavoritePlayersGridBackground();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoritePlayersProviderNew);
    final favorites = favoritesAsync.valueOrNull ?? [];

    // Animation controller for infinite horizontal scroll
    final animationController = useAnimationController(
      duration: const Duration(seconds: 45),
    );

    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    // Start infinite animation unless the OS requests reduced motion.
    useEffect(() {
      if (disableAnimations) {
        animationController.stop();
        animationController.value = 0;
      } else {
        animationController.repeat();
      }
      return null;
    }, [animationController, disableAnimations]);

    if (favorites.isEmpty) {
      return const _EmptyFavoritesPlaceholder();
    }

    // Smart grid configuration based on favorites count
    final gridConfig = _calculateGridConfig(favorites.length);
    final patternCellCount = math.min(
      favorites.length,
      gridConfig.maxVisibleCells,
    );
    final patternFavorites = favorites.length > patternCellCount
        ? favorites.take(patternCellCount).toList(growable: false)
        : favorites;
    final photoUrls =
        ref
            .watch(_favoritePhotoUrlsProvider(_photoUrlKey(patternFavorites)))
            .valueOrNull ??
        const <String, String?>{};

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        final cardHeight = constraints.maxHeight;

        // Bail out on degenerate constraints (zero/negative/non-finite). Without
        // this guard the math below collapses cellWithSpacing to zero and
        // (cardWidth / 0).ceil() throws "Infinity or NaN toInt".
        if (!cardWidth.isFinite ||
            !cardHeight.isFinite ||
            cardWidth <= 0 ||
            cardHeight <= 8) {
          return const SizedBox.shrink();
        }

        const cellSpacing = 4.0;
        final rowHeight =
            (cardHeight - (gridConfig.rows - 1) * cellSpacing) /
            gridConfig.rows;
        final actualCellSize = math.max(
          1.0,
          math.min(gridConfig.baseCellSize, rowHeight - 2),
        );
        final verticalPadding = (rowHeight - actualCellSize) / 2;
        final cellWithSpacing = actualCellSize + cellSpacing;

        // Keep the animated strip bounded. The old version repeated every
        // favorite, so users with large favorite lists rendered hundreds of
        // clipped image widgets behind a tiny card.
        final scrollDistance = patternCellCount * cellWithSpacing;
        final stripCellsPerRow =
            ((cardWidth + scrollDistance) / cellWithSpacing).ceil() + 2;

        // Build the cell grid ONCE and pass as `child` to AnimatedBuilder.
        // The inner RepaintBoundary caches the grid to a layer, so per-frame
        // work collapses to a cheap GPU transform of a pre-rasterized image.
        // No ClipRect here: the parent _PremiumCollectionCard already wraps
        // everything in a ClipRRect, so off-card cells are already clipped.
        final grid = RepaintBoundary(
          child: _StaticPlayerGrid(
            favorites: patternFavorites,
            photoUrls: photoUrls,
            patternCellCount: patternCellCount,
            rows: gridConfig.rows,
            cellsPerRow: stripCellsPerRow,
            cellSize: actualCellSize,
            cellSpacing: cellSpacing,
            cellWithSpacing: cellWithSpacing,
            verticalPadding: verticalPadding,
          ),
        );

        if (disableAnimations) {
          return RepaintBoundary(child: grid);
        }

        return RepaintBoundary(
          child: AnimatedBuilder(
            animation: animationController,
            child: grid,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-animationController.value * scrollDistance, 0),
                child: child,
              );
            },
          ),
        );
      },
    );
  }

  /// Smart algorithm: adapt grid based on number of players.
  /// Key insight: keep maximum 9 visible cells per frame to ensure photos
  /// remain recognizable. Fewer players = larger cells.
  _GridConfig _calculateGridConfig(int playerCount) {
    if (playerCount == 1) {
      // Single player: large prominent photo
      return const _GridConfig(rows: 2, baseCellSize: 56.0, maxVisibleCells: 4);
    } else if (playerCount == 2) {
      return const _GridConfig(rows: 2, baseCellSize: 52.0, maxVisibleCells: 5);
    } else if (playerCount <= 4) {
      return const _GridConfig(rows: 2, baseCellSize: 48.0, maxVisibleCells: 6);
    } else if (playerCount <= 6) {
      return const _GridConfig(rows: 2, baseCellSize: 44.0, maxVisibleCells: 7);
    } else if (playerCount <= 9) {
      return const _GridConfig(rows: 3, baseCellSize: 38.0, maxVisibleCells: 9);
    } else {
      // Many players: smaller cells, 3 rows
      return const _GridConfig(rows: 3, baseCellSize: 34.0, maxVisibleCells: 9);
    }
  }
}

/// Configuration for the irregular grid layout
class _GridConfig {
  const _GridConfig({
    required this.rows,
    required this.baseCellSize,
    required this.maxVisibleCells,
  });

  final int rows;
  final double baseCellSize;
  final int maxVisibleCells;
}

/// Renders the grid of player photos at fixed positions. The parent wraps
/// this in an AnimatedBuilder + Transform.translate, so this widget is built
/// once per layout and reused across all animation frames.
class _StaticPlayerGrid extends StatelessWidget {
  const _StaticPlayerGrid({
    required this.favorites,
    required this.photoUrls,
    required this.patternCellCount,
    required this.rows,
    required this.cellsPerRow,
    required this.cellSize,
    required this.cellSpacing,
    required this.cellWithSpacing,
    required this.verticalPadding,
    this.rowPitch,
  });

  final List<FavoritePlayer> favorites;
  final Map<String, String?> photoUrls;
  final int patternCellCount;
  final int rows;
  final int cellsPerRow;
  final double cellSize;
  final double cellSpacing;
  final double cellWithSpacing;
  final double verticalPadding;

  /// From one row's top to the next; a cell and its gap unless set. The
  /// light strip packs its staggered rows closer (they never touch).
  final double? rowPitch;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    for (int row = 0; row < rows; row++) {
      final rowStagger = row.isOdd ? cellWithSpacing * 0.5 : 0.0;
      final y = row * (rowPitch ?? cellSize + cellSpacing) + verticalPadding;
      for (int i = 0; i < cellsPerRow; i++) {
        final patternIndex = i % patternCellCount;
        final playerIndex = patternIndex % favorites.length;
        final player = favorites[playerIndex];
        final sizeVariation = _getSizeVariation(patternIndex, row);
        final finalCellSize = cellSize * sizeVariation;
        final sizeOffset = (cellSize - finalCellSize) / 2;
        final x = i * cellWithSpacing + rowStagger + sizeOffset;
        cells.add(
          Positioned(
            key: ValueKey('${player.fideId ?? player.playerName}_${row}_$i'),
            left: x,
            top: y + sizeOffset,
            child: _PlayerPhotoCell(
              player: player,
              photoUrl: player.fideId == null ? null : photoUrls[player.fideId],
              size: finalCellSize,
            ),
          ),
        );
      }
    }
    // Clip.none: cells extend beyond the Stack's card-width constraints (up
    // to stripWidth). The RepaintBoundary must cache all of them so the
    // Transform.translate can slide them into view. The outer ClipRRect on
    // _PremiumCollectionCard handles the final visible clip.
    return Stack(clipBehavior: Clip.none, children: cells);
  }

  /// The smallest a photo is drawn, as a share of [cellSize]
  /// ([_getSizeVariation]'s least).
  static const double smallestShare = 0.88;

  /// Deterministic size variation (0.88–1.0) for organic feel.
  double _getSizeVariation(int playerIndex, int row) {
    final seed = (playerIndex * 7 + row * 13) % 10;
    return 0.88 + (seed / 10) * 0.12;
  }
}

/// One bounded lookup for the whole mosaic. This avoids each repeated visual
/// cell becoming its own Consumer while the animated layer is being cached.
final _favoritePhotoUrlsProvider = FutureProvider.family
    .autoDispose<Map<String, String?>, String>((ref, key) async {
      if (key.isEmpty) return const <String, String?>{};

      final ids = key.split('|').where((id) => id.isNotEmpty).toSet();
      if (ids.isEmpty) return const <String, String?>{};

      final entries = await Future.wait(
        ids.map((id) async {
          final url = await FidePhotoService.getPhotoUrlOrNull(id);
          return MapEntry(id, url);
        }),
      );
      return Map<String, String?>.fromEntries(entries);
    });

String _photoUrlKey(List<FavoritePlayer> favorites) {
  return favorites
      .map((player) => player.fideId ?? '')
      .where((id) => id.isNotEmpty)
      .join('|');
}

/// Individual player photo cell with loading and error states
class _PlayerPhotoCell extends StatelessWidget {
  const _PlayerPhotoCell({
    required this.player,
    required this.photoUrl,
    required this.size,
  });

  final FavoritePlayer player;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photo = ClipOval(
      child: photoUrl != null
          ? CachedNetworkImage(
              imageUrl: photoUrl!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .toInt(),
              memCacheHeight: (size * MediaQuery.devicePixelRatioOf(context))
                  .toInt(),
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (_, __) => _buildPlaceholder(context),
              errorWidget: (_, __, ___) => _buildInitials(context),
            )
          : _buildInitials(context),
    );
    if (context.isLightTheme) {
      // Paper: the photo fills its whole circle, and its own edge is
      // deepened a touch into a fine rim (no ring of another colour, no
      // shadow), so a pale photo still reads as a round portrait.
      return SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x24000000), width: 1),
          ),
          child: photo,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _kOnTile.withValues(alpha: 0.35), width: 1.5),
      ),
      child: photo,
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _onTile(context).withValues(alpha: 0.15),
            _onTile(context).withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: size * 0.5,
          color: _onTile(context).withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildInitials(BuildContext context) {
    // Parse initials from "Lastname, Firstname" format
    final nameParts = player.playerName.split(',');
    String initials;
    if (nameParts.length > 1) {
      final lastName = nameParts[0].trim();
      final firstName = nameParts[1].trim();
      initials =
          '${lastName.isNotEmpty ? lastName[0] : ''}'
          '${firstName.isNotEmpty ? firstName[0] : ''}';
    } else {
      // Fallback for "Firstname Lastname" format
      final parts = player.playerName.split(' ');
      initials = parts
          .take(2)
          .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
          .join();
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _onTile(context).withValues(alpha: 0.12),
            _onTile(context).withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: size * 0.32,
            fontWeight: FontWeight.w700,
            color: _onTile(context).withValues(alpha: 0.9),
            letterSpacing: -0.5,
            // Default line height leaves the glyphs sitting a hair high in the
            // circle. Pinning it to 1 hands the vertical centring to the Center
            // above, so the initials land on the true middle.
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Empty state placeholder when no favorites - shows floating hearts pattern
class _EmptyFavoritesPlaceholder extends StatelessWidget {
  const _EmptyFavoritesPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _onTile(context).withValues(alpha: 0.1),
            _onTile(context).withValues(alpha: 0.05),
            _onTile(context).withValues(alpha: 0.07),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _FloatingHeartsPainter(accentColor: _onTile(context)),
        size: Size.infinite,
      ),
    );
  }
}

/// Paints floating hearts pattern for empty favorites state
class _FloatingHeartsPainter extends CustomPainter {
  const _FloatingHeartsPainter({required this.accentColor});

  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accentColor.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    // Draw scattered hearts at various positions and sizes
    final positions = [
      (0.15, 0.2, 12.0),
      (0.45, 0.35, 16.0),
      (0.75, 0.15, 10.0),
      (0.25, 0.7, 14.0),
      (0.65, 0.65, 11.0),
      (0.85, 0.5, 13.0),
      (0.35, 0.45, 9.0),
    ];

    for (final (xRatio, yRatio, heartSize) in positions) {
      final x = size.width * xRatio;
      final y = size.height * yRatio;
      _drawHeart(canvas, Offset(x, y), heartSize, paint);
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    final w = size;
    final h = size;

    path.moveTo(center.dx, center.dy + h * 0.3);
    path.cubicTo(
      center.dx - w * 0.5,
      center.dy - h * 0.1,
      center.dx - w * 0.5,
      center.dy - h * 0.5,
      center.dx,
      center.dy - h * 0.25,
    );
    path.cubicTo(
      center.dx + w * 0.5,
      center.dy - h * 0.5,
      center.dx + w * 0.5,
      center.dy - h * 0.1,
      center.dx,
      center.dy + h * 0.3,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FloatingHeartsPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}

/// Full background country flag for Countrymen card
class _FlagFullBackground extends StatelessWidget {
  const _FlagFullBackground({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final countryAsync = ref.watch(countryDropdownProvider);

    return countryAsync.when(
      data: (country) {
        final flag = FittedBox(
          fit: BoxFit.cover,
          child: CountryFlag.fromCountryCode(
            country.countryCode,
            theme: ImageTheme(width: 200, height: 150),
          ),
        );
        return SizedBox.expand(child: Opacity(opacity: 0.25, child: flag));
      },
      loading: () => _FlagPlaceholder(),
      error: (_, __) => _FlagPlaceholder(),
    );
  }
}

class _FlagPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _onTile(context).withValues(alpha: 0.1),
            _onTile(context).withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.public_rounded,
          size: 48.sp,
          color: _onTile(context).withValues(alpha: 0.15),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- light

/// The light Today tiles' picture band: the room above the title's capitals.
/// The Favorites photos and the Countrymen flag share its top and its size,
/// centred between the tile's top edge and the title, so the two tiles read
/// as a pair and the label always sits on calm ground below.
@immutable
class _PaperBand {
  const _PaperBand._({
    required this.top,
    required this.size,
    required this.capTop,
  });

  /// The band of a tile [height] tall titled [title], at the reader's text
  /// size.
  factory _PaperBand.of(
    BuildContext context, {
    required String title,
    required double height,
  }) {
    final capTop = HubTileFace.labelCapTop(
      context,
      title: title,
      height: height,
    );
    // A photo large enough to know its face, with room above and below.
    final size = math.max(0.0, math.min(36.sp, capTop - 2 * margin));
    return _PaperBand._(top: (capTop - size) / 2, size: size, capTop: capTop);
  }

  /// The least room above and below the band's art.
  static double get margin => 5.sp;

  /// Where the art starts: a photo's top, the finial's.
  final double top;

  /// A photo's diameter; the most a flag stands.
  final double size;

  /// The top of the title's capitals.
  final double capTop;
}

/// The light Favorites drawing: an empty grandstand in the light hub style,
/// 768x512 on a transparent ground.
const String _kFavoritesLightAsset = 'assets/pngs/hub_favorites_light.webp';

/// Where the grandstand's two tiers sit in [_kFavoritesLightAsset], as
/// shares of its height, measured once on the 1536x1024 master by scanning
/// its columns for drawn pixels: the upper tier's seats from y 166, the
/// lower tier's from 332 at the top of its arch (down its middle column the
/// seat backs run to 375, the seat bottoms to 409, the rail to 443). The
/// tiers arch down toward the sides; the upper tier never reaches below
/// y 280.
const double _kStandsUpperSeatTop = 166 / 1024;
const double _kStandsLowerSeatTop = 332 / 1024;
const double _kStandsLowerRailFoot = 444 / 1024;
const double _kStandsBetweenTiers = 300 / 1024;

/// Light Favorites: the followed players' photos glide in a row across the
/// tile's picture band, in front of the grandstand's lower tier, at full
/// strength. Only the strip's two ends fade, short, where the photos glide
/// in and out; the label below sits on plain ground. With no favourite yet,
/// the empty stands fill the band.
class _FavoritesPaperArt extends HookConsumerWidget {
  const _FavoritesPaperArt({required this.title});

  /// The tile's title, which the photos keep above.
  final String title;

  /// How long the strip takes to glide one photo's width (about seven
  /// logical pixels a second).
  static const Duration _glidePerPhoto = Duration(milliseconds: 3800);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites =
        ref.watch(favoritePlayersProviderNew).valueOrNull ??
        const <FavoritePlayer>[];
    final pattern = favorites.take(12).toList(growable: false);
    final period = _glidePerPhoto * math.max(1, pattern.length);
    final controller = useAnimationController(duration: period);
    final still = MediaQuery.disableAnimationsOf(context);
    useEffect(() {
      if (still || pattern.isEmpty) {
        controller
          ..stop()
          ..value = 0;
      } else {
        controller.repeat(period: period);
      }
      return null;
    }, [controller, still, period, pattern.isEmpty]);
    final photoUrls =
        ref
            .watch(_favoritePhotoUrlsProvider(_photoUrlKey(pattern)))
            .valueOrNull ??
        const <String, String?>{};

    return ExcludeSemantics(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            final height = box.maxHeight;
            if (!width.isFinite || width <= 0 || !height.isFinite) {
              return const SizedBox.shrink();
            }
            final band = _PaperBand.of(context, title: title, height: height);
            if (pattern.isEmpty) {
              return _stands(
                width: width,
                // Both tiers, from the upper seats to the lower rail, fill
                // the band.
                height:
                    band.size / (_kStandsLowerRailFoot - _kStandsUpperSeatTop),
                seatTop: band.top,
                seatShare: _kStandsUpperSeatTop,
              );
            }
            // One row of photos large enough to know each face; two
            // staggered rows only where the band is tall enough for both.
            final room = band.capTop - 2 * _PaperBand.margin;
            final twoRows = room / 1.9 >= 30.sp;
            final cell = twoRows ? math.min(34.sp, room / 1.9) : band.size;
            if (cell < 12) return const SizedBox.shrink();
            final gap = 4.sp;
            final pitch = cell + gap;
            // Staggered by half a photo, two rows can sit closer than a
            // photo's height and still never touch.
            final rowPitch = cell * 0.9;
            final strip = twoRows ? cell + rowPitch : cell;
            final top = (band.capTop - strip) / 2;
            final distance = pattern.length * pitch;
            // The lower tier stands behind the last row, in its photos'
            // lower half: its seats rise no higher than the photos' centre
            // line (their bottoms and the rail sit behind the lower third)
            // and its rail ends at the foot of the smallest photo, so
            // nothing of the stands shows between the faces above their
            // centre line. The upper tier is left out.
            final centre = top + strip - cell / 2;
            final radius = cell * _StaticPlayerGrid.smallestShare / 2;
            final standsHeight =
                (radius - 0.5) / (_kStandsLowerRailFoot - _kStandsLowerSeatTop);
            final grid = RepaintBoundary(
              child: _StaticPlayerGrid(
                favorites: pattern,
                photoUrls: photoUrls,
                patternCellCount: pattern.length,
                rows: twoRows ? 2 : 1,
                cellsPerRow: ((width + distance) / pitch).ceil() + 2,
                cellSize: cell,
                cellSpacing: gap,
                cellWithSpacing: pitch,
                verticalPadding: 0,
                rowPitch: rowPitch,
              ),
            );
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                _stands(
                  width: width,
                  height: standsHeight,
                  seatTop: centre + 0.5,
                  seatShare: _kStandsLowerSeatTop,
                  upperTier: false,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: top,
                  height: strip,
                  // The strip's own layer: each frame moves the photos
                  // under its fade and repaints nothing else of the tile.
                  child: RepaintBoundary(
                    child: LightEdgeFade(
                      gradient: stripEdgeFade(),
                      child: ClipRect(
                        child: _glide(
                          controller,
                          grid: grid,
                          distance: distance,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The grandstand [height] tall, centred across [width], with the seat
  /// top at [seatShare] of its height standing at [seatTop]: the whole of it
  /// as the tile's picture, or (without the [upperTier]) its lower tier
  /// alone, everything above it cut away, as a layer of the tile's picture.
  Widget _stands({
    required double width,
    required double height,
    required double seatTop,
    required double seatShare,
    bool upperTier = true,
  }) {
    final standsTop = seatTop - seatShare * height;
    // Its own proportions, or stretched across the tile where they would
    // leave its ends inside it.
    final standsWidth = math.max(height * 1.5, width + 2);
    final picture = Image.asset(
      _kFavoritesLightAsset,
      fit: BoxFit.fill,
      cacheWidth: 768,
      filterQuality: FilterQuality.medium,
    );
    if (upperTier) {
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: (width - standsWidth) / 2,
            top: standsTop,
            width: standsWidth,
            height: height,
            child: picture,
          ),
        ],
      );
    }
    final cut = standsTop + _kStandsBetweenTiers * height;
    return Positioned(
      left: 0,
      right: 0,
      top: cut,
      bottom: 0,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: (width - standsWidth) / 2,
              top: standsTop - cut,
              width: standsWidth,
              height: height,
              child: picture,
            ),
          ],
        ),
      ),
    );
  }

  Widget _glide(
    AnimationController controller, {
    required Widget grid,
    required double distance,
  }) {
    return AnimatedBuilder(
      animation: controller,
      child: grid,
      builder: (context, child) => Transform.translate(
        offset: Offset(-controller.value * distance, 0),
        child: child,
      ),
    );
  }
}

/// Light Countrymen: the federation's real flag flying from the drawing's
/// pole in the tile's picture band, the pole and its flag centred across the
/// tile. The cloth is matched to the Favorites photos beside it (as tall,
/// level with them), the finial just above; the pole's foot and the mound
/// ease into the ground just above the title, so the label sits on calm
/// ground below.
class _CountrymenPaperArt extends StatelessWidget {
  const _CountrymenPaperArt({required this.ref, required this.title});

  final WidgetRef ref;
  final String title;

  /// The shaft showing under the cloth at rest, as a share of its height.
  static const double _shaftUnderCloth = 0.05;

  @override
  Widget build(BuildContext context) {
    final country = ref.watch(countryDropdownProvider);
    // Nothing until the federation is known, so the pole never stands bare
    // and then moves for the flag it flies.
    if (country.isLoading && !country.hasValue) return const SizedBox.shrink();
    final code = country.valueOrNull == null
        ? null
        : flagClothCode(country.valueOrNull!.countryCode);
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
        final band = _PaperBand.of(context, title: title, height: size.height);
        // The ground the mound fades into, a little above the title's
        // capitals, the room the mound needs to fade there, and the least
        // room above the finial.
        final ground = band.capTop - 1.5.sp;
        final fade = 4.sp;
        final headroom = 7.sp;
        // Down the picture, per point of cloth: the finial and collar above
        // it, and the cloth, the shaft under it and the base block below.
        const shaft = FlagPoleArt.poleFoot - FlagPoleArt.hoistTop;
        const perCloth = (1 + _shaftUnderCloth) / shaft;
        const above = (FlagPoleArt.hoistTop - FlagPoleArt.finialTop) * perCloth;
        const below = (FlagPoleArt.moundTop - FlagPoleArt.hoistTop) * perCloth;
        // The cloth level with the photos and as tall, or shorter where
        // the picture would not then fit between the headroom and the
        // ground.
        var cloth = math.min(band.size, (ground - fade - band.top) / below);
        var clothTop = band.top;
        if (clothTop - above * cloth < headroom) {
          cloth = math.min(cloth, (ground - fade - headroom) / (above + below));
          clothTop = math.max(band.top, headroom + above * cloth);
        }
        if (cloth < 12) return const SizedBox.shrink();
        final height = cloth * perCloth;
        final pictureTop = clothTop - FlagPoleArt.hoistTop * height;
        return FlagPoleScene(
          flagCode: code,
          footFade: ground - (pictureTop + FlagPoleArt.moundTop * height),
          groundLine: ground,
          layout: (aspect) => FlagPoleLayout.centred(
            width: size.width,
            bottom: pictureTop + height,
            height: height,
            cloth: FlagPoleLayout.fitCloth(
              Size(
                size.width -
                    2 * HubTileFace.labelInset -
                    FlagPoleLayout.finialReach(height),
                cloth,
              ),
              aspect,
            ),
          ),
        );
      },
    );
  }
}
