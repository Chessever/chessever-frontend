import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/player_backfill_provider.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/tabs/player_about_tab.dart';
import 'package:chessever2/screens/player_profile/widgets/save_to_library_sheet.dart';
import 'package:chessever2/screens/player_profile/tabs/player_events_tab.dart';
import 'package:chessever2/screens/player_profile/tabs/player_games_tab.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';

import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:chessever2/utils/favorite_limit_guard.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
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
    this.gamebasePlayerId,
  });

  /// FIDE ID - can be null for players without official FIDE registration
  final int? fideId;
  final String playerName;
  final String? title;
  final String? federation;
  final int? rating;
  final String? gamebasePlayerId;

  /// Create from SearchPlayer model
  factory PlayerProfileScreen.fromSearchPlayer(SearchPlayer player) {
    return PlayerProfileScreen(
      fideId: player.fideId,
      playerName: player.name,
      title: player.title,
      federation: player.fed,
      rating: player.rating,
    );
  }

  @override
  ConsumerState<PlayerProfileScreen> createState() =>
      _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends ConsumerState<PlayerProfileScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _favoriteAnimationController;
  late Animation<double> _favoriteScaleAnimation;
  final ScrollToTopBus _scrollToTopBus = ScrollToTopBus();

  /// Games/events are now sourced exclusively from TWIC. The old
  /// ChessEver/TWIC source selector was removed after the two databases were
  /// merged backend-side, so TWIC is the single source of truth.
  static const _source = PlayerProfileDataSource.twic;
  String? _currentGamebasePlayerId;
  bool _didPrefetchExplorerRoot = false;
  int? _gamesTabCueCount;

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
    _scrollToTopBus.dispose();
    super.dispose();
  }

  String? _normalizePlayerId(String? raw) {
    final id = raw?.trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  void _handleTabSelection(int index) {
    HapticFeedbackService.buttonPress();
    final nextTab = PlayerProfileTab.values[index];
    final currentTab = ref.read(selectedPlayerProfileTabProvider);
    if (nextTab == currentTab) {
      _scrollToTopBus.request();
      return;
    }
    ref.read(selectedPlayerProfileTabProvider.notifier).state = nextTab;
    if (nextTab == PlayerProfileTab.games && _gamesTabCueCount != null) {
      setState(() => _gamesTabCueCount = null);
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handlePageChanged(int index) {
    final nextTab = PlayerProfileTab.values[index];
    final currentTab = ref.read(selectedPlayerProfileTabProvider);
    if (PlayerProfileTab.values.indexOf(currentTab) != index) {
      ref.read(selectedPlayerProfileTabProvider.notifier).state = nextTab;
    }
    if (nextTab == PlayerProfileTab.games && _gamesTabCueCount != null) {
      setState(() => _gamesTabCueCount = null);
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
    GameOnlineFilter? online,
    PlayerResultFilter? playerResultFilter,
    String? searchQuery,
    int? gamesTabCueCount,
  }) async {
    final allowed = await requireFullAuthGuard(context);
    if (!allowed) return;

    HapticFeedbackService.buttonPress();
    final playerKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
      source: _source,
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
      online: online,
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
        if (!mounted) return;
        final subscribed = await requirePremiumGuard(context, ref);
        if (!subscribed || !mounted) return;
      }
    }

    if (gamesTabCueCount != null || eco == GameEcoFilter.all) {
      if (!mounted) return;
      setState(() {
        _gamesTabCueCount =
            gamesTabCueCount != null && gamesTabCueCount > 0
                ? gamesTabCueCount
                : null;
      });
    }

    // Apply the filter
    notifier.mergeFilter(
      timeControl: timeControl,
      color: color,
      eco: eco,
      online: online,
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
      source: PlayerProfileDataSource.twic,
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
      source: _source,
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
    final hasPremium = await requirePremiumGuard(context, ref);
    if (!hasPremium || !mounted) return;

    HapticFeedbackService.buttonPress();
    final uuid = _resolveGamebasePlayerId();
    if (uuid == null) return;

    _startExplorerTreeForPlayer(uuid);

    final initialPlayer = _buildExplorerFallbackPlayer(uuid);
    if (!mounted) return;

    // Map player profile filters → explorer filters (time control + rating only).
    final playerKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
      source: _source,
      gamebasePlayerId: _currentGamebasePlayerId,
    );
    final gameFilter =
        ref.read(playerProfileGamesKeyProvider(playerKey)).filter;
    final GamebaseFilters? explorerFilters =
        gameFilter.hasExplorerMappableFilters
            ? gameFilter.toGamebaseFilters()
            : null;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => GamebaseExplorerScreen.scoped(
              initialPlayer: initialPlayer,
              initialFilters: explorerFilters,
            ),
      ),
    );

    // Warm/update cache in background without blocking navigation.
    unawaited(ref.read(playerByIdProvider(uuid).future));
  }

  void _startExplorerTreeForPlayer(String playerId) {
    if (_didPrefetchExplorerRoot) return;
    _didPrefetchExplorerRoot = true;

    ref.read(playerOpeningTreeProvider(playerId).notifier).start();
  }

  Future<void> _toggleFavorite() async {
    final allowed = await requireFullAuthGuard(context);
    if (!allowed) return;

    // Check if adding (not removing) and enforce limit
    final fideIdStr = widget.fideId?.toString();
    final currentlyFavorited = ref
        .read(favoritePlayersProviderNew)
        .maybeWhen(
          data: (players) => players.any((p) => p.fideId == fideIdStr),
          orElse: () => false,
        );
    if (!currentlyFavorited) {
      if (!mounted) return;
      final canAdd = await canAddMoreFavorites(context, ref);
      if (!canAdd) return;
    }

    HapticFeedbackService.buttonPress();

    try {
      final isNowFavorite = await ref
          .read(favoritePlayersProviderNew.notifier)
          .toggleFavorite(
            fideId: widget.fideId?.toString(),
            playerName: widget.playerName,
            countryCode: widget.federation,
            rating: widget.rating,
            title: widget.title,
          );
      if (isNowFavorite) {
        _favoriteAnimationController.forward().then(
          (_) => _favoriteAnimationController.reverse(),
        );
      }
    } on FavoriteLimitExceededException {
      if (mounted) {
        await showPremiumPaywallSheet(context: context);
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
          _startExplorerTreeForPlayer(playerId);
        });
      }
    }

    final activePlayerKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
      source: _source,
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
      source: PlayerProfileDataSource.twic,
      gamebasePlayerId: _currentGamebasePlayerId,
    );
    // TWIC summary feeds the games-tab total count and the study-opening row.
    final twicSummaryAsync = ref.watch(
      twicProfileSummaryProvider(twicLookupKey),
    );

    // Watch favorites to show correct state
    final favoritesAsync = ref.watch(favoritePlayersProviderNew);
    final isFavorite = favoritesAsync.maybeWhen(
      data:
          (players) =>
              players.any((p) => p.fideId == widget.fideId?.toString()),
      orElse: () => false,
    );

    final playerKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
      source: _source,
      gamebasePlayerId: _currentGamebasePlayerId,
    );
    final gamesState = ref.watch(playerProfileGamesKeyProvider(playerKey));
    final hasActiveFilter = gamesState.hasActiveFilters;

    var isTwicStatsLoading = false;
    if (selectedTab == PlayerProfileTab.about) {
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
    final isTwicLoading = gamesState.isLoading || isTwicStatsLoading;

    return Scaffold(
      key: e2eKey(E2eIds.playerProfileRoot),
      backgroundColor: context.colors.background,
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
                    if (hasPlayerExplorer &&
                        selectedTab == PlayerProfileTab.about)
                      _buildStudyOpeningRow(),
                    if (selectedTab == PlayerProfileTab.games)
                      _buildGamesActionButtons(
                        showStudyOpening: hasPlayerExplorer,
                        playerKey: activePlayerKey,
                        hasActiveFilter: hasActiveFilter,
                        knownTotalCount:
                            twicSummaryAsync.valueOrNull?.totalGames,
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
              color: context.colors.textPrimary,
            ),
          ),

          // Player name and flag
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Country flag
                  if (countryCode.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2.br),
                      child: CountryFlag.fromCountryCode(
                        countryCode,
                        theme: ImageTheme(height: 16.h, width: 22.w),
                      ),
                    ),

                  if (countryCode.isNotEmpty) SizedBox(width: 8.w),

                  // Title and name
                  Flexible(
                    child: Text(
                      _formatDisplayName(
                        name: effectiveName,
                        title: effectiveTitle,
                      ),
                      style: AppTypography.textLgBold.copyWith(
                        color: context.colors.textPrimary,
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
                  preserveOriginalColors: isFavorite,
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

    final tabOptions = PlayerProfileTab.values
        .map((tab) {
          if (tab == PlayerProfileTab.games &&
              selectedTab != PlayerProfileTab.games &&
              _gamesTabCueCount != null &&
              _gamesTabCueCount! > 0) {
            return 'Games ${formatCompactCount(_gamesTabCueCount!)}';
          }
          return playerProfileTabNames[tab]!;
        })
        .toList(growable: false);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: SegmentedSwitcher(
        backgroundColor: context.colors.popup,
        selectedBackgroundColor: context.colors.popup,
        options: tabOptions,
        initialSelection: PlayerProfileTab.values.indexOf(selectedTab),
        currentSelection: PlayerProfileTab.values.indexOf(selectedTab),
        onSelectionChanged: _handleTabSelection,
        notifyOnReselect: true,
      ),
    );
  }

  Widget _buildIndicatorBar({
    required bool hasActiveFilter,
    required bool isTwicLoading,
  }) {
    // The TWIC LinearProgressIndicator has an internal repeating animation
    // that updates its Semantics node every frame. Combined with the extra
    // semantic boundaries on tablet (Center + ConstrainedBox), this dirtied
    // parent semantics mid-assembly and blocked everything below from
    // rendering. Exclude from semantics + isolate paint.
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          height: 2.h,
          child: Stack(
            children: [
              // Filter active indicator bar
              Positioned.fill(
                child: SingleMotionBuilder(
                  motion: const CupertinoMotion.snappy(),
                  value: hasActiveFilter ? 1.0 : 0.0,
                  builder: (context, barProgress, _) {
                    if (barProgress < 0.01) return const SizedBox.shrink();
                    return Container(
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
                    );
                  },
                ),
              ),
              // TWIC loading indicator
              Positioned.fill(
                child: SingleMotionBuilder(
                  motion: const CupertinoMotion.snappy(),
                  value: isTwicLoading ? 1.0 : 0.0,
                  builder: (context, loadingProgress, _) {
                    if (loadingProgress < 0.01) return const SizedBox.shrink();
                    return Opacity(
                      opacity: loadingProgress.clamp(0.0, 1.0),
                      child: LinearProgressIndicator(
                        backgroundColor: kPrimaryColor.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          kPrimaryColor.withValues(alpha: 0.92),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent({
    String? effectiveTitle,
    String? effectiveFederation,
  }) {
    return ScrollToTopScope(
      bus: _scrollToTopBus,
      child: PageView.builder(
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
                dataSource: _source,
                gamebasePlayerId: _currentGamebasePlayerId,
                onOpenGames: _openGames,
              );
            case PlayerProfileTab.games:
              return PlayerGamesTab(
                fideId: widget.fideId,
                playerName: widget.playerName,
                dataSource: _source,
                gamebasePlayerId: _currentGamebasePlayerId,
              );
            case PlayerProfileTab.events:
              return PlayerEventsTab(
                fideId: widget.fideId,
                playerName: widget.playerName,
                dataSource: _source,
                gamebasePlayerId: _currentGamebasePlayerId,
              );
          }
        },
      ),
    );
  }

  /// Compact inline row for study opening on the About tab.
  Widget _buildStudyOpeningRow() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        14.h,
        horizontalPadding,
        0,
      ),
      child: _StudyOpeningPill(onTap: _openExplorer),
    );
  }

  /// Full action buttons row for the Games tab (study opening + save to library).
  /// Animates the study opening card in/out with a spring when switching
  /// between TWIC (both cards) and ChessEver (save-to-library only).
  Widget _buildGamesActionButtons({
    required PlayerProfileKey playerKey,
    required bool hasActiveFilter,
    required bool showStudyOpening,
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
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.bouncy(),
        value: showStudyOpening ? 1.0 : 0.0,
        builder: (context, t, _) {
          // t: 1 = both cards visible (TWIC), 0 = only save-to-library.
          // Clamp aggressively — bouncy spring overshoots, and any NaN/inf
          // leaking into Opacity/Transform downstream produces an invalid
          // matrix in the layer tree (manifests on tablet under TWIC).
          final tt = t.isFinite ? t.clamp(0.0, 1.0) : 0.0;
          final buildTreeFlex = (tt * 1000).round();

          return Row(
            children: [
              if (buildTreeFlex > 0) ...[
                Flexible(
                  flex: buildTreeFlex,
                  child: ClipRect(
                    child: Opacity(
                      opacity: tt,
                      child: Transform.scale(
                        scale: 0.92 + 0.08 * tt,
                        alignment: Alignment.centerLeft,
                        child: _ActionCard(
                          icon: Icons.account_tree_outlined,
                          title: 'Build Tree',
                          subtitle:
                              hasActiveFilter
                                  ? 'Filtered games'
                                  : 'Repertoire view',
                          isHighlighted: hasActiveFilter,
                          onTap: _openExplorer,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w * tt),
              ],
              // Save to Library — always present, fills remaining width.
              Flexible(
                flex: 1000,
                child: _ActionCard(
                  icon: Icons.library_add_outlined,
                  title: 'Save to Library',
                  subtitle:
                      hasActiveFilter ? 'Filtered games' : 'Games collection',
                  isHighlighted: hasActiveFilter,
                  onTap: () {
                    showSaveToLibrarySheet(
                      context: context,
                      ref: ref,
                      playerKey: playerKey,
                      knownTotalCount: knownTotalCount,
                      onSelectSpecific: () {
                        _handleTabSelection(
                          PlayerProfileTab.values.indexOf(
                            PlayerProfileTab.games,
                          ),
                        );
                        ref
                            .read(
                              playerGamesSelectionModeProvider(
                                playerKey,
                              ).notifier,
                            )
                            .state = true;
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
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
}

/// Compact pill-style button for study opening on the About tab.
class _StudyOpeningPill extends StatefulWidget {
  const _StudyOpeningPill({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_StudyOpeningPill> createState() => _StudyOpeningPillState();
}

class _StudyOpeningPillState extends State<_StudyOpeningPill> {
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
            scale: 1.0 - 0.02 * pressProgress,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10.br),
                border: Border.all(
                  color: kPrimaryColor.withValues(alpha: 0.24),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 16.ic,
                    color: kPrimaryColor,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'Build Tree',
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.92),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18.ic,
                    color: context.colors.textPrimary.withValues(alpha: 0.5),
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

class _ActionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isHighlighted;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isHighlighted = false,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  static const _filterRed = Color(0xFFEF4444);
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
            child: SingleMotionBuilder(
              motion: const CupertinoMotion.snappy(),
              value: widget.isHighlighted ? 1.0 : 0.0,
              builder: (context, h, _) {
                // Idle: solid dark card. Highlighted: red-tinted.
                final bg =
                    Color.lerp(
                      context.colors.surface,
                      _filterRed.withValues(alpha: 0.10),
                      h,
                    )!;
                final iconBg =
                    Color.lerp(
                      context.colors.textPrimary.withValues(alpha: 0.08),
                      _filterRed.withValues(alpha: 0.18),
                      h,
                    )!;
                final iconColor =
                    Color.lerp(
                      context.colors.textPrimary.withValues(alpha: 0.85),
                      _filterRed,
                      h,
                    )!;
                return Container(
                  height: 62.h,
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.w,
                    vertical: 8.h,
                  ),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12.br),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return OverflowBox(
                        minWidth: 0,
                        maxWidth: double.infinity,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: constraints.maxWidth.clamp(
                            160.w,
                            double.infinity,
                          ),
                          child: Row(
                            children: [
                              // Icon badge
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 34.w,
                                    height: 34.h,
                                    decoration: BoxDecoration(
                                      color: iconBg,
                                      borderRadius: BorderRadius.circular(9.br),
                                    ),
                                    child: Icon(
                                      widget.icon,
                                      size: 18.ic,
                                      color: iconColor,
                                    ),
                                  ),
                                  // Red dot badge when highlighted
                                  if (widget.isHighlighted)
                                    Positioned(
                                      right: -3,
                                      top: -3,
                                      child: Container(
                                        width: 9.w,
                                        height: 9.w,
                                        decoration: const BoxDecoration(
                                          color: _filterRed,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.title,
                                      style: AppTypography.textSmBold.copyWith(
                                        color: context.colors.textPrimary,
                                        height: 1.15,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: 2.h),
                                    Text(
                                      widget.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.textXsRegular
                                          .copyWith(
                                            height: 1.15,
                                            color:
                                                widget.isHighlighted
                                                    ? _filterRed.withValues(
                                                      alpha: 0.9,
                                                    )
                                                    : context.colors.textPrimary
                                                        .withValues(alpha: 0.5),
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
              },
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
