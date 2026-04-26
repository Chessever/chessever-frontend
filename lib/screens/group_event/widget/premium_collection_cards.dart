import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/countrymen/countrymen_tab_screen.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/premium_games/premium_games_screen.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';

import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Collection cards displayed at the top of For You tab.
/// Shows "Favorites" and "Countrymen" cards that navigate to combined game lists.
class PremiumCollectionCards extends StatelessWidget {
  const PremiumCollectionCards({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 20.sp),
      child: Row(
        children: [
          Expanded(
            child: _PremiumCollectionCard(
              type: PremiumGamesType.favorites,
              title: 'Favorites',
            ),
          ),
          SizedBox(width: 12.sp),
          Expanded(
            child: _PremiumCollectionCard(
              type: PremiumGamesType.countrymen,
              title: 'Countrymen',
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05, end: 0);
  }
}

class _PremiumCollectionCard extends ConsumerWidget {
  const _PremiumCollectionCard({required this.type, required this.title});

  final PremiumGamesType type;
  final String title;

  // Neutral accent color for all card types
  Color get _accentColor => kWhiteColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _handleTap(context, ref),
      child: Container(
        height: 108.sp,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: _accentColor.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.br),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Full background fill - player grid for favorites, flag for countrymen
              if (type == PremiumGamesType.favorites)
                const Positioned.fill(child: _FavoritePlayersGridBackground())
              else
                _FlagFullBackground(ref: ref),
              // Gradient overlay for text readability
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        kBlack2Color.withValues(alpha: 0.6),
                        kBlack2Color.withValues(alpha: 0.95),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              // Foreground content - clean text-only design
              Padding(
                padding: EdgeInsets.all(12.sp),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      style: AppTypography.textMdBold.copyWith(
                        color: kWhiteColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(height: 2.sp),
                    Text(
                      'Tap to view→',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

    // Start infinite animation
    useEffect(() {
      animationController.repeat();
      return null;
    }, [animationController]);

    if (favorites.isEmpty) {
      return const _EmptyFavoritesPlaceholder();
    }

    // Smart grid configuration based on favorites count
    final gridConfig = _calculateGridConfig(favorites.length);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        final cardHeight = constraints.maxHeight;

        const cellSpacing = 4.0;
        final rowHeight =
            (cardHeight - (gridConfig.rows - 1) * cellSpacing) /
                gridConfig.rows;
        final actualCellSize =
            math.min(gridConfig.baseCellSize, rowHeight - 2);
        final verticalPadding = (rowHeight - actualCellSize) / 2;
        final cellWithSpacing = actualCellSize + cellSpacing;

        // Pattern repeats every `favorites.length` cells.
        final period = favorites.length * cellWithSpacing;
        // Scroll exactly 2 pattern periods per cycle so the wrap is seamless
        // (controller resets 1.0 → 0.0 and the image is pixel-identical).
        const scrollPeriods = 2;
        final scrollDistance = scrollPeriods * period;
        final stripCellsPerRow =
            ((cardWidth + scrollDistance) / cellWithSpacing).ceil() + 2;

        // Build the cell grid ONCE and pass as `child` to AnimatedBuilder.
        // The inner RepaintBoundary caches the grid to a layer, so per-frame
        // work collapses to a cheap GPU transform of a pre-rasterized image.
        // No ClipRect here: the parent _PremiumCollectionCard already wraps
        // everything in a ClipRRect, so off-card cells are already clipped.
        return RepaintBoundary(
          child: AnimatedBuilder(
            animation: animationController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-animationController.value * scrollDistance, 0),
                child: child,
              );
            },
            child: RepaintBoundary(
              child: _StaticPlayerGrid(
                favorites: favorites,
                rows: gridConfig.rows,
                cellsPerRow: stripCellsPerRow,
                cellSize: actualCellSize,
                cellSpacing: cellSpacing,
                cellWithSpacing: cellWithSpacing,
                verticalPadding: verticalPadding,
              ),
            ),
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
      return const _GridConfig(
        rows: 3,
        baseCellSize: 34.0,
        maxVisibleCells: 12,
      );
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
    required this.rows,
    required this.cellsPerRow,
    required this.cellSize,
    required this.cellSpacing,
    required this.cellWithSpacing,
    required this.verticalPadding,
  });

  final List<FavoritePlayer> favorites;
  final int rows;
  final int cellsPerRow;
  final double cellSize;
  final double cellSpacing;
  final double cellWithSpacing;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    for (int row = 0; row < rows; row++) {
      final rowStagger = row.isOdd ? cellWithSpacing * 0.5 : 0.0;
      final y = row * (cellSize + cellSpacing) + verticalPadding;
      for (int i = 0; i < cellsPerRow; i++) {
        final playerIndex = i % favorites.length;
        final player = favorites[playerIndex];
        final sizeVariation = _getSizeVariation(playerIndex, row);
        final finalCellSize = cellSize * sizeVariation;
        final sizeOffset = (cellSize - finalCellSize) / 2;
        final x = i * cellWithSpacing + rowStagger + sizeOffset;
        cells.add(
          Positioned(
            key: ValueKey(
              '${player.fideId ?? player.playerName}_${row}_$i',
            ),
            left: x,
            top: y + sizeOffset,
            child: _PlayerPhotoCell(
              player: player,
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

  /// Deterministic size variation (0.88–1.0) for organic feel.
  double _getSizeVariation(int playerIndex, int row) {
    final seed = (playerIndex * 7 + row * 13) % 10;
    return 0.88 + (seed / 10) * 0.12;
  }
}

/// Provider to cache player photo URLs - prevents re-fetching on every animation frame
final _playerPhotoUrlProvider = FutureProvider.family
    .autoDispose<String?, String?>((ref, fideId) async {
      if (fideId == null || fideId.isEmpty) return null;
      return FidePhotoService.getPhotoUrlOrNull(fideId);
    });

/// Individual player photo cell with loading and error states
class _PlayerPhotoCell extends ConsumerWidget {
  const _PlayerPhotoCell({required this.player, required this.size});

  final FavoritePlayer player;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use cached provider instead of useFuture to prevent flashing
    final photoUrlAsync = ref.watch(_playerPhotoUrlProvider(player.fideId));

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: kWhiteColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: photoUrlAsync.when(
          data:
              (photoUrl) =>
                  photoUrl != null
                      ? CachedNetworkImage(
                        imageUrl: photoUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).toInt(),
                        placeholder: (_, __) => _buildPlaceholder(),
                        errorWidget: (_, __, ___) => _buildInitials(),
                      )
                      : _buildInitials(),
          loading: () => _buildPlaceholder(),
          error: (_, __) => _buildInitials(),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kWhiteColor.withValues(alpha: 0.15),
            kWhiteColor.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: size * 0.5,
          color: kWhiteColor.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildInitials() {
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
      initials =
          parts
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
            kWhiteColor.withValues(alpha: 0.2),
            kWhiteColor.withValues(alpha: 0.1),
          ],
        ),
      ),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            fontSize: size * 0.32,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.9),
            letterSpacing: -0.5,
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
            kWhiteColor.withValues(alpha: 0.1),
            kWhiteColor.withValues(alpha: 0.05),
            kWhiteColor.withValues(alpha: 0.07),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _FloatingHeartsPainter(accentColor: kWhiteColor),
        size: Size.infinite,
      ),
    );
  }
}

/// Paints floating hearts pattern for empty favorites state
class _FloatingHeartsPainter extends CustomPainter {
  _FloatingHeartsPainter({required this.accentColor});

  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
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
  bool shouldRepaint(covariant _FloatingHeartsPainter oldDelegate) => false;
}

/// Full background country flag for Countrymen card
class _FlagFullBackground extends StatelessWidget {
  const _FlagFullBackground({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final countryAsync = ref.watch(countryDropdownProvider);

    return countryAsync.when(
      data:
          (country) => SizedBox.expand(
            child: Opacity(
              opacity: 0.25,
              child: FittedBox(
                fit: BoxFit.cover,
                child: CountryFlag.fromCountryCode(
country.countryCode,
  theme: ImageTheme(width: 200,
                  height: 150,),
),
              ),
            ),
          ),
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
            kWhiteColor.withValues(alpha: 0.1),
            kWhiteColor.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.public_rounded,
          size: 48.sp,
          color: kWhiteColor.withValues(alpha: 0.15),
        ),
      ),
    );
  }
}
