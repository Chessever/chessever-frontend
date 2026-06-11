import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/library_combined_search_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart'
    show getTitleBadgeColor;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Maximum number of player cards to display
const int _maxTwicPlayerCards = 4;

/// Provider that extracts top players from the TWIC/library combined search.
/// Mirrors `topSearchedPlayersProvider` from the home page but for `GamebasePlayer`.
final topTwicSearchedPlayersProvider = Provider.autoDispose
    .family<List<GamebasePlayer>, String>((ref, query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];

  final searchAsync = ref.watch(libraryCombinedSearchProvider(trimmed));
  return searchAsync.maybeWhen(
    data: (result) {
      if (result.players.isEmpty) return const [];
      final seen = <String>{};
      final unique = <GamebasePlayer>[];
      for (final p in result.players) {
        final key = p.name.toLowerCase().trim();
        if (seen.add(key)) {
          unique.add(p);
          if (unique.length >= _maxTwicPlayerCards) break;
        }
      }
      return unique;
    },
    orElse: () => const [],
  );
});

/// Player search cards displayed above the TWIC games list.
/// Mirrors the home-page `PlayerSearchCards` aesthetic but consumes
/// `GamebasePlayer` from the gamebase combined search.
class TwicPlayerSearchCards extends ConsumerWidget {
  const TwicPlayerSearchCards({super.key, required this.searchQuery});

  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(topTwicSearchedPlayersProvider(searchQuery));

    if (players.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 12.h),
      child: _buildPlayerGrid(players),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05, end: 0);
  }

  Widget _buildPlayerGrid(List<GamebasePlayer> players) {
    if (players.length == 1) {
      return _TwicPlayerCard(player: players.first, isCompact: false);
    }

    if (players.length == 2) {
      return Row(
        children: [
          Expanded(child: _TwicPlayerCard(player: players[0], isCompact: true)),
          SizedBox(width: 12.sp),
          Expanded(child: _TwicPlayerCard(player: players[1], isCompact: true)),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _TwicPlayerCard(player: players[0], isCompact: true)),
            SizedBox(width: 12.sp),
            Expanded(child: _TwicPlayerCard(player: players[1], isCompact: true)),
          ],
        ),
        SizedBox(height: 12.sp),
        Row(
          children: [
            Expanded(child: _TwicPlayerCard(player: players[2], isCompact: true)),
            SizedBox(width: 12.sp),
            if (players.length > 3)
              Expanded(
                child: _TwicPlayerCard(player: players[3], isCompact: true),
              )
            else
              const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }
}

class _TwicPlayerCard extends ConsumerWidget {
  const _TwicPlayerCard({required this.player, this.isCompact = false});

  final GamebasePlayer player;
  final bool isCompact;

  void _navigateToProfile(BuildContext context) {
    HapticFeedbackService.buttonPress();
    final fideIdInt = int.tryParse(player.fideId.trim());
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerProfileScreen(
          fideId: fideIdInt,
          playerName: player.name,
          title: player.title,
          federation: player.fed,
          rating: player.highestRating,
          gamebasePlayerId: player.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countryCode = _getIso2CountryCode();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _navigateToProfile(context),
      child: Container(
        height: isCompact ? 108.sp : 120.sp,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: context.colors.divider,
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.br),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (countryCode != null)
                _FlagBackground(countryCode: countryCode),
              _PlayerPhotoOverlay(player: player, isCompact: isCompact),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        Colors.transparent,
                        context.colors.surface.withValues(alpha: 0.5),
                        context.colors.surface.withValues(alpha: 0.85),
                        context.colors.surface.withValues(alpha: 0.95),
                      ],
                      stops: const [0.0, 0.25, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(isCompact ? 12.sp : 14.sp),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (player.title != null && player.title!.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(bottom: 4.sp),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 5.sp,
                            vertical: 2.sp,
                          ),
                          decoration: BoxDecoration(
                            color: getTitleBadgeColor(player.title!),
                            borderRadius: BorderRadius.circular(4.br),
                          ),
                          child: Text(
                            player.title!,
                            style: AppTypography.textXsBold.copyWith(
                              color: context.colors.textPrimary,
                              fontSize: isCompact ? 9.sp : 10.sp,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    Text(
                      player.displayName,
                      style: (isCompact
                              ? AppTypography.textMdBold
                              : AppTypography.textLgBold)
                          .copyWith(
                        color: context.colors.textPrimary,
                        letterSpacing: 0.3,
                      ),
                      maxLines: isCompact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2.sp),
                    Row(
                      children: [
                        if (player.fed.trim().isNotEmpty) ...[
                          FederationFlag(
                            federation: player.fed,
                            width: isCompact ? 14.sp : 16.sp,
                            height: isCompact ? 10.sp : 12.sp,
                            borderRadius: BorderRadius.circular(2.br),
                          ),
                          SizedBox(width: 5.sp),
                        ],
                        Expanded(
                          child: Text(
                            _buildSubtitle(),
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.colors.textPrimary
                                  .withValues(alpha: 0.7),
                              fontSize: isCompact ? 10.sp : 11.sp,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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

  String _buildSubtitle() {
    final parts = <String>[];

    final rating = player.highestRating;
    if (rating != null && rating > 0) {
      parts.add('$rating');
    }

    final fed = player.fed.trim();
    if (fed.isNotEmpty) {
      final countryName = CountryUtils.getCountryName(fed);
      parts.add(countryName.isNotEmpty ? countryName : fed);
    }

    return parts.join(' • ');
  }

  String? _getIso2CountryCode() {
    final fed = player.fed.trim();
    if (fed.isEmpty) return null;
    final lower = fed.toLowerCase();
    // Treat TWIC's "Unknown" / sentinel feds as no flag.
    if (const {'unknown', 'none', 'unrated', 'n/a', 'na', '?', '-'}
        .contains(lower)) {
      return null;
    }
    // fed can be 2-letter ISO, 3-letter FIDE, or a country name (TWIC uses names).
    final upper = fed.toUpperCase();
    if (upper.length == 2) return upper;
    if (upper.length == 3) {
      final iso = CountryUtils.toIso2Code(upper);
      return (iso.length == 2) ? iso : null;
    }
    final mapped = CountryUtils.countryNameToIso2(fed);
    if (mapped.isNotEmpty) return mapped;
    final fallback = CountryUtils.getCountryCode(fed);
    return (fallback != null && fallback.length == 2) ? fallback : null;
  }
}

/// Full background country flag with subtle opacity
class _FlagBackground extends StatelessWidget {
  const _FlagBackground({required this.countryCode});

  final String countryCode;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Opacity(
        opacity: 0.20,
        child: FittedBox(
          fit: BoxFit.cover,
          child: FederationFlag(
            federation: countryCode,
            width: 300,
            height: 200,
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
    );
  }
}

/// FIDE photo cache provider — keyed by raw fideId string so empty/non-numeric
/// fall through cleanly to placeholder.
final _twicPlayerPhotoUrlProvider = FutureProvider.family
    .autoDispose<String?, String>((ref, fideId) async {
  if (fideId.isEmpty) return null;
  return FidePhotoService.getPhotoUrlOrNull(fideId);
});

class _PlayerPhotoOverlay extends ConsumerWidget {
  const _PlayerPhotoOverlay({required this.player, this.isCompact = false});

  final GamebasePlayer player;
  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoUrlAsync = ref.watch(
      _twicPlayerPhotoUrlProvider(player.fideId.trim()),
    );

    return Positioned(
      right: isCompact ? -15.sp : -20.sp,
      top: isCompact ? -8.sp : -10.sp,
      bottom: isCompact ? -8.sp : -10.sp,
      child: photoUrlAsync.when(
        data: (photoUrl) {
          if (photoUrl == null) return _buildPlaceholder(context);
          return AspectRatio(
            aspectRatio: 0.8,
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [
                  Colors.white,
                  Colors.white.withValues(alpha: 0.85),
                  Colors.white.withValues(alpha: 0.3),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.25, 0.55, 1.0],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: CachedNetworkImage(
                imageUrl: photoUrl,
                fit: BoxFit.cover,
                memCacheWidth:
                    (200 * MediaQuery.devicePixelRatioOf(context)).toInt(),
                placeholder: (_, _) => _buildPlaceholder(context),
                errorWidget: (_, _, _) => _buildPlaceholder(context),
              ),
            ),
          );
        },
        loading: () => _buildPlaceholder(context),
        error: (_, _) => _buildPlaceholder(context),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.8,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              context.colors.divider.withValues(alpha: 0.6),
              context.colors.divider.withValues(alpha: 0.2),
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.person_rounded,
            size: isCompact ? 32.sp : 48.sp,
            color: context.colors.iconSecondary,
          ),
        ),
      ),
    );
  }
}
