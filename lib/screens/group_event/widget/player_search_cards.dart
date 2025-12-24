import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/repository/supabase/game/games.dart' show SearchPlayer;
import 'package:chessever2/screens/group_event/group_event_screen.dart' show searchTabQueryProvider;
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Maximum number of player cards to display
const int _maxPlayerCards = 4;

/// Provider that extracts the top searched players from search results (up to 4)
final topSearchedPlayersProvider = Provider.autoDispose<List<SearchPlayer>>((ref) {
  final searchQuery = ref.watch(searchTabQueryProvider);
  if (searchQuery.isEmpty) return [];

  final searchResults = ref.watch(supabaseCombinedSearchProvider(searchQuery));
  return searchResults.maybeWhen(
    data: (results) {
      if (results.playerResults.isEmpty) return [];
      // Return top players from search results (already sorted by relevance + ELO)
      // Deduplicate by name to avoid showing same player multiple times
      final seen = <String>{};
      final uniquePlayers = <SearchPlayer>[];
      for (final result in results.playerResults) {
        if (result.player == null) continue;
        final normalizedName = result.player!.name.toLowerCase().trim();
        if (!seen.contains(normalizedName)) {
          seen.add(normalizedName);
          uniquePlayers.add(result.player!);
          if (uniquePlayers.length >= _maxPlayerCards) break;
        }
      }
      return uniquePlayers;
    },
    orElse: () => [],
  );
});

/// Keep the old provider for backwards compatibility
final topSearchedPlayerProvider = Provider.autoDispose<SearchPlayer?>((ref) {
  final players = ref.watch(topSearchedPlayersProvider);
  return players.isNotEmpty ? players.first : null;
});

/// Player search cards displayed at the top of search results.
/// Shows up to 4 player cards in a grid layout with profile photos and country flags.
class PlayerSearchCards extends ConsumerWidget {
  const PlayerSearchCards({super.key, required this.searchQuery});

  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(topSearchedPlayersProvider);

    if (players.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 16.sp),
      child: _buildPlayerGrid(players),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05, end: 0);
  }

  Widget _buildPlayerGrid(List<SearchPlayer> players) {
    if (players.length == 1) {
      // Single player: full-width card
      return _PlayerSearchCard(player: players.first, isCompact: false);
    }

    if (players.length == 2) {
      // Two players: single row
      return Row(
        children: [
          Expanded(child: _PlayerSearchCard(player: players[0], isCompact: true)),
          SizedBox(width: 12.sp),
          Expanded(child: _PlayerSearchCard(player: players[1], isCompact: true)),
        ],
      );
    }

    // 3-4 players: 2x2 grid
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _PlayerSearchCard(player: players[0], isCompact: true)),
            SizedBox(width: 12.sp),
            Expanded(child: _PlayerSearchCard(player: players[1], isCompact: true)),
          ],
        ),
        SizedBox(height: 12.sp),
        Row(
          children: [
            Expanded(child: _PlayerSearchCard(player: players[2], isCompact: true)),
            SizedBox(width: 12.sp),
            if (players.length > 3)
              Expanded(child: _PlayerSearchCard(player: players[3], isCompact: true))
            else
              const Expanded(child: SizedBox()), // Empty space for 3 players
          ],
        ),
      ],
    );
  }
}

class _PlayerSearchCard extends ConsumerWidget {
  const _PlayerSearchCard({
    required this.player,
    this.isCompact = false,
  });

  final SearchPlayer player;
  final bool isCompact;

  void _navigateToProfile(BuildContext context) {
    // Navigate to player profile - works with or without fideId
    // Players without fideId will have games fetched by name instead
    HapticFeedbackService.buttonPress();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerProfileScreen(
          fideId: player.fideId,
          playerName: player.name,
          title: player.title,
          federation: player.fed,
          rating: player.rating,
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
          color: kWhiteColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.br),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Background: Country flag (full bleed, subtle)
            if (countryCode != null) _FlagBackground(countryCode: countryCode),

            // Player photo overlay (positioned on right side)
            _PlayerPhotoOverlay(player: player, isCompact: isCompact),

            // Gradient overlay for text readability
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [
                      Colors.transparent,
                      kBlack2Color.withValues(alpha: 0.5),
                      kBlack2Color.withValues(alpha: 0.85),
                      kBlack2Color.withValues(alpha: 0.95),
                    ],
                    stops: const [0.0, 0.25, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // Foreground content
            Padding(
              padding: EdgeInsets.all(isCompact ? 12.sp : 14.sp),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Title badge (GM, IM, etc)
                  if (player.title != null && player.title!.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(bottom: 4.sp),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 5.sp,
                          vertical: 2.sp,
                        ),
                        decoration: BoxDecoration(
                          color: _getTitleColor(player.title!),
                          borderRadius: BorderRadius.circular(4.br),
                        ),
                        child: Text(
                          player.title!,
                          style: AppTypography.textXsBold.copyWith(
                            color: kWhiteColor,
                            fontSize: isCompact ? 9.sp : 10.sp,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  // Player name
                  Text(
                    _formatPlayerName(player.name),
                    style: (isCompact ? AppTypography.textMdBold : AppTypography.textLgBold).copyWith(
                      color: kWhiteColor,
                      letterSpacing: 0.3,
                    ),
                    maxLines: isCompact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.sp),
                  // Subtitle: Rating + Country
                  Row(
                    children: [
                      // Small flag icon
                      if (countryCode != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2.br),
                          child: CountryFlag.fromCountryCode(
                            countryCode,
                            width: isCompact ? 14.sp : 16.sp,
                            height: isCompact ? 10.sp : 12.sp,
                          ),
                        ),
                        SizedBox(width: 5.sp),
                      ],
                      Expanded(
                        child: Text(
                          _buildSubtitle(),
                          style: AppTypography.textXsRegular.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.7),
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

    if (player.rating != null && player.rating! > 0) {
      parts.add('${player.rating}');
    }

    if (player.fed != null && player.fed!.isNotEmpty) {
      final countryName = CountryUtils.getCountryName(player.fed!);
      if (countryName.isNotEmpty) {
        parts.add(countryName);
      }
    }

    return parts.join(' \u2022 ');
  }

  String? _getIso2CountryCode() {
    if (player.fed == null || player.fed!.isEmpty) return null;
    return CountryUtils.toIso2Code(player.fed!);
  }

  String _formatPlayerName(String name) {
    // Handle "Lastname, Firstname" format
    if (name.contains(',')) {
      final parts = name.split(',');
      if (parts.length >= 2) {
        return '${parts[1].trim()} ${parts[0].trim()}';
      }
    }
    return name;
  }

  Color _getTitleColor(String title) {
    switch (title.toUpperCase()) {
      case 'GM':
        return const Color(0xFFD4AF37); // Gold
      case 'IM':
        return const Color(0xFFC0C0C0); // Silver
      case 'FM':
        return const Color(0xFFCD7F32); // Bronze
      case 'WGM':
        return const Color(0xFFE8B4B4); // Rose gold
      case 'WIM':
        return const Color(0xFFB4C4E8); // Light blue
      case 'WFM':
        return const Color(0xFFB4E8D4); // Light teal
      case 'CM':
        return const Color(0xFF8B9DC3); // Slate blue
      case 'WCM':
        return const Color(0xFFD4B4E8); // Light purple
      default:
        return kDarkGreyColor;
    }
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
          child: CountryFlag.fromCountryCode(
            countryCode,
            width: 300,
            height: 200,
          ),
        ),
      ),
    );
  }
}

/// Provider to cache player photo URLs
final _searchPlayerPhotoUrlProvider =
    FutureProvider.family.autoDispose<String?, int?>((ref, fideId) async {
  if (fideId == null) return null;
  return FidePhotoService.getPhotoUrlOrNull(fideId.toString());
});

/// Player photo overlay positioned on the right side of the card
class _PlayerPhotoOverlay extends ConsumerWidget {
  const _PlayerPhotoOverlay({
    required this.player,
    this.isCompact = false,
  });

  final SearchPlayer player;
  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoUrlAsync = ref.watch(_searchPlayerPhotoUrlProvider(player.fideId));

    return Positioned(
      right: isCompact ? -15.sp : -20.sp,
      top: isCompact ? -8.sp : -10.sp,
      bottom: isCompact ? -8.sp : -10.sp,
      child: photoUrlAsync.when(
        data: (photoUrl) {
          if (photoUrl == null) return _buildPlaceholder();
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
                placeholder: (_, __) => _buildPlaceholder(),
                errorWidget: (_, __, ___) => _buildPlaceholder(),
              ),
            ),
          );
        },
        loading: () => _buildPlaceholder(),
        error: (_, __) => _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return AspectRatio(
      aspectRatio: 0.8,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kWhiteColor.withValues(alpha: 0.06),
              kWhiteColor.withValues(alpha: 0.02),
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.person_rounded,
            size: isCompact ? 32.sp : 48.sp,
            color: kWhiteColor.withValues(alpha: 0.12),
          ),
        ),
      ),
    );
  }
}
