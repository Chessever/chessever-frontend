import 'dart:async';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/providers/player_backfill_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/tabs/player_about_tab.dart';
import 'package:chessever2/screens/player_profile/tabs/player_events_tab.dart';
import 'package:chessever2/screens/player_profile/tabs/player_games_tab.dart';
import 'package:chessever2/screens/player_profile/widgets/save_to_library_sheet.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Enum for player profile screen tabs
enum PlayerProfileTab { about, games, events }

/// Tab names for display
const playerProfileTabNames = {
  PlayerProfileTab.about: 'About',
  PlayerProfileTab.games: 'Games',
  PlayerProfileTab.events: 'Events',
};

/// Provider for selected tab
final selectedPlayerProfileTabProvider =
    StateProvider.autoDispose<PlayerProfileTab>(
      (ref) => PlayerProfileTab.about,
    );

/// Player profile screen showing detailed player information
/// with three tabs: About, Games, and Events.
class PlayerProfileScreen extends ConsumerStatefulWidget {
  const PlayerProfileScreen({
    super.key,
    this.fideId,
    required this.playerName,
    this.title,
    this.federation,
    this.rating,
    this.dataSource = PlayerProfileDataSource.supabase,
    this.gamebasePlayerId,
  });

  /// FIDE ID - can be null for players without official FIDE registration
  final int? fideId;
  final String playerName;
  final String? title;
  final String? federation;
  final int? rating;
  final PlayerProfileDataSource dataSource;
  final String? gamebasePlayerId;

  /// Create from SearchPlayer model
  factory PlayerProfileScreen.fromSearchPlayer(SearchPlayer player) {
    return PlayerProfileScreen(
      fideId: player.fideId,
      playerName: player.name,
      title: player.title,
      federation: player.fed,
      rating: player.rating,
      dataSource: PlayerProfileDataSource.supabase,
    );
  }

  @override
  ConsumerState<PlayerProfileScreen> createState() =>
      _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends ConsumerState<PlayerProfileScreen>
    with SingleTickerProviderStateMixin {
  static const String _startingFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  late PageController _pageController;
  late AnimationController _favoriteAnimationController;
  late Animation<double> _favoriteScaleAnimation;
  late PlayerProfileDataSource _currentDataSource;
  String? _currentGamebasePlayerId;
  bool _didPrefetchExplorerRoot = false;

  bool _showHeaderExtras = true;
  double _scrollAccumulator = 0.0;
  static const _scrollCollapseThreshold = 40.0;

  bool _handleScrollNotification(ScrollUpdateNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    final delta = notification.scrollDelta ?? 0.0;
    final offset = notification.metrics.pixels;

    if (offset <= 0) {
      if (!_showHeaderExtras) setState(() => _showHeaderExtras = true);
      _scrollAccumulator = 0.0;
      return false;
    }

    if ((delta > 0 && _scrollAccumulator < 0) ||
        (delta < 0 && _scrollAccumulator > 0)) {
      _scrollAccumulator = 0.0;
    }
    _scrollAccumulator += delta;

    if (_scrollAccumulator > _scrollCollapseThreshold && _showHeaderExtras) {
      setState(() => _showHeaderExtras = false);
    } else if (_scrollAccumulator < -_scrollCollapseThreshold &&
        !_showHeaderExtras) {
      setState(() => _showHeaderExtras = true);
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _currentDataSource = widget.dataSource;
    _currentGamebasePlayerId = _normalizePlayerId(widget.gamebasePlayerId);
    final initialTab = ref.read(selectedPlayerProfileTabProvider);
    _pageController = PageController(
      initialPage: PlayerProfileTab.values.indexOf(initialTab),
    );

    _favoriteAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _favoriteScaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(
        parent: _favoriteAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _favoriteAnimationController.dispose();
    super.dispose();
  }

  String? _normalizePlayerId(String? raw) {
    final id = raw?.trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  void _setDataSource(
    PlayerProfileDataSource source, {
    String? gamebasePlayerId,
  }) {
    if (_currentDataSource == source) return;
    HapticFeedbackService.light();
    setState(() {
      final normalizedId = _normalizePlayerId(gamebasePlayerId);
      if (normalizedId != null && normalizedId.isNotEmpty) {
        _currentGamebasePlayerId = normalizedId;
      }
      _currentDataSource = source;
    });
  }

  void _handleTabSelection(int index) {
    HapticFeedbackService.buttonPress();
    ref.read(selectedPlayerProfileTabProvider.notifier).state =
        PlayerProfileTab.values[index];
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handlePageChanged(int index) {
    final currentTab = ref.read(selectedPlayerProfileTabProvider);
    if (PlayerProfileTab.values.indexOf(currentTab) != index) {
      ref.read(selectedPlayerProfileTabProvider.notifier).state =
          PlayerProfileTab.values[index];
    }
  }

  /// Update filters in a combinable way.
  ///
  /// Filter logic:
  /// - Single filter is free for all users
  /// - Chaining 2+ filters requires premium subscription
  /// - If a filter property is provided (even if 'all'), it updates that property
  /// - Other filter properties are preserved
  Future<void> _openGames({
    GameTimeControlFilter? timeControl,
    GameColorFilter? color,
    GameEcoFilter? eco,
    PlayerResultFilter? playerResultFilter,
    String? searchQuery,
  }) async {
    HapticFeedbackService.buttonPress();
    final playerKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
      source: _currentDataSource,
      gamebasePlayerId: _currentGamebasePlayerId,
    );
    final currentState = ref.read(playerProfileGamesKeyProvider(playerKey));
    final notifier = ref.read(
      playerProfileGamesKeyProvider(playerKey).notifier,
    );

    // Compute what the resulting filter state would be after this merge
    final newFilter = currentState.filter.copyWith(
      timeControl: timeControl,
      color: color,
      eco: eco,
    );
    final newPlayerResult =
        playerResultFilter ?? currentState.playerResultFilter;
    final newSearchQuery = searchQuery ?? currentState.searchQuery;
    final newActiveCount =
        newFilter.activeFilterCount +
        (newPlayerResult != PlayerResultFilter.all ? 1 : 0) +
        (newSearchQuery.isNotEmpty ? 1 : 0);

    // Paywall: allow 1 filter free, require premium for chaining (2+)
    if (newActiveCount > 1) {
      final isPremium = ref.read(subscriptionProvider).isSubscribed;
      if (!isPremium) {
        final subscribed = await requirePremiumGuard(context, ref);
        if (!subscribed || !mounted) return;
      }
    }

    // Apply the filter
    notifier.mergeFilter(
      timeControl: timeControl,
      color: color,
      eco: eco,
      playerResultFilter: playerResultFilter,
      searchQuery: searchQuery,
    );
  }

  /// Resolve the gamebase player UUID from constructor or TWIC summary.
  String? _resolveGamebasePlayerId() {
    if (_currentGamebasePlayerId != null) return _currentGamebasePlayerId;
    final twicLookupKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
      source: PlayerProfileDataSource.supabase,
      gamebasePlayerId: _currentGamebasePlayerId,
    );
    return ref
        .read(twicProfileSummaryProvider(twicLookupKey))
        .valueOrNull
        ?.gamebasePlayerId;
  }

  PlayerGender _mapSexToGender(String? sex) {
    final normalized = sex?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return PlayerGender.male;
    if (normalized == 'f' || normalized.startsWith('female')) {
      return PlayerGender.female;
    }
    return PlayerGender.male;
  }

  GamebasePlayer _buildExplorerFallbackPlayer(String id) {
    final cached = ref.read(playerByIdProvider(id)).valueOrNull;
    if (cached != null) return cached;

    final activePlayerKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
      source: _currentDataSource,
      gamebasePlayerId: _currentGamebasePlayerId,
    );
    final activeProfile =
        ref.read(playerProfileDataKeyProvider(activePlayerKey)).valueOrNull;
    final fallbackChessPlayer =
        ref.read(chessPlayerByFideIdProvider(widget.fideId)).valueOrNull;

    final name =
        (activeProfile?.name.trim().isNotEmpty ?? false)
            ? activeProfile!.name.trim()
            : ((fallbackChessPlayer?.name.trim().isNotEmpty ?? false)
                ? fallbackChessPlayer!.name.trim()
                : widget.playerName);

    final fed =
        (activeProfile?.federation?.trim().isNotEmpty ?? false)
            ? activeProfile!.federation!.trim()
            : ((widget.federation?.trim().isNotEmpty ?? false)
                ? widget.federation!.trim()
                : (fallbackChessPlayer?.country?.trim() ?? ''));

    final fideId = widget.fideId?.toString() ?? '';

    final title =
        (activeProfile?.title?.trim().isNotEmpty ?? false)
            ? activeProfile!.title?.trim()
            : ((widget.title?.trim().isNotEmpty ?? false)
                ? widget.title?.trim()
                : fallbackChessPlayer?.title?.trim());

    return GamebasePlayer(
      id: id,
      fideId: fideId,
      name: name,
      gender: _mapSexToGender(activeProfile?.sex),
      fed: fed,
      title: title,
      ratingClassical: activeProfile?.classicalRating ?? widget.rating,
      ratingRapid: activeProfile?.rapidRating,
      ratingBlitz: activeProfile?.blitzRating,
    );
  }

  Future<void> _openExplorer() async {
    HapticFeedbackService.buttonPress();
    final uuid = _resolveGamebasePlayerId();
    if (uuid == null) return;

    _prefetchExplorerRootForPlayer(uuid);

    final initialPlayer = _buildExplorerFallbackPlayer(uuid);
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => GamebaseExplorerScreen.scoped(initialPlayer: initialPlayer),
      ),
    );

    // Warm/update cache in background without blocking navigation.
    unawaited(ref.read(playerByIdProvider(uuid).future));
  }

  void _prefetchExplorerRootForPlayer(String playerId) {
    if (_didPrefetchExplorerRoot) return;
    _didPrefetchExplorerRoot = true;

    unawaited(() async {
      try {
        await ref
            .read(gamebaseRepositoryProvider)
            .getMoveAggregates(fen: _startingFen, playerId: playerId);
      } catch (_) {
        // Best-effort prefetch only; never block UI on this path.
      }
    }());
  }

  Future<void> _toggleFavorite() async {
    final allowed = await requireFullAuthGuard(context);
    if (!allowed) return;

    HapticFeedbackService.buttonPress();

    final favoritesNotifier = ref.read(
      favoritePlayersNotifierProvider.notifier,
    );

    // Create a PlayerStandingModel for the favorites system
    final player = PlayerStandingModel(
      name: widget.playerName,
      countryCode: widget.federation ?? '',
      score: widget.rating ?? 0,
      scoreChange: 0,
      matchScore: null,
      fideId: widget.fideId,
      title: widget.title,
    );

    try {
      final isNowFavorite = await favoritesNotifier.toggleFavorite(player);
      if (isNowFavorite) {
        _favoriteAnimationController.forward().then(
          (_) => _favoriteAnimationController.reverse(),
        );
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update favorite. Please try again.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTab = ref.watch(selectedPlayerProfileTabProvider);
    final hasPlayerExplorer = _resolveGamebasePlayerId() != null;
    if (hasPlayerExplorer && !_didPrefetchExplorerRoot) {
      final playerId = _resolveGamebasePlayerId();
      if (playerId != null && playerId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _prefetchExplorerRootForPlayer(playerId);
        });
      }
    }

    final activePlayerKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
      source: _currentDataSource,
      gamebasePlayerId: _currentGamebasePlayerId,
    );
    final activeProfileAsync = ref.watch(
      playerProfileDataKeyProvider(activePlayerKey),
    );
    final activeProfile = activeProfileAsync.valueOrNull;
    final fallbackChessPlayer =
        ref.watch(chessPlayerByFideIdProvider(widget.fideId)).valueOrNull;
    final effectiveName =
        (activeProfile?.name.trim().isNotEmpty ?? false)
            ? activeProfile!.name
            : ((fallbackChessPlayer?.name.trim().isNotEmpty ?? false)
                ? fallbackChessPlayer!.name
                : widget.playerName);
    final effectiveTitle =
        (activeProfile?.title?.trim().isNotEmpty ?? false)
            ? activeProfile!.title
            : ((widget.title?.trim().isNotEmpty ?? false)
                ? widget.title
                : ((fallbackChessPlayer?.title?.trim().isNotEmpty ?? false)
                    ? fallbackChessPlayer!.title
                    : widget.title));
    final effectiveFederation =
        (activeProfile?.federation?.trim().isNotEmpty ?? false)
            ? activeProfile!.federation
            : ((widget.federation?.trim().isNotEmpty ?? false)
                ? widget.federation
                : ((fallbackChessPlayer?.country?.trim().isNotEmpty ?? false)
                    ? fallbackChessPlayer!.country
                    : widget.federation));
    final countryCode =
        effectiveFederation != null
            ? CountryUtils.toIso2Code(effectiveFederation)
            : '';
    final twicLookupKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
      source: PlayerProfileDataSource.supabase,
      gamebasePlayerId: _currentGamebasePlayerId,
    );
    // Always watch so the source selector stays visible in both modes.
    final twicSummaryAsync = ref.watch(
      twicProfileSummaryProvider(twicLookupKey),
    );

    // Watch favorites to show correct state
    final favoritesAsync = ref.watch(favoritePlayersNotifierProvider);
    final isFavorite = favoritesAsync.maybeWhen(
      data: (state) => state.players.any((p) => p.fideId == widget.fideId),
      orElse: () => false,
    );

    final playerKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
      source: _currentDataSource,
      gamebasePlayerId: _currentGamebasePlayerId,
    );
    final gamesState = ref.watch(playerProfileGamesKeyProvider(playerKey));
    final hasActiveFilter = gamesState.hasActiveFilters;
    final isTwicSource = _currentDataSource == PlayerProfileDataSource.twic;

    var isTwicStatsLoading = false;
    if (isTwicSource && selectedTab == PlayerProfileTab.about) {
      final allGamesStats = ref.watch(
        twicPlayerStatsProvider(
          TwicPlayerStatsRequest(
            playerKey: playerKey,
            scope: TwicStatsScope.allGames,
          ),
        ),
      );
      final openingStats = ref.watch(
        twicPlayerStatsProvider(
          TwicPlayerStatsRequest(
            playerKey: playerKey,
            scope: TwicStatsScope.filteredIgnoringEco,
          ),
        ),
      );
      final filteredStats = ref.watch(
        twicPlayerStatsProvider(
          TwicPlayerStatsRequest(
            playerKey: playerKey,
            scope: TwicStatsScope.filtered,
          ),
        ),
      );
      isTwicStatsLoading =
          allGamesStats.isLoading ||
          openingStats.isLoading ||
          filteredStats.isLoading;
    }
    final isTwicLoading =
        isTwicSource && (gamesState.isLoading || isTwicStatsLoading);

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.isTablet
                    ? ResponsiveHelper.contentMaxWidth
                    : double.infinity,
          ),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),

              // App bar
              _buildAppBar(
                context,
                countryCode,
                isFavorite,
                effectiveFederation: effectiveFederation,
                effectiveName: effectiveName,
                effectiveTitle: effectiveTitle,
              ),

              SizedBox(height: 8.h),

              // Tab switcher
              _buildTabSwitcher(selectedTab),

              // Filter/loading indicator bar — adjacent to tab
              _buildIndicatorBar(
                hasActiveFilter: hasActiveFilter,
                isTwicLoading: isTwicLoading,
              ),

              SingleMotionBuilder(
                motion: const CupertinoMotion.snappy(),
                value: _showHeaderExtras ? 1.0 : 0.0,
                builder: (context, progress, child) {
                  final clamped = progress.clamp(0.0, 1.0);
                  if (clamped == 0) return const SizedBox.shrink();
                  return ClipRect(
                    child: Align(
                      heightFactor: clamped,
                      alignment: Alignment.topCenter,
                      child: Opacity(opacity: clamped, child: child),
                    ),
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDataSourceSelector(twicSummaryAsync),
                    if (hasPlayerExplorer)
                      _buildActionButtons(
                        displayName: _formatDisplayName(
                          name: effectiveName,
                          title: effectiveTitle,
                        ),
                        playerKey: activePlayerKey,
                        knownTotalCount:
                            _currentDataSource == PlayerProfileDataSource.twic
                                ? twicSummaryAsync.valueOrNull?.totalGames
                                : null,
                      ),
                  ],
                ),
              ),

              // Tab content
              Expanded(
                child: NotificationListener<ScrollUpdateNotification>(
                  onNotification: _handleScrollNotification,
                  child: _buildTabContent(
                    effectiveTitle: effectiveTitle,
                    effectiveFederation: effectiveFederation,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    String countryCode,
    bool isFavorite, {
    required String? effectiveFederation,
    required String effectiveName,
    required String? effectiveTitle,
  }) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: [
          // Back button
          IconButton(
            iconSize: 24.ic,
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_ios_new_outlined,
              size: 24.ic,
              color: kWhiteColor,
            ),
          ),

          // Player name and flag
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Country flag
                  if (effectiveFederation?.toUpperCase() == 'FID')
                    Image.asset(
                      PngAsset.fideLogo,
                      height: 16.h,
                      width: 22.w,
                      fit: BoxFit.cover,
                    )
                  else if (countryCode.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2.br),
                      child: CountryFlag.fromCountryCode(
                        countryCode,
                        height: 16.h,
                        width: 22.w,
                      ),
                    ),

                  if (countryCode.isNotEmpty ||
                      effectiveFederation?.toUpperCase() == 'FID')
                    SizedBox(width: 8.w),

                  // Title and name
                  Flexible(
                    child: Text(
                      _formatDisplayName(
                        name: effectiveName,
                        title: effectiveTitle,
                      ),
                      style: AppTypography.textLgBold.copyWith(
                        color: kWhiteColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Favorite button
          GestureDetector(
            onTap: _toggleFavorite,
            child: Container(
              width: 48.w,
              height: 48.h,
              padding: EdgeInsets.all(8.sp),
              child: ScaleTransition(
                scale: _favoriteScaleAnimation,
                child: SvgWidget(
                  isFavorite
                      ? SvgAsset.favouriteRedIcon
                      : SvgAsset.favouriteIcon2,
                  semanticsLabel: 'Favorite',
                  height: 22.h,
                  width: 22.w,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher(PlayerProfileTab selectedTab) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: SegmentedSwitcher(
        backgroundColor: kPopUpColor,
        selectedBackgroundColor: kPopUpColor,
        options: playerProfileTabNames.values.toList(),
        initialSelection: PlayerProfileTab.values.indexOf(selectedTab),
        currentSelection: PlayerProfileTab.values.indexOf(selectedTab),
        onSelectionChanged: _handleTabSelection,
      ),
    );
  }

  Widget _buildIndicatorBar({
    required bool hasActiveFilter,
    required bool isTwicLoading,
  }) {
    return SizedBox(
      height: 2.h,
      child: Stack(
        children: [
          // Filter active indicator bar
          SingleMotionBuilder(
            motion: const CupertinoMotion.snappy(),
            value: hasActiveFilter ? 1.0 : 0.0,
            builder: (context, barProgress, _) {
              if (barProgress < 0.01) return const SizedBox.shrink();
              return Positioned.fill(
                child: Container(
                  height: 2.h * barProgress,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kPrimaryColor.withValues(alpha: 0.0),
                        kPrimaryColor.withValues(alpha: 0.8 * barProgress),
                        kPrimaryColor.withValues(alpha: 0.8 * barProgress),
                        kPrimaryColor.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.2, 0.8, 1.0],
                    ),
                  ),
                ),
              );
            },
          ),
          // TWIC loading indicator
          SingleMotionBuilder(
            motion: const CupertinoMotion.snappy(),
            value: isTwicLoading ? 1.0 : 0.0,
            builder: (context, loadingProgress, _) {
              if (loadingProgress < 0.01) return const SizedBox.shrink();
              return Positioned.fill(
                child: Opacity(
                  opacity: loadingProgress.clamp(0.0, 1.0),
                  child: LinearProgressIndicator(
                    backgroundColor: kPrimaryColor.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      kPrimaryColor.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent({
    String? effectiveTitle,
    String? effectiveFederation,
  }) {
    return PageView.builder(
      controller: _pageController,
      itemCount: PlayerProfileTab.values.length,
      onPageChanged: _handlePageChanged,
      itemBuilder: (context, index) {
        switch (PlayerProfileTab.values[index]) {
          case PlayerProfileTab.about:
            return PlayerAboutTab(
              fideId: widget.fideId,
              playerName: widget.playerName,
              title: effectiveTitle,
              federation: effectiveFederation,
              fallbackRating: widget.rating,
              dataSource: _currentDataSource,
              gamebasePlayerId: _currentGamebasePlayerId,
              onOpenGames: _openGames,
            );
          case PlayerProfileTab.games:
            return PlayerGamesTab(
              fideId: widget.fideId,
              playerName: widget.playerName,
              dataSource: _currentDataSource,
              gamebasePlayerId: _currentGamebasePlayerId,
            );
          case PlayerProfileTab.events:
            return PlayerEventsTab(
              fideId: widget.fideId,
              playerName: widget.playerName,
              dataSource: _currentDataSource,
              gamebasePlayerId: _currentGamebasePlayerId,
            );
        }
      },
    );
  }

  Widget _buildActionButtons({
    required String displayName,
    required PlayerProfileKey playerKey,
    int? knownTotalCount,
  }) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        4.h,
        horizontalPadding,
        2.h,
      ),
      child: Row(
        children: [
          Expanded(
            child: _ActionCard(
              icon: Icons.account_tree_outlined,
              title: 'Study opening',
              subtitle: 'Repertoire view',
              onTap: _openExplorer,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: _ActionCard(
              icon: Icons.library_add_outlined,
              title: 'Save to Library',
              subtitle: 'Games collection',
              onTap: () {
                showSaveToLibrarySheet(
                  context: context,
                  ref: ref,
                  playerKey: playerKey,
                  knownTotalCount: knownTotalCount,
                  onSelectSpecific: () {
                    _handleTabSelection(
                      PlayerProfileTab.values.indexOf(PlayerProfileTab.games),
                    );
                    ref
                        .read(
                          playerGamesSelectionModeProvider(playerKey).notifier,
                        )
                        .state = true;
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDisplayName({String? name, String? title}) {
    String displayName = name ?? widget.playerName;

    // Handle "Lastname, Firstname" format
    if (displayName.contains(',')) {
      final parts = displayName.split(',');
      if (parts.length >= 2) {
        displayName = '${parts[1].trim()} ${parts[0].trim()}';
      }
    }

    // Prepend title if present
    if (title != null && title.isNotEmpty) {
      return '$title $displayName';
    }

    return displayName;
  }

  Widget _buildDataSourceSelector(
    AsyncValue<TwicProfileSummary?> twicSummaryAsync,
  ) {
    final summary = twicSummaryAsync.valueOrNull;
    final isLoading = twicSummaryAsync.isLoading;
    final isTwic = _currentDataSource == PlayerProfileDataSource.twic;

    if (summary == null && !isLoading && !isTwic) {
      return const SizedBox.shrink();
    }

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );
    final twicGameCount =
        summary != null ? formatCompactCount(summary.totalGames) : '--';

    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      value: 1.0,
      builder: (context, progress, _) {
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - progress) * -6),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                4.h,
                horizontalPadding,
                0,
              ),
              child: _DataSourceBanner(
                isTwic: isTwic,
                isLoading: isLoading,
                twicGameCount: twicGameCount,
                twicEnabled: summary != null || isTwic,
                onSelectRegular:
                    () => _setDataSource(PlayerProfileDataSource.supabase),
                onSelectTwic:
                    summary == null
                        ? null
                        : () => _setDataSource(
                          PlayerProfileDataSource.twic,
                          gamebasePlayerId: summary.gamebasePlayerId,
                        ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Segmented toggle for switching between ChessEver and TWIC data sources.
class _DataSourceBanner extends StatelessWidget {
  const _DataSourceBanner({
    required this.isTwic,
    required this.isLoading,
    required this.twicGameCount,
    required this.twicEnabled,
    required this.onSelectRegular,
    required this.onSelectTwic,
  });

  final bool isTwic;
  final bool isLoading;
  final String twicGameCount;
  final bool twicEnabled;
  final VoidCallback onSelectRegular;
  final VoidCallback? onSelectTwic;

  @override
  Widget build(BuildContext context) {
    final canSwitchToTwic =
        twicEnabled && onSelectTwic != null && !isLoading;

    return Container(
      padding: EdgeInsets.all(3.sp),
      decoration: BoxDecoration(
        color: kWhiteColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Row(
        children: [
          // ChessEver tab
          Expanded(
            child: _SourceTab(
              label: 'ChessEver',
              isActive: !isTwic,
              onTap: isTwic ? onSelectRegular : null,
            ),
          ),
          SizedBox(width: 3.w),
          // TWIC tab
          Expanded(
            child: _SourceTab(
              label: isLoading ? 'TWIC' : 'TWIC · $twicGameCount',
              isActive: isTwic,
              isLoading: isLoading && !isTwic,
              onTap: !isTwic && canSwitchToTwic ? onSelectTwic : null,
              accentColor: kPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceTab extends StatefulWidget {
  const _SourceTab({
    required this.label,
    required this.isActive,
    this.isLoading = false,
    this.onTap,
    this.accentColor,
  });

  final String label;
  final bool isActive;
  final bool isLoading;
  final VoidCallback? onTap;
  final Color? accentColor;

  @override
  State<_SourceTab> createState() => _SourceTabState();
}

class _SourceTabState extends State<_SourceTab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.accentColor ?? kWhiteColor;

    return GestureDetector(
      onTapDown:
          widget.onTap != null
              ? (_) => setState(() => _pressed = true)
              : null,
      onTapUp:
          widget.onTap != null
              ? (_) {
                setState(() => _pressed = false);
                HapticFeedbackService.light();
                widget.onTap!();
              }
              : null,
      onTapCancel:
          widget.onTap != null
              ? () => setState(() => _pressed = false)
              : null,
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _pressed ? 1.0 : 0.0,
        builder: (context, pressProgress, _) {
          return Transform.scale(
            scale: 1.0 - 0.02 * pressProgress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: 10.w,
                vertical: 7.h,
              ),
              decoration: BoxDecoration(
                color:
                    widget.isActive
                        ? (widget.accentColor != null
                            ? activeColor.withValues(alpha: 0.12)
                            : kWhiteColor.withValues(alpha: 0.10))
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8.br),
                border: Border.all(
                  color:
                      widget.isActive
                          ? (widget.accentColor != null
                              ? activeColor.withValues(alpha: 0.30)
                              : kWhiteColor.withValues(alpha: 0.12))
                          : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.isLoading) ...[
                    SizedBox(
                      width: 10.w,
                      height: 10.h,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          kPrimaryColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    SizedBox(width: 6.w),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      style: AppTypography.textXsMedium.copyWith(
                        color:
                            widget.isActive
                                ? (widget.accentColor != null
                                    ? activeColor.withValues(alpha: 0.95)
                                    : kWhiteColor.withValues(alpha: 0.95))
                                : kWhiteColor.withValues(alpha: 0.40),
                        fontWeight:
                            widget.isActive
                                ? FontWeight.w600
                                : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Model for recent opponent data (keeping for backward compatibility)
class _ActionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedbackService.light();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _pressed ? 1.0 : 0.0,
        builder: (context, pressProgress, _) {
          return Transform.scale(
            scale: 1.0 - 0.03 * pressProgress,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: kPopUpColor,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: kPrimaryColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34.w,
                    height: 34.h,
                    decoration: BoxDecoration(
                      color: kPrimaryColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(9.br),
                    ),
                    child: Icon(widget.icon, size: 18.ic, color: kWhiteColor),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: AppTypography.textSmBold.copyWith(
                            color: kWhiteColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          widget.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.textXsRegular.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Model for recent opponent data (keeping for backward compatibility)
class RecentOpponent {
  const RecentOpponent({
    required this.name,
    required this.title,
    required this.countryCode,
    required this.rating,
    required this.result,
    required this.playedAsWhite,
    this.fideId,
  });

  final String name;
  final String? title;
  final String countryCode;
  final int rating;
  final double result; // 1.0 = win, 0.5 = draw, 0.0 = loss
  final bool playedAsWhite;
  final String? fideId;
}
