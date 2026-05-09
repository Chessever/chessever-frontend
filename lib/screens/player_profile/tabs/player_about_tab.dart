import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:motor/motor.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/string_utils.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/fullscreen_image_viewer.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:country_flags/country_flags.dart';
import 'package:heroine/heroine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Callback for updating game filters in a combinable way.
/// Each parameter is optional - only provided parameters are updated,
/// allowing multiple filters to be combined (e.g., Rapid + Win + specific opening).
typedef PlayerGamesOpenCallback =
    void Function({
      GameTimeControlFilter? timeControl,
      GameColorFilter? color,
      GameEcoFilter? eco,
      GameOnlineFilter? online,
      PlayerResultFilter? playerResultFilter,
      String? searchQuery,
    });

/// About tab showing comprehensive player information and analytics
class PlayerAboutTab extends ConsumerStatefulWidget {
  const PlayerAboutTab({
    super.key,
    this.fideId,
    required this.playerName,
    this.title,
    this.federation,
    this.fallbackRating,
    this.dataSource = PlayerProfileDataSource.supabase,
    this.gamebasePlayerId,
    this.onOpenGames,
  });

  final int? fideId;
  final String playerName;
  final String? title;
  final String? federation;
  final int? fallbackRating;
  final PlayerProfileDataSource dataSource;
  final String? gamebasePlayerId;
  final PlayerGamesOpenCallback? onOpenGames;

  @override
  ConsumerState<PlayerAboutTab> createState() => _PlayerAboutTabState();
}

class _PlayerAboutTabState extends ConsumerState<PlayerAboutTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  GameFilter? _previousFilter;
  double _filterFlashValue = 0.0;

  // Cached TWIC analytics — kept across filter changes so we never show a
  // full-page skeleton when the user adjusts a filter. The thin loading bar
  // in the parent screen already signals the in-flight request.
  PlayerAnalytics? _cachedBaseStats;
  PlayerAnalytics? _cachedOpeningStats;
  PlayerAnalytics? _cachedFilteredStats;

  /// Get the player profile key for provider lookups
  PlayerProfileKey get _playerKey => PlayerProfileKey(
    fideId: widget.fideId,
    playerName: widget.playerName,
    source: widget.dataSource,
    gamebasePlayerId: widget.gamebasePlayerId,
  );

  void _triggerFilterFlash() {
    setState(() => _filterFlashValue = 1.0);
    // Let motor handle the spring back to 0
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        setState(() => _filterFlashValue = 0.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Watch filter state and trigger animation on change
    final gamesState = ref.watch(playerProfileGamesKeyProvider(_playerKey));
    final currentFilter = gamesState.filter;
    final hasActiveFilter = currentFilter.hasActiveFilters;

    // Trigger flash animation when any filter changes
    if (_previousFilter != null && _previousFilter != currentFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerFilterFlash();
      });
    }
    _previousFilter = currentFilter;

    final profileDataAsync = ref.watch(
      playerProfileDataKeyProvider(_playerKey),
    );
    final canUseTwicStats = widget.dataSource == PlayerProfileDataSource.twic;
    // Supabase path still uses prefetched games for analytics; TWIC uses backend stats.
    final gamesAsync =
        canUseTwicStats
            ? const AsyncValue<List<GamesTourModel>>.data([])
            : ref.watch(playerGamesDataKeyProvider(_playerKey));
    final twicBaseStatsAsync =
        canUseTwicStats
            ? ref.watch(
              twicPlayerStatsProvider(
                TwicPlayerStatsRequest(
                  playerKey: _playerKey,
                  scope: TwicStatsScope.allGames,
                ),
              ),
            )
            : const AsyncValue<PlayerAnalytics?>.data(null);
    final twicOpeningStatsAsync =
        canUseTwicStats
            ? ref.watch(
              twicPlayerStatsProvider(
                TwicPlayerStatsRequest(
                  playerKey: _playerKey,
                  scope: TwicStatsScope.filteredIgnoringEco,
                ),
              ),
            )
            : const AsyncValue<PlayerAnalytics?>.data(null);
    final twicFilteredStatsAsync =
        canUseTwicStats
            ? ref.watch(
              twicPlayerStatsProvider(
                TwicPlayerStatsRequest(
                  playerKey: _playerKey,
                  scope: TwicStatsScope.filtered,
                ),
              ),
            )
            : const AsyncValue<PlayerAnalytics?>.data(null);

    // Keep caches fresh so filter changes never blank the screen.
    if (canUseTwicStats) {
      final bv = twicBaseStatsAsync.valueOrNull;
      if (bv != null) _cachedBaseStats = bv;
      final ov = twicOpeningStatsAsync.valueOrNull;
      if (ov != null) _cachedOpeningStats = ov;
      final fv = twicFilteredStatsAsync.valueOrNull;
      if (fv != null) _cachedFilteredStats = fv;
    }

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );

    Widget content = RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(playerProfileDataKeyProvider(_playerKey));
        ref.invalidate(playerGamesDataKeyProvider(_playerKey));
        if (canUseTwicStats) {
          ref.invalidate(
            twicPlayerStatsProvider(
              TwicPlayerStatsRequest(
                playerKey: _playerKey,
                scope: TwicStatsScope.allGames,
              ),
            ),
          );
          ref.invalidate(
            twicPlayerStatsProvider(
              TwicPlayerStatsRequest(
                playerKey: _playerKey,
                scope: TwicStatsScope.filteredIgnoringEco,
              ),
            ),
          );
          ref.invalidate(
            twicPlayerStatsProvider(
              TwicPlayerStatsRequest(
                playerKey: _playerKey,
                scope: TwicStatsScope.filtered,
              ),
            ),
          );
        }
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 16.h,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Player header with photo and ratings
            _PlayerHeaderSection(
              fideId: widget.fideId,
              playerName: widget.playerName,
              title: widget.title,
              federation: widget.federation,
              profileData: profileDataAsync.valueOrNull,
              fallbackRating: widget.fallbackRating,
              dataSource: widget.dataSource,
              gamebasePlayerId: widget.gamebasePlayerId,
              onOpenGames: widget.onOpenGames,
            ),

            SizedBox(height: 24.h),

            // Analytics section
            canUseTwicStats
                ? _buildTwicAnalyticsSection(
                  gamesState: gamesState,
                  currentFilter: currentFilter,
                  hasActiveFilter: hasActiveFilter,
                  twicBaseStatsAsync: twicBaseStatsAsync,
                  twicOpeningStatsAsync: twicOpeningStatsAsync,
                  twicFilteredStatsAsync: twicFilteredStatsAsync,
                  cachedBase: _cachedBaseStats,
                  cachedOpening: _cachedOpeningStats,
                  cachedFiltered: _cachedFilteredStats,
                )
                : gamesAsync.when(
                  data: (allGames) {
                    if (allGames.isEmpty) {
                      return _buildNoGamesMessage();
                    }

                    // Base analytics from ALL games (stable list for opening repertoire)
                    final baseAnalyticsRequest = PlayerAnalyticsRequest(
                      fideId: widget.fideId,
                      playerName: widget.playerName,
                      games: allGames,
                    );
                    final baseOpeningAnalytics = ref.watch(
                      playerAnalyticsProvider(baseAnalyticsRequest),
                    );

                    // Filter for opening repertoire: exclude ECO filter (you SELECT from this list)
                    final filterForOpenings = currentFilter.copyWith(
                      eco: GameEcoFilter.all,
                    );
                    final effectiveFilterForOpenings =
                        playerProfileEffectiveFilter(filterForOpenings);
                    final gamesForOpenings =
                        playerProfileHasStructuredFilters(filterForOpenings)
                            ? GameFilterHelper.applyFilter(
                              allGames,
                              effectiveFilterForOpenings,
                            )
                            : allGames;

                    // Filter for other stats: use full filter including ECO
                    final effectiveCurrentFilter = playerProfileEffectiveFilter(
                      currentFilter,
                    );
                    final filteredGames =
                        playerProfileHasStructuredFilters(currentFilter)
                            ? GameFilterHelper.applyFilter(
                              allGames,
                              effectiveCurrentFilter,
                            )
                            : allGames;

                    // Show empty state if no games match filter (but only for non-ECO filters)
                    if (gamesForOpenings.isEmpty &&
                        playerProfileHasStructuredFilters(filterForOpenings)) {
                      return _buildNoGamesForFilterMessage(filterForOpenings);
                    }

                    // Analytics for opening repertoire (without ECO filter) - used to determine active openings
                    final openingAnalyticsRequest = PlayerAnalyticsRequest(
                      fideId: widget.fideId,
                      playerName: widget.playerName,
                      games: gamesForOpenings,
                    );
                    final openingAnalytics = ref.watch(
                      playerAnalyticsProvider(openingAnalyticsRequest),
                    );

                    // Analytics for other stats (with full filter)
                    final analyticsRequest = PlayerAnalyticsRequest(
                      fideId: widget.fideId,
                      playerName: widget.playerName,
                      games: filteredGames,
                    );
                    final analytics = ref.watch(
                      playerAnalyticsProvider(analyticsRequest),
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Filter active indicator — AnimatedSize prevents scroll jump
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          alignment: Alignment.topCenter,
                          clipBehavior: Clip.hardEdge,
                          child:
                              hasActiveFilter
                                  ? Padding(
                                    padding: EdgeInsets.only(bottom: 16.h),
                                    child: _FilterActiveBanner(
                                      filter: currentFilter,
                                      totalGames: allGames.length,
                                      filteredGames: filteredGames.length,
                                      showFormat:
                                          widget.dataSource ==
                                          PlayerProfileDataSource.twic,
                                    ),
                                  )
                                  : const SizedBox.shrink(),
                        ),

                        // Overall statistics
                        _OverallStatsSection(
                          resultStats: analytics.resultStats,
                          avgOpponentRating: analytics.avgOpponentRating,
                          currentResultFilter: gamesState.playerResultFilter,
                          onOpenGames: widget.onOpenGames,
                        ),

                        SizedBox(height: 24.h),

                        // Color performance
                        _ColorPerformanceSection(
                          colorStats: analytics.colorStats,
                          currentColorFilter: gamesState.filter.color,
                          onOpenGames: widget.onOpenGames,
                        ),

                        SizedBox(height: 24.h),

                        // Recent form
                        if (analytics.recentForm.isNotEmpty) ...[
                          _RecentFormSection(
                            form: analytics.recentForm,
                            recentGames: _getRecentCompletedGames(
                              filteredGames,
                              widget.fideId,
                              widget.playerName,
                            ),
                            onOpenGames: widget.onOpenGames,
                          ),
                          SizedBox(height: 24.h),
                        ],

                        // Opening repertoire - base stats for stable list, filtered for active/inactive
                        if (baseOpeningAnalytics.openingStats.isNotEmpty)
                          _OpeningRepertoireSection(
                            baseOpeningStats: baseOpeningAnalytics.openingStats,
                            baseOpeningStatsWhite:
                                baseOpeningAnalytics.openingStatsWhite,
                            baseOpeningStatsBlack:
                                baseOpeningAnalytics.openingStatsBlack,
                            filteredOpeningStats: openingAnalytics.openingStats,
                            filteredOpeningStatsWhite:
                                openingAnalytics.openingStatsWhite,
                            filteredOpeningStatsBlack:
                                openingAnalytics.openingStatsBlack,
                            hasNonEcoFilters:
                                filterForOpenings.hasActiveFilters,
                            playerKey: _playerKey,
                            onOpenGames: widget.onOpenGames,
                          ),

                        SizedBox(height: 24.h),
                      ],
                    );
                  },
                  loading: () => _buildLoadingAnalytics(),
                  error: (error, _) => _buildErrorMessage(error.toString()),
                ),
          ],
        ),
      ),
    );

    // Apply tablet max-width constraint
    if (ResponsiveHelper.isTablet) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: content,
        ),
      );
    }

    // Wrap with motor-powered filter flash overlay
    return Stack(
      children: [
        // Main content with subtle scale when filter active
        SingleMotionBuilder(
          motion: const CupertinoMotion.smooth(),
          value: hasActiveFilter ? 1.0 : 0.0,
          builder: (context, filterProgress, _) {
            return content;
          },
        ),
        // Filter flash overlay - elegant wave effect
        SingleMotionBuilder(
          motion: const CupertinoMotion.bouncy(),
          value: _filterFlashValue,
          builder: (context, flashValue, _) {
            if (flashValue < 0.01) {
              return const SizedBox.shrink();
            }

            // Wave effect - flash sweeps down then fades
            final waveProgress = flashValue;
            final opacity = waveProgress * 0.35;

            return Positioned.fill(
              child: IgnorePointer(
                child: ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 1.0),
                        Colors.white.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                      stops: [
                        0.0,
                        0.3 + (waveProgress * 0.2),
                        0.5 + (waveProgress * 0.3),
                      ],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          kPrimaryColor.withValues(alpha: opacity),
                          kPrimaryColor.withValues(alpha: opacity * 0.7),
                          kPrimaryColor.withValues(alpha: opacity * 0.3),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNoGamesMessage() {
    return Container(
      padding: EdgeInsets.all(24.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        children: [
          Icon(
            Icons.sports_esports_outlined,
            size: 48.ic,
            color: context.colors.textPrimary.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No games found',
            style: AppTypography.textMdMedium.copyWith(color: context.colors.textPrimary),
          ),
          SizedBox(height: 4.h),
          Text(
            'Analytics will appear when games are available',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildNoGamesForFilterMessage(GameFilter filter) {
    const filterRedColor = Color(0xFFEF4444);

    // Build filter description
    final parts = <String>[];
    if (filter.timeControl != GameTimeControlFilter.all) {
      parts.add(filter.timeControl.displayText);
    }
    if (filter.color != GameColorFilter.all) {
      parts.add(filter.color == GameColorFilter.white ? 'White' : 'Black');
    }
    if (!filter.eco.isAll) {
      parts.add(filter.eco.code ?? 'this opening');
    }
    final filterName = parts.isNotEmpty ? parts.join(' + ') : 'matching';

    return Container(
      padding: EdgeInsets.all(24.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        children: [
          Icon(
            Icons.filter_alt_outlined,
            size: 48.ic,
            color: filterRedColor.withValues(alpha: 0.6),
          ),
          SizedBox(height: 12.h),
          Text(
            'No $filterName games',
            style: AppTypography.textMdMedium.copyWith(color: context.colors.textPrimary),
          ),
          SizedBox(height: 4.h),
          Text(
            'No games match the current filters.\nTap filter cards again to clear them.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildLoadingAnalytics() {
    return Column(
          children: List.generate(
            3,
            (index) => Container(
              margin: EdgeInsets.only(bottom: 16.h),
              height: 120.h,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
          ),
        )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1500.ms, color: context.colors.textPrimary.withValues(alpha: 0.1));
  }

  Widget _buildErrorMessage(String error) {
    return Container(
      padding: EdgeInsets.all(24.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline,
            size: 48.ic,
            color: Colors.redAccent.withValues(alpha: 0.7),
          ),
          SizedBox(height: 12.h),
          Text(
            'Failed to load analytics',
            style: AppTypography.textMdMedium.copyWith(color: context.colors.textPrimary),
          ),
          SizedBox(height: 4.h),
          Text(
            error,
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTwicAnalyticsSection({
    required PlayerProfileGamesState gamesState,
    required GameFilter currentFilter,
    required bool hasActiveFilter,
    required AsyncValue<PlayerAnalytics?> twicBaseStatsAsync,
    required AsyncValue<PlayerAnalytics?> twicOpeningStatsAsync,
    required AsyncValue<PlayerAnalytics?> twicFilteredStatsAsync,
    required PlayerAnalytics? cachedBase,
    required PlayerAnalytics? cachedOpening,
    required PlayerAnalytics? cachedFiltered,
  }) {
    // Fall back to the last cached value while a new request is in-flight so
    // we never blank the screen on a filter change. The thin loading bar in
    // the parent already signals the pending request to the user.
    final baseAnalytics = twicBaseStatsAsync.valueOrNull ?? cachedBase;
    final openingAnalytics = twicOpeningStatsAsync.valueOrNull ?? cachedOpening;
    final analytics = twicFilteredStatsAsync.valueOrNull ?? cachedFiltered;

    final anyStatsLoading =
        twicBaseStatsAsync.isLoading ||
        twicOpeningStatsAsync.isLoading ||
        twicFilteredStatsAsync.isLoading;
    final statsError =
        twicBaseStatsAsync.error ??
        twicOpeningStatsAsync.error ??
        twicFilteredStatsAsync.error;

    final allStatsMissing =
        baseAnalytics == null && openingAnalytics == null && analytics == null;
    final allScopesResolvedToValue =
        twicBaseStatsAsync.hasValue &&
        twicOpeningStatsAsync.hasValue &&
        twicFilteredStatsAsync.hasValue;

    // Only show the full skeleton on the very first load (no cached data yet).
    if (anyStatsLoading && allStatsMissing) {
      return _buildLoadingAnalytics();
    }

    // Prevent "No games found" flicker while scope providers are still resolving.
    if (allStatsMissing && !allScopesResolvedToValue && statsError == null) {
      return _buildLoadingAnalytics();
    }

    if (statsError != null &&
        baseAnalytics == null &&
        openingAnalytics == null &&
        analytics == null) {
      return _buildErrorMessage(statsError.toString());
    }

    final base = baseAnalytics ?? analytics ?? openingAnalytics;
    final opening = openingAnalytics ?? analytics ?? baseAnalytics;
    final filtered = analytics ?? openingAnalytics ?? baseAnalytics;

    if (base == null || opening == null || filtered == null) {
      return _buildNoGamesMessage();
    }

    final filterForOpenings = currentFilter.copyWith(eco: GameEcoFilter.all);
    final filteredGames = gamesState.filteredGames;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child:
              hasActiveFilter
                  ? Padding(
                    padding: EdgeInsets.only(bottom: 16.h),
                    child: _FilterActiveBanner(
                      filter: currentFilter,
                      totalGames: base.resultStats.totalGames,
                      filteredGames: filtered.resultStats.totalGames,
                      showFormat: true,
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
        _OverallStatsSection(
          resultStats: base.resultStats,
          avgOpponentRating: base.avgOpponentRating,
          currentResultFilter: gamesState.playerResultFilter,
          onOpenGames: widget.onOpenGames,
        ),
        SizedBox(height: 24.h),
        _ColorPerformanceSection(
          colorStats: base.colorStats,
          currentColorFilter: gamesState.filter.color,
          onOpenGames: widget.onOpenGames,
        ),
        SizedBox(height: 24.h),
        if (filtered.recentForm.isNotEmpty && filteredGames.isNotEmpty) ...[
          _RecentFormSection(
            form: filtered.recentForm,
            recentGames: _getRecentCompletedGames(
              filteredGames,
              widget.fideId,
              widget.playerName,
            ),
            onOpenGames: widget.onOpenGames,
          ),
          SizedBox(height: 24.h),
        ],
        if (base.openingStats.isNotEmpty)
          _OpeningRepertoireSection(
            baseOpeningStats: base.openingStats,
            baseOpeningStatsWhite: base.openingStatsWhite,
            baseOpeningStatsBlack: base.openingStatsBlack,
            filteredOpeningStats: opening.openingStats,
            filteredOpeningStatsWhite: opening.openingStatsWhite,
            filteredOpeningStatsBlack: opening.openingStatsBlack,
            hasNonEcoFilters: filterForOpenings.hasActiveFilters,
            playerKey: _playerKey,
            onOpenGames: widget.onOpenGames,
          ),
        SizedBox(height: 24.h),
      ],
    );
  }
}

/// Get the recent completed games for a player (matches the recent form)
List<GamesTourModel> _getRecentCompletedGames(
  List<GamesTourModel> games,
  int? targetFideId,
  String targetPlayerName,
) {
  final normalizedTargetName = _normalizeName(targetPlayerName);
  final completedGames = <GamesTourModel>[];

  for (final game in games) {
    // Determine if target player is in this game
    bool isTargetWhite = game.whitePlayer.fideId == targetFideId;
    bool isTargetBlack = game.blackPlayer.fideId == targetFideId;

    // If fideId matching failed, try name matching
    if (!isTargetWhite && !isTargetBlack) {
      final whiteNameNormalized = _normalizeName(game.whitePlayer.name);
      final blackNameNormalized = _normalizeName(game.blackPlayer.name);
      isTargetWhite = whiteNameNormalized == normalizedTargetName;
      isTargetBlack = blackNameNormalized == normalizedTargetName;
    }

    if (!isTargetWhite && !isTargetBlack) continue;

    // Only include completed games
    final isWhiteWin = game.gameStatus == GameStatus.whiteWins;
    final isBlackWin = game.gameStatus == GameStatus.blackWins;
    final isDraw = game.gameStatus == GameStatus.draw;
    final isCompleted = isWhiteWin || isBlackWin || isDraw;

    if (isCompleted) {
      completedGames.add(game);
      if (completedGames.length >= 10) break;
    }
  }

  return completedGames;
}

/// Normalize player name for comparison
String _normalizeName(String name) {
  final trimmed = name.trim().toLowerCase();
  if (trimmed.contains(',')) {
    final parts = trimmed.split(',');
    if (parts.length >= 2) {
      return '${parts[1].trim()} ${parts[0].trim()}';
    }
  }
  return trimmed;
}

/// Filter active banner showing which time control filter is applied
class _FilterActiveBanner extends StatelessWidget {
  const _FilterActiveBanner({
    required this.filter,
    required this.totalGames,
    required this.filteredGames,
    this.showFormat = true,
  });

  final GameFilter filter;
  final int totalGames;
  final int filteredGames;
  final bool showFormat;

  static const _filterRedColor = Color(0xFFEF4444);

  String _buildFilterDescription() {
    final parts = <String>[];

    if (filter.timeControl != GameTimeControlFilter.all) {
      parts.add(filter.timeControl.displayText);
    }
    if (filter.color != GameColorFilter.all) {
      parts.add(filter.color == GameColorFilter.white ? 'White' : 'Black');
    }
    if (showFormat && filter.online != GameOnlineFilter.all) {
      parts.add(filter.online.displayText);
    }
    if (!filter.eco.isAll) {
      parts.add(filter.eco.code ?? 'Opening');
    }

    if (parts.isEmpty) return 'Filtered games';
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: _filterRedColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10.br),
        border: Border.all(
          color: _filterRedColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8.w,
            height: 8.w,
            decoration: const BoxDecoration(
              color: _filterRedColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              _buildFilterDescription(),
              style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
            ),
          ),
          Text(
            '$filteredGames of $totalGames',
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Player header with photo and rating cards
class _PlayerHeaderSection extends ConsumerStatefulWidget {
  const _PlayerHeaderSection({
    this.fideId,
    required this.playerName,
    this.title,
    this.federation,
    this.profileData,
    this.fallbackRating,
    required this.dataSource,
    this.gamebasePlayerId,
    this.onOpenGames,
  });

  final int? fideId;
  final String playerName;
  final String? title;
  final String? federation;
  final PlayerProfileData? profileData;
  final int? fallbackRating;
  final PlayerProfileDataSource dataSource;
  final String? gamebasePlayerId;
  final PlayerGamesOpenCallback? onOpenGames;

  @override
  ConsumerState<_PlayerHeaderSection> createState() =>
      _PlayerHeaderSectionState();
}

class _PlayerHeaderSectionState extends ConsumerState<_PlayerHeaderSection> {
  Future<String?>? _photoFuture;

  @override
  void initState() {
    super.initState();
    // Only fetch photo if fideId is available
    if (widget.fideId != null) {
      _photoFuture = FidePhotoService.getPhotoUrlOrNull(
        widget.fideId.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = getPlayerInitials(widget.playerName);
    final effectiveFederation =
        (widget.profileData?.federation?.trim().isNotEmpty ?? false)
            ? widget.profileData!.federation!.trim()
            : (widget.federation?.trim() ?? '');
    final effectiveTitle =
        (widget.profileData?.title?.trim().isNotEmpty ?? false)
            ? widget.profileData!.title!.trim()
            : (widget.title?.trim() ?? '');
    final countryCode =
        effectiveFederation.isNotEmpty
            ? CountryUtils.toIso2Code(effectiveFederation)
            : '';
    final countryName =
        effectiveFederation.isNotEmpty
            ? CountryUtils.getCountryName(effectiveFederation)
            : '';

    // Use profile data ratings, fallback to the rating passed from search/navigation
    final classicalRating =
        widget.profileData?.classicalRating ?? widget.fallbackRating;
    final rapidRating = widget.profileData?.rapidRating;
    final blitzRating = widget.profileData?.blitzRating;

    // Get current time control filter to show selected state
    final playerKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
      source: widget.dataSource,
      gamebasePlayerId: widget.gamebasePlayerId,
    );
    final gamesState = ref.watch(playerProfileGamesKeyProvider(playerKey));
    final currentTimeControl = gamesState.filter.timeControl;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Player avatar
            _buildAvatar(initials, effectiveTitle),

            SizedBox(width: 16.w),

            // Rating cards
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _RatingCard(
                      icon: PngAsset.classicalIcon,
                      label: 'Classical',
                      rating: classicalRating,
                      isSelected:
                          currentTimeControl == GameTimeControlFilter.classical,
                      onTap: () {
                        // Toggle: if already selected, clear filter; otherwise apply
                        final newTimeControl =
                            currentTimeControl ==
                                    GameTimeControlFilter.classical
                                ? GameTimeControlFilter.all
                                : GameTimeControlFilter.classical;
                        widget.onOpenGames?.call(timeControl: newTimeControl);
                      },
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: _RatingCard(
                      icon: PngAsset.rapidIcon,
                      label: 'Rapid',
                      rating: rapidRating,
                      isSelected:
                          currentTimeControl == GameTimeControlFilter.rapid,
                      onTap: () {
                        // Toggle: if already selected, clear filter; otherwise apply
                        final newTimeControl =
                            currentTimeControl == GameTimeControlFilter.rapid
                                ? GameTimeControlFilter.all
                                : GameTimeControlFilter.rapid;
                        widget.onOpenGames?.call(timeControl: newTimeControl);
                      },
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: _RatingCard(
                      icon: PngAsset.blitzIcon,
                      label: 'Blitz',
                      rating: blitzRating,
                      isSelected:
                          currentTimeControl == GameTimeControlFilter.blitz,
                      onTap: () {
                        // Toggle: if already selected, clear filter; otherwise apply
                        final newTimeControl =
                            currentTimeControl == GameTimeControlFilter.blitz
                                ? GameTimeControlFilter.all
                                : GameTimeControlFilter.blitz;
                        widget.onOpenGames?.call(timeControl: newTimeControl);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        SizedBox(height: 16.h),

        // Player info row
        Container(
          padding: EdgeInsets.all(16.sp),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Row(
            children: [
              // Country
              if (countryCode.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(2.br),
                  child: CountryFlag.fromCountryCode(
countryCode,
  theme: ImageTheme(height: 20.h,
                    width: 28.w,),
),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        countryName.isNotEmpty
                            ? countryName
                            : effectiveFederation,
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                      Text(
                        'Federation',
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textPrimary.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // FIDE ID
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: context.colors.surfaceRecessed,
                  borderRadius: BorderRadius.circular(8.br),
                ),
                child: Column(
                  children: [
                    Text(
                      widget.fideId?.toString() ?? '-',
                      style: AppTypography.textSmBold.copyWith(
                        color: context.colors.textPrimary,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      'FIDE ID',
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textPrimary.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.02, end: 0);
  }

  Widget _buildAvatar(String initials, String effectiveTitle) {
    final heroTag =
        'player_avatar_profile_${widget.fideId ?? widget.playerName}';

    return FutureBuilder<String?>(
      future: _photoFuture,
      builder: (context, snapshot) {
        final photoUrl = snapshot.data;

        return GestureDetector(
          onTap: () {
            showPlayerAvatarFullscreen(
              context: context,
              photoUrl: photoUrl,
              initials: initials,
              heroTag: heroTag,
              title: effectiveTitle.isNotEmpty ? effectiveTitle : null,
            );
          },
          child: Heroine(
            tag: heroTag,
            motion: const CupertinoMotion.smooth(),
            flightShuttleBuilder: const FadeShuttleBuilder(),
            child: PlayerInitialsAvatar(
              photoUrl: photoUrl,
              initials: initials,
              size: 110.w,
              borderRadius: 12.br,
              title: effectiveTitle.isNotEmpty ? effectiveTitle : null,
            ),
          ),
        );
      },
    );
  }
}

/// Rating card widget with motor animations and selection state
/// Chess-themed: smooth like a piece sliding into position
class _RatingCard extends StatefulWidget {
  const _RatingCard({
    required this.icon,
    required this.label,
    this.rating,
    this.onTap,
    this.isSelected = false,
  });

  final String icon;
  final String label;
  final int? rating;
  final VoidCallback? onTap;
  final bool isSelected;

  @override
  State<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<_RatingCard> {
  double _pressScale = 1.0;

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap != null) {
      setState(() => _pressScale = 0.92);
    }
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _pressScale = 1.0);
  }

  void _onTapCancel() {
    setState(() => _pressScale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // Use motor for all animated properties
    return GestureDetector(
      onTapDown: widget.onTap != null ? _onTapDown : null,
      onTapUp: widget.onTap != null ? _onTapUp : null,
      onTapCancel: widget.onTap != null ? _onTapCancel : null,
      onTap: widget.onTap,
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _pressScale,
        builder: (context, pressScale, _) {
          return SingleMotionBuilder(
            // Bouncy spring for selection - like a chess piece settling
            motion: const CupertinoMotion.bouncy(),
            value: widget.isSelected ? 1.0 : 0.0,
            builder: (context, selectProgress, _) {
              // Interpolate colors based on selection progress
              final bgColor =
                  Color.lerp(
                    context.colors.surface,
                    kPrimaryColor.withValues(alpha: 0.18),
                    selectProgress,
                  )!;
              final borderColor =
                  Color.lerp(
                    Colors.transparent,
                    kPrimaryColor,
                    selectProgress,
                  )!;
              final labelColor =
                  Color.lerp(context.colors.textPrimaryMuted, kPrimaryColor, selectProgress)!;
              final ratingColor =
                  Color.lerp(context.colors.textPrimary, kPrimaryColor, selectProgress)!;

              // Subtle scale bump when selected
              final selectScale = 1.0 + (selectProgress * 0.03);
              final combinedScale = pressScale * selectScale;

              // Border width animates
              final borderWidth = 1.0 + (selectProgress * 0.5);

              return Transform.scale(
                scale: combinedScale,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8.sp,
                    vertical: 10.sp,
                  ),
                  height: 110.w,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10.br),
                    border: Border.all(color: borderColor, width: borderWidth),
                    // Subtle glow when selected
                    boxShadow:
                        selectProgress > 0.5
                            ? [
                              BoxShadow(
                                color: kPrimaryColor.withValues(
                                  alpha: 0.2 * selectProgress,
                                ),
                                blurRadius: 12 * selectProgress,
                                spreadRadius: 0,
                              ),
                            ]
                            : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Icon with color filter when selected
                      ColorFiltered(
                        colorFilter:
                            selectProgress > 0.5
                                ? ColorFilter.mode(
                                  kPrimaryColor.withValues(
                                    alpha: selectProgress * 0.3,
                                  ),
                                  BlendMode.srcATop,
                                )
                                : const ColorFilter.mode(
                                  Colors.transparent,
                                  BlendMode.dst,
                                ),
                        child: Image.asset(
                          widget.icon,
                          width: 20.w,
                          height: 20.h,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        widget.label,
                        style: AppTypography.textXsMedium.copyWith(
                          color: labelColor,
                          fontSize: 10.sp,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        widget.rating?.toString() ?? '-',
                        style: AppTypography.textLgBold.copyWith(
                          color: ratingColor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Overall statistics section
class _OverallStatsSection extends StatelessWidget {
  const _OverallStatsSection({
    required this.resultStats,
    required this.avgOpponentRating,
    required this.currentResultFilter,
    this.onOpenGames,
  });

  final ResultStatistics resultStats;
  final int avgOpponentRating;
  final PlayerResultFilter currentResultFilter;
  final PlayerGamesOpenCallback? onOpenGames;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overall Performance',
          style: AppTypography.textSmBold.copyWith(color: context.colors.textPrimary),
        ),
        SizedBox(height: 12.h),
        Container(
          padding: EdgeInsets.all(16.sp),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Column(
            children: [
              // Win/Draw/Loss percentages
              Row(
                children: [
                  _StatBox(
                    label: 'Win Rate',
                    value: '${(resultStats.winRate * 100).toStringAsFixed(1)}%',
                    color: kGreenColor,
                    isSelected: currentResultFilter == PlayerResultFilter.win,
                    onTap: () {
                      // Toggle: if already selected, clear filter; otherwise apply
                      final newFilter =
                          currentResultFilter == PlayerResultFilter.win
                              ? PlayerResultFilter.all
                              : PlayerResultFilter.win;
                      onOpenGames?.call(playerResultFilter: newFilter);
                    },
                  ),
                  SizedBox(width: 12.w),
                  _StatBox(
                    label: 'Draw Rate',
                    value:
                        '${(resultStats.drawRate * 100).toStringAsFixed(1)}%',
                    color: context.colors.textPrimaryMuted,
                    isSelected: currentResultFilter == PlayerResultFilter.draw,
                    onTap: () {
                      // Toggle: if already selected, clear filter; otherwise apply
                      final newFilter =
                          currentResultFilter == PlayerResultFilter.draw
                              ? PlayerResultFilter.all
                              : PlayerResultFilter.draw;
                      onOpenGames?.call(playerResultFilter: newFilter);
                    },
                  ),
                  SizedBox(width: 12.w),
                  _StatBox(
                    label: 'Loss Rate',
                    value:
                        '${(resultStats.lossRate * 100).toStringAsFixed(1)}%',
                    color: Colors.redAccent,
                    isSelected: currentResultFilter == PlayerResultFilter.loss,
                    onTap: () {
                      // Toggle: if already selected, clear filter; otherwise apply
                      final newFilter =
                          currentResultFilter == PlayerResultFilter.loss
                              ? PlayerResultFilter.all
                              : PlayerResultFilter.loss;
                      onOpenGames?.call(playerResultFilter: newFilter);
                    },
                  ),
                ],
              ),

              SizedBox(height: 16.h),

              // Win/Draw/Loss bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4.br),
                child: SizedBox(
                  height: 8.h,
                  child: Row(
                    children: [
                      Expanded(
                        flex: resultStats.wins,
                        child: Container(color: kGreenColor),
                      ),
                      if (resultStats.draws > 0)
                        Expanded(
                          flex: resultStats.draws,
                          child: Container(
                            color: context.colors.textPrimary.withValues(alpha: 0.5),
                          ),
                        ),
                      if (resultStats.losses > 0)
                        Expanded(
                          flex: resultStats.losses,
                          child: Container(color: Colors.redAccent),
                        ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 16.h),

              // Total games and avg opponent
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${resultStats.totalGames}',
                          style: AppTypography.textLgBold.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                        Text(
                          'Total Games',
                          style: AppTypography.textXsRegular.copyWith(
                            color: context.colors.textPrimary.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '${resultStats.wins}W / ${resultStats.draws}D / ${resultStats.losses}L',
                          style: AppTypography.textSmMedium.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                        Text(
                          'W / D / L',
                          style: AppTypography.textXsRegular.copyWith(
                            color: context.colors.textPrimary.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (avgOpponentRating > 0)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$avgOpponentRating',
                            style: AppTypography.textLgBold.copyWith(
                              color: context.colors.textPrimary,
                            ),
                          ),
                          Text(
                            'Avg. Opponent',
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.colors.textPrimary.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
  }
}

/// Stat box widget with selection state
class _StatBox extends StatefulWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
    this.isSelected = false,
    this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  State<_StatBox> createState() => _StatBoxState();
}

class _StatBoxState extends State<_StatBox> {
  double _pressScale = 1.0;

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap != null) {
      setState(() => _pressScale = 0.95);
    }
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _pressScale = 1.0);
  }

  void _onTapCancel() {
    setState(() => _pressScale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTapDown: widget.onTap != null ? _onTapDown : null,
        onTapUp: widget.onTap != null ? _onTapUp : null,
        onTapCancel: widget.onTap != null ? _onTapCancel : null,
        onTap: widget.onTap,
        child: SingleMotionBuilder(
          motion: const CupertinoMotion.snappy(),
          value: _pressScale,
          builder: (context, pressScale, _) {
            return SingleMotionBuilder(
              motion: const CupertinoMotion.bouncy(),
              value: widget.isSelected ? 1.0 : 0.0,
              builder: (context, selectProgress, _) {
                // Interpolate colors based on selection
                final bgColor =
                    Color.lerp(
                      widget.color.withValues(alpha: 0.15),
                      widget.color.withValues(alpha: 0.25),
                      selectProgress,
                    )!;
                final borderColor =
                    Color.lerp(
                      Colors.transparent,
                      widget.color,
                      selectProgress,
                    )!;

                // Subtle scale bump when selected
                final selectScale = 1.0 + (selectProgress * 0.02);
                final combinedScale = pressScale * selectScale;

                // Border width animates
                final borderWidth = selectProgress * 1.5;

                return Transform.scale(
                  scale: combinedScale,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8.br),
                      border:
                          borderWidth > 0
                              ? Border.all(
                                color: borderColor,
                                width: borderWidth,
                              )
                              : null,
                      // Subtle glow when selected
                      boxShadow:
                          selectProgress > 0.5
                              ? [
                                BoxShadow(
                                  color: widget.color.withValues(
                                    alpha: 0.2 * selectProgress,
                                  ),
                                  blurRadius: 8 * selectProgress,
                                  spreadRadius: 0,
                                ),
                              ]
                              : null,
                    ),
                    child: Column(
                      children: [
                        Text(
                          widget.value,
                          style: AppTypography.textMdBold.copyWith(
                            color: widget.color,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          widget.label,
                          style: AppTypography.textXsRegular.copyWith(
                            color: context.colors.textPrimary.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Color performance section
class _ColorPerformanceSection extends StatelessWidget {
  const _ColorPerformanceSection({
    required this.colorStats,
    required this.currentColorFilter,
    this.onOpenGames,
  });

  final ColorStatistics colorStats;
  final GameColorFilter currentColorFilter;
  final PlayerGamesOpenCallback? onOpenGames;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance by Color',
          style: AppTypography.textSmBold.copyWith(color: context.colors.textPrimary),
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            // White piece stats
            Expanded(
              child: _ColorStatCard(
                color: Colors.white,
                label: 'As White',
                games: colorStats.whiteGames,
                wins: colorStats.whiteWins,
                draws: colorStats.whiteDraws,
                losses: colorStats.whiteLosses,
                score: colorStats.whiteScore,
                isSelected: currentColorFilter == GameColorFilter.white,
                onTap: () {
                  // Toggle: if already selected, clear filter; otherwise apply
                  final newFilter =
                      currentColorFilter == GameColorFilter.white
                          ? GameColorFilter.all
                          : GameColorFilter.white;
                  // Clear opening filter when switching colors to avoid incompatible openings
                  // (e.g., can't have Black openings when filtering for White games)
                  final shouldClearOpening = newFilter != GameColorFilter.all;
                  onOpenGames?.call(
                    color: newFilter,
                    eco: shouldClearOpening ? GameEcoFilter.all : null,
                  );
                },
              ),
            ),
            SizedBox(width: 12.w),
            // Black piece stats
            Expanded(
              child: _ColorStatCard(
                color: Colors.black,
                label: 'As Black',
                games: colorStats.blackGames,
                wins: colorStats.blackWins,
                draws: colorStats.blackDraws,
                losses: colorStats.blackLosses,
                score: colorStats.blackScore,
                isSelected: currentColorFilter == GameColorFilter.black,
                onTap: () {
                  // Toggle: if already selected, clear filter; otherwise apply
                  final newFilter =
                      currentColorFilter == GameColorFilter.black
                          ? GameColorFilter.all
                          : GameColorFilter.black;
                  // Clear opening filter when switching colors to avoid incompatible openings
                  final shouldClearOpening = newFilter != GameColorFilter.all;
                  onOpenGames?.call(
                    color: newFilter,
                    eco: shouldClearOpening ? GameEcoFilter.all : null,
                  );
                },
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 200.ms);
  }
}

/// Color stat card with selection state
class _ColorStatCard extends StatefulWidget {
  const _ColorStatCard({
    required this.color,
    required this.label,
    required this.games,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.score,
    this.isSelected = false,
    this.onTap,
  });

  final Color color;
  final String label;
  final int games;
  final int wins;
  final int draws;
  final int losses;
  final double score;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  State<_ColorStatCard> createState() => _ColorStatCardState();
}

class _ColorStatCardState extends State<_ColorStatCard> {
  double _pressScale = 1.0;

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap != null) {
      setState(() => _pressScale = 0.96);
    }
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _pressScale = 1.0);
  }

  void _onTapCancel() {
    setState(() => _pressScale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // Determine accent color based on piece color
    final accentColor =
        widget.color == Colors.white ? kPrimaryColor : kPrimaryColor;

    return GestureDetector(
      onTapDown: widget.onTap != null ? _onTapDown : null,
      onTapUp: widget.onTap != null ? _onTapUp : null,
      onTapCancel: widget.onTap != null ? _onTapCancel : null,
      onTap: widget.onTap,
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _pressScale,
        builder: (context, pressScale, _) {
          return SingleMotionBuilder(
            motion: const CupertinoMotion.bouncy(),
            value: widget.isSelected ? 1.0 : 0.0,
            builder: (context, selectProgress, _) {
              // Interpolate colors based on selection
              final bgColor =
                  Color.lerp(
                    context.colors.surface,
                    accentColor.withValues(alpha: 0.12),
                    selectProgress,
                  )!;

              final defaultBorderColor = context.colors.textPrimary.withValues(alpha: 0.08);
              final selectedBorderColor = accentColor;
              final borderColor =
                  Color.lerp(
                    defaultBorderColor,
                    selectedBorderColor,
                    selectProgress,
                  )!;

              // Keep layout stable in two-column row while still animating press.
              final combinedScale = pressScale;

              // Border width animates
              final borderWidth = 1.0 + (selectProgress * 1.0);

              return Transform.scale(
                scale: combinedScale,
                child: Container(
                  padding: EdgeInsets.all(16.sp),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12.br),
                    border: Border.all(color: borderColor, width: borderWidth),
                    // Subtle glow when selected
                    boxShadow:
                        selectProgress > 0.5
                            ? [
                              BoxShadow(
                                color: accentColor.withValues(
                                  alpha: 0.15 * selectProgress,
                                ),
                                blurRadius: 10 * selectProgress,
                                spreadRadius: 0,
                              ),
                            ]
                            : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 20.w,
                            height: 20.w,
                            decoration: BoxDecoration(
                              color: widget.color,
                              borderRadius: BorderRadius.circular(4.br),
                              border: Border.all(
                                color:
                                    Color.lerp(
                                      context.colors.textPrimary.withValues(alpha: 0.3),
                                      accentColor,
                                      selectProgress,
                                    )!,
                                width: 1 + selectProgress,
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.textSmMedium.copyWith(
                                color: Color.lerp(
                                  context.colors.textPrimary,
                                  accentColor,
                                  selectProgress * 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        '${(widget.score * 100).toStringAsFixed(1)}%',
                        style: AppTypography.textXlBold.copyWith(
                          color: Color.lerp(
                            context.colors.textPrimary,
                            accentColor,
                            selectProgress * 0.3,
                          ),
                        ),
                      ),
                      Text(
                        'Score',
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textPrimary.withValues(alpha: 0.5),
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Wrap(
                        spacing: 6.w,
                        runSpacing: 4.h,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _WLDIndicator(
                            value: widget.wins,
                            type: 'W',
                            compact: true,
                          ),
                          _WLDIndicator(
                            value: widget.draws,
                            type: 'D',
                            compact: true,
                          ),
                          _WLDIndicator(
                            value: widget.losses,
                            type: 'L',
                            compact: true,
                          ),
                          Text(
                            '${widget.games} games',
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.colors.textPrimary.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Recent form section with expandable game cards
class _RecentFormSection extends StatefulWidget {
  const _RecentFormSection({
    required this.form,
    required this.recentGames,
    this.onOpenGames,
  });

  final List<double> form;
  final List<GamesTourModel> recentGames;
  final PlayerGamesOpenCallback? onOpenGames;

  @override
  State<_RecentFormSection> createState() => _RecentFormSectionState();
}

class _RecentFormSectionState extends State<_RecentFormSection> {
  int? _selectedIndex;

  void _onChipTapped(int index) {
    HapticFeedbackService.buttonPress();
    setState(() {
      if (_selectedIndex == index) {
        // Deselect if same chip tapped
        _selectedIndex = null;
      } else {
        _selectedIndex = index;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get the selected game if any
    final selectedGame =
        _selectedIndex != null && _selectedIndex! < widget.recentGames.length
            ? widget.recentGames[_selectedIndex!]
            : null;

    // Get event name for the selected game
    final eventName =
        selectedGame?.tourSlug != null
            ? StringUtils.slugToTitle(selectedGame!.tourSlug!)
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Form (Last ${widget.form.length} games)',
          style: AppTypography.textSmBold.copyWith(color: context.colors.textPrimary),
        ),
        SizedBox(height: 12.h),
        Container(
          padding: EdgeInsets.all(16.sp),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Column(
            children: [
              // W/D/L chips row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(widget.form.length, (index) {
                  final result = widget.form[index];
                  final isSelected = _selectedIndex == index;

                  Color bgColor;
                  String text;
                  if (result == 1.0) {
                    bgColor = kGreenColor;
                    text = 'W';
                  } else if (result == 0.5) {
                    bgColor = context.colors.textPrimary.withValues(alpha: 0.5);
                    text = 'D';
                  } else {
                    bgColor = Colors.redAccent;
                    text = 'L';
                  }

                  return _AnimatedFormChip(
                    text: text,
                    bgColor: bgColor,
                    isSelected: isSelected,
                    isDraw: result == 0.5,
                    onTap: () => _onChipTapped(index),
                  );
                }),
              ),

              // Expandable game card section
              _ExpandableGameCard(
                selectedGame: selectedGame,
                selectedIndex: _selectedIndex,
                allRecentGames: widget.recentGames,
                eventName: eventName,
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 300.ms);
  }
}

/// Animated form chip with motor-powered selection state
class _AnimatedFormChip extends StatefulWidget {
  const _AnimatedFormChip({
    required this.text,
    required this.bgColor,
    required this.isSelected,
    required this.isDraw,
    required this.onTap,
  });

  final String text;
  final Color bgColor;
  final bool isSelected;
  final bool isDraw;
  final VoidCallback onTap;

  @override
  State<_AnimatedFormChip> createState() => _AnimatedFormChipState();
}

class _AnimatedFormChipState extends State<_AnimatedFormChip> {
  double _pressScale = 1.0;

  void _onTapDown(TapDownDetails _) {
    setState(() => _pressScale = 0.85);
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _pressScale = 1.0);
    widget.onTap();
  }

  void _onTapCancel() {
    setState(() => _pressScale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _pressScale,
        builder: (context, pressScale, _) {
          return SingleMotionBuilder(
            motion: const CupertinoMotion.bouncy(),
            value: widget.isSelected ? 1.0 : 0.0,
            builder: (context, selectProgress, _) {
              // Selection scale and shadow
              final selectScale = 1.0 + (selectProgress * 0.15);
              final combinedScale = pressScale * selectScale;

              // Selection indicator glow
              final glowOpacity = selectProgress * 0.6;
              final borderWidth = selectProgress * 2.5;

              return Transform.scale(
                scale: combinedScale,
                child: Container(
                  width: 28.w,
                  height: 28.w,
                  decoration: BoxDecoration(
                    color: widget.bgColor,
                    borderRadius: BorderRadius.circular(6.br),
                    border:
                        borderWidth > 0
                            ? Border.all(
                              color: context.colors.textPrimary.withValues(
                                alpha: glowOpacity + 0.3,
                              ),
                              width: borderWidth,
                            )
                            : null,
                    boxShadow:
                        selectProgress > 0.1
                            ? [
                              BoxShadow(
                                color: widget.bgColor.withValues(
                                  alpha: 0.5 * selectProgress,
                                ),
                                blurRadius: 8 * selectProgress,
                                spreadRadius: 2 * selectProgress,
                              ),
                            ]
                            : null,
                  ),
                  child: Center(
                    child: Text(
                      widget.text,
                      style: AppTypography.textXsBold.copyWith(
                        color: widget.isDraw ? kBlackColor : context.colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Expandable game card with motor-powered height animation
class _ExpandableGameCard extends ConsumerWidget {
  const _ExpandableGameCard({
    required this.selectedGame,
    required this.selectedIndex,
    required this.allRecentGames,
    this.eventName,
  });

  final GamesTourModel? selectedGame;
  final int? selectedIndex;
  final List<GamesTourModel> allRecentGames;
  final String? eventName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpanded = selectedGame != null;

    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      value: isExpanded ? 1.0 : 0.0,
      builder: (context, expandProgress, _) {
        if (expandProgress < 0.01) {
          return const SizedBox.shrink();
        }

        // Calculate animated properties
        final opacity = expandProgress.clamp(0.0, 1.0);
        final scale = 0.9 + (0.1 * expandProgress);

        return Column(
          children: [
            // Animated spacing
            SizedBox(height: 16.h * expandProgress),

            // Divider with animated opacity
            Opacity(
              opacity: opacity,
              child: Container(
                height: 1,
                margin: EdgeInsets.only(bottom: 16.h * expandProgress),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      context.colors.divider.withValues(alpha: 0),
                      context.colors.divider.withValues(alpha: 0.5),
                      context.colors.divider.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),

            // Game card with scale and opacity animation
            Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child:
                    selectedGame != null
                        ? _buildTappableGameCard(
                          context,
                          ref,
                          selectedGame!,
                          eventName,
                        )
                        : const SizedBox.shrink(),
              ),
            ),

            // Hint text
            Opacity(
              opacity: opacity * 0.7,
              child: Padding(
                padding: EdgeInsets.only(top: 8.h * expandProgress),
                child: Text(
                  'Tap card to view full game',
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTappableGameCard(
    BuildContext context,
    WidgetRef ref,
    GamesTourModel game,
    String? eventName,
  ) {
    return TappableScale(
      scaleDown: 0.98,
      onTap: () {
        HapticFeedbackService.cardTap();
        // Navigate to chessboard
        ref
            .read(gameCardWrapperProvider)
            .navigateToChessBoard(
              context: context,
              orderedGames: allRecentGames,
              gameIndex: selectedIndex ?? 0,
              onReturnFromChessboard: null,
              viewSource: ChessboardView.playerProfile,
            );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.br),
        child: GamesTourGameCardBody(
          matchComparison: MatchWithComparison(
            game: game,
            comparison: MatchComparison.sameOrder,
          ),
          eventName: eventName,
          showClock: false,
        ),
      ),
    );
  }
}

enum _OpeningRepertoireFilter { all, white, black }

/// Opening repertoire section with selectable opening rows.
/// Uses base stats (from all games) for a stable card list,
/// and filtered stats to determine which openings are active/inactive.
class _OpeningRepertoireSection extends ConsumerStatefulWidget {
  const _OpeningRepertoireSection({
    required this.baseOpeningStats,
    required this.baseOpeningStatsWhite,
    required this.baseOpeningStatsBlack,
    required this.filteredOpeningStats,
    required this.filteredOpeningStatsWhite,
    required this.filteredOpeningStatsBlack,
    required this.hasNonEcoFilters,
    required this.playerKey,
    this.onOpenGames,
  });

  /// Base stats from ALL games - used for the stable card list
  final List<OpeningStatistic> baseOpeningStats;
  final List<OpeningStatistic> baseOpeningStatsWhite;
  final List<OpeningStatistic> baseOpeningStatsBlack;

  /// Filtered stats (non-ECO filters applied) - used to determine active/inactive
  final List<OpeningStatistic> filteredOpeningStats;
  final List<OpeningStatistic> filteredOpeningStatsWhite;
  final List<OpeningStatistic> filteredOpeningStatsBlack;

  /// Whether any non-ECO filters are currently active
  final bool hasNonEcoFilters;

  final PlayerProfileKey playerKey;
  final PlayerGamesOpenCallback? onOpenGames;

  @override
  ConsumerState<_OpeningRepertoireSection> createState() =>
      _OpeningRepertoireSectionState();
}

class _OpeningRepertoireSectionState
    extends ConsumerState<_OpeningRepertoireSection> {
  _OpeningRepertoireFilter _localFilter = _OpeningRepertoireFilter.all;

  /// Get the effective filter - synced with global color filter
  _OpeningRepertoireFilter get _effectiveFilter {
    final gamesState = ref.watch(
      playerProfileGamesKeyProvider(widget.playerKey),
    );
    final colorFilter = gamesState.filter.color;

    // Sync local filter with global color filter
    if (colorFilter == GameColorFilter.white) {
      return _OpeningRepertoireFilter.white;
    } else if (colorFilter == GameColorFilter.black) {
      return _OpeningRepertoireFilter.black;
    }
    // When global is "all", use local preference
    return _localFilter;
  }

  /// Base openings for stable card list (from all games)
  List<OpeningStatistic> get _baseOpenings {
    switch (_effectiveFilter) {
      case _OpeningRepertoireFilter.white:
        return widget.baseOpeningStatsWhite;
      case _OpeningRepertoireFilter.black:
        return widget.baseOpeningStatsBlack;
      case _OpeningRepertoireFilter.all:
        return widget.baseOpeningStats;
    }
  }

  /// Filtered openings (with non-ECO filters) - used to check active/inactive
  List<OpeningStatistic> get _filteredOpenings {
    switch (_effectiveFilter) {
      case _OpeningRepertoireFilter.white:
        return widget.filteredOpeningStatsWhite;
      case _OpeningRepertoireFilter.black:
        return widget.filteredOpeningStatsBlack;
      case _OpeningRepertoireFilter.all:
        return widget.filteredOpeningStats;
    }
  }

  /// Set of active ECO codes from filtered openings (fast lookup)
  Set<String> get _activeEcoCodes {
    return _filteredOpenings.map((o) => o.eco.toUpperCase()).toSet();
  }

  /// Check if an opening is active (has games matching current filters)
  bool _isOpeningActive(OpeningStatistic opening) {
    if (!widget.hasNonEcoFilters) return true;
    return _activeEcoCodes.contains(opening.eco.toUpperCase());
  }

  /// Check if an opening is currently selected based on ECO filter state
  bool _isOpeningSelected(OpeningStatistic opening) {
    final gamesState = ref.watch(
      playerProfileGamesKeyProvider(widget.playerKey),
    );
    final currentEco = gamesState.filter.eco.code;

    if (currentEco != null && currentEco.isNotEmpty) {
      return opening.eco.toUpperCase() == currentEco.toUpperCase();
    }

    return false;
  }

  void _onOpeningTapped(OpeningStatistic opening) {
    HapticFeedbackService.buttonPress();

    final isCurrentlySelected = _isOpeningSelected(opening);

    if (isCurrentlySelected) {
      // Deselect: clear just the eco filter
      widget.onOpenGames?.call(eco: GameEcoFilter.all);
    } else {
      // Select: apply the ECO filter only (no searchQuery — ECO is the unique key)
      final eco = opening.eco.trim();
      final hasEco = RegExp(r'^[A-E]').hasMatch(eco);

      // Also set matching color filter if selecting from White/Black tab
      GameColorFilter? colorToSet;
      if (_effectiveFilter == _OpeningRepertoireFilter.white) {
        colorToSet = GameColorFilter.white;
      } else if (_effectiveFilter == _OpeningRepertoireFilter.black) {
        colorToSet = GameColorFilter.black;
      }

      widget.onOpenGames?.call(
        eco: hasEco ? GameEcoFilter.forCode(eco) : null,
        color: colorToSet,
      );
    }
  }

  void _onLocalFilterChanged(_OpeningRepertoireFilter newFilter) {
    if (_localFilter == newFilter) return;

    HapticFeedbackService.buttonPress();
    setState(() => _localFilter = newFilter);

    // When user manually switches repertoire tab, also update global color filter
    // and clear any incompatible opening selection
    final gamesState = ref.read(
      playerProfileGamesKeyProvider(widget.playerKey),
    );
    final currentEco = gamesState.filter.eco.code;

    GameColorFilter? newColorFilter;
    bool shouldClearOpening = false;

    if (newFilter == _OpeningRepertoireFilter.white) {
      newColorFilter = GameColorFilter.white;
      // Check if current opening is compatible with White
      if (currentEco != null && currentEco.isNotEmpty) {
        final inWhite = widget.baseOpeningStatsWhite.any(
          (o) => o.eco.toUpperCase() == currentEco.toUpperCase(),
        );
        if (!inWhite) shouldClearOpening = true;
      }
    } else if (newFilter == _OpeningRepertoireFilter.black) {
      newColorFilter = GameColorFilter.black;
      // Check if current opening is compatible with Black
      if (currentEco != null && currentEco.isNotEmpty) {
        final inBlack = widget.baseOpeningStatsBlack.any(
          (o) => o.eco.toUpperCase() == currentEco.toUpperCase(),
        );
        if (!inBlack) shouldClearOpening = true;
      }
    } else {
      // "All" - clear color filter but keep opening
      newColorFilter = GameColorFilter.all;
    }

    widget.onOpenGames?.call(
      color: newColorFilter,
      eco: shouldClearOpening ? GameEcoFilter.all : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use base openings for stable list (never disappears)
    final topOpenings = _baseOpenings.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Opening Repertoire',
          style: AppTypography.textSmBold.copyWith(color: context.colors.textPrimary),
        ),
        SizedBox(height: 12.h),
        Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Filter chips inside the container
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
                child: Row(
                  children: [
                    _buildFilterChip(_OpeningRepertoireFilter.all, 'All'),
                    SizedBox(width: 8.w),
                    _buildFilterChip(_OpeningRepertoireFilter.white, 'White'),
                    SizedBox(width: 8.w),
                    _buildFilterChip(_OpeningRepertoireFilter.black, 'Black'),
                  ],
                ),
              ),
              // Divider between chips and list
              Divider(
                color: context.colors.divider,
                height: 1,
                indent: 16.w,
                endIndent: 16.w,
              ),
              // Repertoire list - always stable, inactive cards dimmed
              if (topOpenings.isEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 20.h),
                  child: Text(
                    _effectiveFilter == _OpeningRepertoireFilter.all
                        ? 'No openings found yet'
                        : 'No openings found for this color',
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.6),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: topOpenings.length,
                  separatorBuilder:
                      (_, __) => Divider(
                        color: context.colors.divider,
                        height: 1,
                        indent: 16.w,
                        endIndent: 16.w,
                      ),
                  itemBuilder: (context, index) {
                    final opening = topOpenings[index];
                    final isActive = _isOpeningActive(opening);
                    final isSelected = isActive && _isOpeningSelected(opening);
                    return _OpeningRow(
                      opening: opening,
                      isSelected: isSelected,
                      isActive: isActive,
                      onTap: isActive ? () => _onOpeningTapped(opening) : null,
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 400.ms);
  }

  Widget _buildFilterChip(_OpeningRepertoireFilter filter, String label) {
    final isSelected = _effectiveFilter == filter;
    final background =
        isSelected ? context.colors.textPrimary.withValues(alpha: 0.12) : context.colors.surface;
    final borderColor =
        isSelected
            ? context.colors.textPrimary.withValues(alpha: 0.6)
            : context.colors.divider.withValues(alpha: 0.6);
    final textColor =
        isSelected ? context.colors.textPrimary : context.colors.textPrimary.withValues(alpha: 0.6);

    return GestureDetector(
      onTap: () => _onLocalFilterChanged(filter),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16.br),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Text(
          label,
          style: AppTypography.textXsMedium.copyWith(color: textColor),
        ),
      ),
    );
  }
}

/// Opening row widget with motor-powered selection and active/inactive animations
class _OpeningRow extends StatefulWidget {
  const _OpeningRow({
    required this.opening,
    this.isSelected = false,
    this.isActive = true,
    this.onTap,
  });

  final OpeningStatistic opening;
  final bool isSelected;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  State<_OpeningRow> createState() => _OpeningRowState();
}

class _OpeningRowState extends State<_OpeningRow> {
  double _pressScale = 1.0;

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap != null) {
      setState(() => _pressScale = 0.97);
    }
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _pressScale = 1.0);
  }

  void _onTapCancel() {
    setState(() => _pressScale = 1.0);
  }

  Color _getEcoColor(String eco) {
    if (eco.isEmpty) return context.colors.surfaceRecessed;
    switch (eco[0].toUpperCase()) {
      case 'A':
        return const Color(0xFF4A90A4);
      case 'B':
        return const Color(0xFF8B4513);
      case 'C':
        return const Color(0xFF6B8E23);
      case 'D':
        return const Color(0xFF8B008B);
      case 'E':
        return const Color(0xFFB8860B);
      default:
        return context.colors.surfaceRecessed;
    }
  }

  Color _getScoreColor(double score) {
    if (score >= 0.6) return kGreenColor;
    if (score >= 0.4) return context.colors.textPrimary;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null ? _onTapDown : null,
      onTapUp: widget.onTap != null ? _onTapUp : null,
      onTapCancel: widget.onTap != null ? _onTapCancel : null,
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _pressScale,
        builder: (context, pressScale, _) {
          return SingleMotionBuilder(
            // Bouncy spring for selection - smooth like a chess piece settling
            motion: const CupertinoMotion.bouncy(),
            value: widget.isSelected ? 1.0 : 0.0,
            builder: (context, selectProgress, _) {
              // Third layer: active/inactive spring transition
              return SingleMotionBuilder(
                motion: const CupertinoMotion.bouncy(),
                value: widget.isActive ? 1.0 : 0.0,
                builder: (context, activeProgress, _) {
                  // Inactive state dims everything smoothly
                  // activeProgress: 1.0 = fully active, 0.0 = fully inactive
                  final inactiveAmount = 1.0 - activeProgress;

                  // Interpolate colors based on selection + active state
                  final bgColor =
                      Color.lerp(
                        Colors.transparent,
                        kPrimaryColor.withValues(alpha: 0.12),
                        selectProgress * activeProgress,
                      )!;

                  // Name color: white when active, dimmed when inactive
                  final activeNameColor =
                      Color.lerp(
                        context.colors.textPrimary,
                        kPrimaryColor,
                        selectProgress * 0.6,
                      )!;
                  final nameColor =
                      Color.lerp(
                        activeNameColor,
                        context.colors.textPrimary.withValues(alpha: 0.22),
                        inactiveAmount,
                      )!;

                  // ECO badge border for selection
                  final ecoBorderColor =
                      Color.lerp(
                        Colors.transparent,
                        kPrimaryColor,
                        selectProgress * activeProgress,
                      )!;
                  final ecoBorderWidth = selectProgress * activeProgress * 2.0;

                  // ECO badge color desaturates when inactive
                  final baseEcoColor = _getEcoColor(widget.opening.eco);
                  final ecoColor =
                      Color.lerp(
                        baseEcoColor,
                        context.colors.surfaceRecessed.withValues(alpha: 0.5),
                        inactiveAmount * 0.7,
                      )!;

                  // Score color dims when inactive
                  final baseScoreColor = _getScoreColor(widget.opening.score);
                  final activeScoreColor =
                      Color.lerp(
                        baseScoreColor,
                        kPrimaryColor,
                        selectProgress * 0.4,
                      )!;
                  final scoreColor =
                      Color.lerp(
                        activeScoreColor,
                        context.colors.textPrimary.withValues(alpha: 0.18),
                        inactiveAmount,
                      )!;

                  // Subtle text color for secondary elements
                  final secondaryTextAlpha =
                      0.4 * activeProgress + 0.12 * inactiveAmount;

                  // Scale: subtle selection bump only when active
                  final selectScale =
                      1.0 + (selectProgress * activeProgress * 0.01);
                  final combinedScale = pressScale * selectScale;

                  return Transform.scale(
                    scale: combinedScale,
                    child: Container(
                      decoration: BoxDecoration(
                        color: bgColor,
                        // Left border accent when selected
                        border:
                            selectProgress > 0.1 && activeProgress > 0.5
                                ? Border(
                                  left: BorderSide(
                                    color: kPrimaryColor.withValues(
                                      alpha: selectProgress * 0.8,
                                    ),
                                    width: 3 * selectProgress,
                                  ),
                                )
                                : null,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 12.h,
                        ),
                        child: Row(
                          children: [
                            // ECO code badge - desaturates when inactive
                            Container(
                              width: 42.w,
                              padding: EdgeInsets.symmetric(vertical: 4.h),
                              decoration: BoxDecoration(
                                color: ecoColor,
                                borderRadius: BorderRadius.circular(6.br),
                                border:
                                    ecoBorderWidth > 0
                                        ? Border.all(
                                          color: ecoBorderColor,
                                          width: ecoBorderWidth,
                                        )
                                        : null,
                                boxShadow:
                                    selectProgress > 0.5 && activeProgress > 0.5
                                        ? [
                                          BoxShadow(
                                            color: kPrimaryColor.withValues(
                                              alpha: 0.3 * selectProgress,
                                            ),
                                            blurRadius: 8 * selectProgress,
                                            spreadRadius: 0,
                                          ),
                                        ]
                                        : null,
                              ),
                              child: Text(
                                widget.opening.eco,
                                textAlign: TextAlign.center,
                                style: AppTypography.textXsBold.copyWith(
                                  color: Color.lerp(
                                    context.colors.textPrimary,
                                    context.colors.textPrimary.withValues(alpha: 0.35),
                                    inactiveAmount,
                                  ),
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),

                            SizedBox(width: 12.w),

                            // Opening name and stats
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.opening.openingName ??
                                        widget.opening.eco,
                                    style: AppTypography.textSmMedium.copyWith(
                                      color: nameColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: 4.h),
                                  Wrap(
                                    spacing: 4.w,
                                    runSpacing: 2.h,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      _WLDIndicator(
                                        value: widget.opening.wins,
                                        type: 'W',
                                        compact: true,
                                        dimAmount: inactiveAmount,
                                      ),
                                      _WLDIndicator(
                                        value: widget.opening.draws,
                                        type: 'D',
                                        compact: true,
                                        dimAmount: inactiveAmount,
                                      ),
                                      _WLDIndicator(
                                        value: widget.opening.losses,
                                        type: 'L',
                                        compact: true,
                                        dimAmount: inactiveAmount,
                                      ),
                                      SizedBox(width: 4.w),
                                      Text(
                                        '${widget.opening.count} games',
                                        style: AppTypography.textXsRegular
                                            .copyWith(
                                              color: context.colors.textPrimary.withValues(
                                                alpha: secondaryTextAlpha,
                                              ),
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Score percentage
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${(widget.opening.score * 100).toStringAsFixed(0)}%',
                                  style: AppTypography.textSmBold.copyWith(
                                    color: scoreColor,
                                  ),
                                ),
                                Text(
                                  'score',
                                  style: AppTypography.textXsRegular.copyWith(
                                    color: context.colors.textPrimary.withValues(
                                      alpha: secondaryTextAlpha,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Win/Loss/Draw indicator with color and optional dimming
class _WLDIndicator extends StatelessWidget {
  const _WLDIndicator({
    required this.value,
    required this.type,
    this.compact = false,
    this.dimAmount = 0.0,
  });

  final int value;
  final String type; // 'W', 'L', or 'D'
  final bool compact;
  final double dimAmount; // 0.0 = fully active, 1.0 = fully dimmed

  @override
  Widget build(BuildContext context) {
    Color baseBgColor;
    Color baseTextColor;

    switch (type) {
      case 'W':
        baseBgColor = kGreenColor.withValues(alpha: 0.2);
        baseTextColor = kGreenColor;
        break;
      case 'L':
        baseBgColor = Colors.redAccent.withValues(alpha: 0.2);
        baseTextColor = Colors.redAccent;
        break;
      case 'D':
      default:
        baseBgColor = context.colors.textPrimary.withValues(alpha: 0.15);
        baseTextColor = context.colors.textPrimary.withValues(alpha: 0.7);
        break;
    }

    // Dim colors when inactive
    final bgColor =
        Color.lerp(
          baseBgColor,
          context.colors.textPrimary.withValues(alpha: 0.05),
          dimAmount,
        )!;
    final textColor =
        Color.lerp(
          baseTextColor,
          context.colors.textPrimary.withValues(alpha: 0.2),
          dimAmount,
        )!;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6.w : 8.w,
        vertical: compact ? 2.h : 4.h,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4.br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            type,
            style: (compact
                    ? AppTypography.textXsBold
                    : AppTypography.textXsMedium)
                .copyWith(color: textColor),
          ),
          SizedBox(width: compact ? 2.w : 4.w),
          Text(
            value.toString(),
            style: (compact
                    ? AppTypography.textXsBold
                    : AppTypography.textXsMedium)
                .copyWith(color: textColor),
          ),
        ],
      ),
    );
  }
}
