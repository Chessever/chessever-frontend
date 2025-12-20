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
  const _PremiumCollectionCard({
    required this.type,
    required this.title,
  });

  final PremiumGamesType type;
  final String title;

  // Neutral accent color for all card types
  Color get _accentColor => kWhiteColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = _getSubtitle(ref);

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
                const _FavoritePlayersGridBackground()
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
                    if (subtitle != null)
                      Text(
                        subtitle,
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

  String? _getSubtitle(WidgetRef ref) {
    if (type == PremiumGamesType.favorites) {
      final favorites = ref.watch(favoritePlayersProviderNew).valueOrNull ?? [];
      if (favorites.isEmpty) return 'Tap to add players';
      if (favorites.length == 1) return favorites.first.playerName;
      return '${favorites.length} players followed';
    } else {
      final country = ref.watch(countryDropdownProvider).value;
      return country?.name ?? 'Select country';
    }
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    HapticFeedbackService.cardTap();

    // Navigate directly to combined games screens (no paywall)
    if (context.mounted) {
      if (type == PremiumGamesType.favorites) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const FavoritesTabScreen(),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CountrymenTabScreen(),
          ),
        );
      }
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
      duration: const Duration(seconds: 25),
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

        return AnimatedBuilder(
          animation: animationController,
          builder: (context, child) {
            return ClipRect(
              child: _IrregularPlayerGrid(
                favorites: favorites,
                scrollProgress: animationController.value,
                gridConfig: gridConfig,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
              ),
            );
          },
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
      return const _GridConfig(rows: 2, baseCellSize: 48.0, maxVisibleCells: 4);
    } else if (playerCount == 2) {
      return const _GridConfig(rows: 2, baseCellSize: 44.0, maxVisibleCells: 5);
    } else if (playerCount <= 4) {
      return const _GridConfig(rows: 2, baseCellSize: 40.0, maxVisibleCells: 6);
    } else if (playerCount <= 6) {
      return const _GridConfig(rows: 2, baseCellSize: 36.0, maxVisibleCells: 7);
    } else if (playerCount <= 9) {
      return const _GridConfig(rows: 3, baseCellSize: 32.0, maxVisibleCells: 9);
    } else {
      // Many players: smaller cells, 3 rows
      return const _GridConfig(rows: 3, baseCellSize: 28.0, maxVisibleCells: 12);
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

/// Renders the irregular scrolling grid of player photos with heterogeneous distribution
class _IrregularPlayerGrid extends StatelessWidget {
  const _IrregularPlayerGrid({
    required this.favorites,
    required this.scrollProgress,
    required this.gridConfig,
    required this.cardWidth,
    required this.cardHeight,
  });

  final List<FavoritePlayer> favorites;
  final double scrollProgress;
  final _GridConfig gridConfig;
  final double cardWidth;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    // Generate organic cell placements
    final cells = _generateHeterogeneousCells();

    // Calculate strip width for seamless looping
    final maxX = cells.fold<double>(0, (max, c) => math.max(max, c.x + c.size));
    final stripWidth = maxX + 50; // Add buffer

    // Calculate scroll offset
    final scrollOffset = scrollProgress * stripWidth;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Scrolling player photos with organic placement
        ...cells.map((cell) {
          // Apply scroll offset with wrapping
          var x = cell.x - scrollOffset;

          // Wrap around for seamless infinite scroll
          while (x < -cell.size - 10) {
            x += stripWidth;
          }
          while (x > stripWidth) {
            x -= stripWidth;
          }

          // Skip cells outside visible range
          if (x < -cell.size - 20 || x > cardWidth + 20) {
            return const SizedBox.shrink();
          }

          final player = favorites[cell.playerIndex % favorites.length];

          return Positioned(
            left: x,
            top: cell.y,
            child: _PlayerPhotoCell(
              key: ValueKey('${player.fideId ?? player.playerName}_${cell.id}'),
              player: player,
              size: cell.size,
            ),
          );
        }),
      ],
    );
  }

  /// Generate heterogeneous cell placements with varied sizes and organic positioning
  List<_CellPlacement> _generateHeterogeneousCells() {
    final cells = <_CellPlacement>[];
    final random = _SeededRandom(favorites.length * 31 + 17);

    // Base sizes with more dramatic variation
    final minSize = gridConfig.baseCellSize * 0.7;
    final maxSize = gridConfig.baseCellSize * 1.35;

    // Vertical padding from edges
    final topPadding = 4.0;
    final bottomPadding = 8.0;
    final usableHeight = cardHeight - topPadding - bottomPadding;

    // Generate enough cells to fill ~3x the card width for smooth looping
    final targetWidth = cardWidth * 3.5;
    var currentX = 0.0;
    var cellId = 0;

    // Track recent Y positions to avoid clustering
    final recentYs = <double>[];
    const maxRecentYs = 4;

    while (currentX < targetWidth) {
      // Vary horizontal spacing between cells
      final horizontalGap = 6.0 + random.nextDouble() * 14.0;

      // Determine size with bias toward medium sizes but occasional large/small
      final sizeRoll = random.nextDouble();
      double size;
      if (sizeRoll < 0.15) {
        // 15% chance: small
        size = minSize + random.nextDouble() * (maxSize - minSize) * 0.25;
      } else if (sizeRoll > 0.85) {
        // 15% chance: large
        size = minSize + (maxSize - minSize) * (0.75 + random.nextDouble() * 0.25);
      } else {
        // 70% chance: medium with variation
        size = minSize + (maxSize - minSize) * (0.3 + random.nextDouble() * 0.4);
      }

      // Calculate Y position with heterogeneous distribution
      // Avoid placing too close to recent positions
      double y;
      var attempts = 0;
      do {
        // Add vertical wobble - not aligned to rows
        final baseY = random.nextDouble() * (usableHeight - size);
        y = topPadding + baseY;
        attempts++;
      } while (_isTooCloseToRecent(y, size, recentYs) && attempts < 5);

      // Update recent Y tracking
      recentYs.add(y);
      if (recentYs.length > maxRecentYs) {
        recentYs.removeAt(0);
      }

      cells.add(_CellPlacement(
        id: cellId,
        x: currentX,
        y: y,
        size: size,
        playerIndex: cellId % favorites.length,
      ));

      currentX += size + horizontalGap;
      cellId++;
    }

    return cells;
  }

  /// Check if Y position is too close to recent placements (would cause vertical clustering)
  bool _isTooCloseToRecent(double y, double size, List<double> recentYs) {
    if (recentYs.isEmpty) return false;

    final minDistance = size * 0.6; // Minimum vertical gap
    for (final recentY in recentYs.take(2)) {
      if ((y - recentY).abs() < minDistance) {
        return true;
      }
    }
    return false;
  }
}

/// Simple seeded pseudo-random for deterministic but varied distribution
class _SeededRandom {
  _SeededRandom(this._seed);

  int _seed;

  double nextDouble() {
    _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
    return (_seed / 0x7fffffff);
  }
}

/// Represents a single cell placement in the heterogeneous grid
class _CellPlacement {
  const _CellPlacement({
    required this.id,
    required this.x,
    required this.y,
    required this.size,
    required this.playerIndex,
  });

  final int id;
  final double x;
  final double y;
  final double size;
  final int playerIndex;
}



/// Provider to cache player photo URLs - prevents re-fetching on every animation frame
final _playerPhotoUrlProvider = FutureProvider.family.autoDispose<String?, String?>((ref, fideId) async {
  if (fideId == null || fideId.isEmpty) return null;
  return FidePhotoService.getPhotoUrlOrNull(fideId);
});

/// Individual player photo cell with loading and error states
class _PlayerPhotoCell extends ConsumerWidget {
  const _PlayerPhotoCell({
    super.key,
    required this.player,
    required this.size,
  });

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
          color: kWhiteColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: photoUrlAsync.when(
          data: (photoUrl) => photoUrl != null
              ? CachedNetworkImage(
                  imageUrl: photoUrl,
                  fit: BoxFit.cover,
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
      initials = '${lastName.isNotEmpty ? lastName[0] : ''}'
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
      center.dx - w * 0.5, center.dy - h * 0.1,
      center.dx - w * 0.5, center.dy - h * 0.5,
      center.dx, center.dy - h * 0.25,
    );
    path.cubicTo(
      center.dx + w * 0.5, center.dy - h * 0.5,
      center.dx + w * 0.5, center.dy - h * 0.1,
      center.dx, center.dy + h * 0.3,
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
      data: (country) => SizedBox.expand(
        child: Opacity(
          opacity: 0.25,
          child: FittedBox(
            fit: BoxFit.cover,
            child: CountryFlag.fromCountryCode(
              country.countryCode,
              width: 200,
              height: 150,
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
