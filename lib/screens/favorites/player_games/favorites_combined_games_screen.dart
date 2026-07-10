import 'dart:async';

import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/live_gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_stack.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FavoritesCombinedGamesScreen extends ConsumerStatefulWidget {
  const FavoritesCombinedGamesScreen({super.key});

  @override
  ConsumerState<FavoritesCombinedGamesScreen> createState() =>
      _FavoritesCombinedGamesScreenState();
}

class _FavoritesCombinedGamesScreenState
    extends ConsumerState<FavoritesCombinedGamesScreen>
    with WidgetsBindingObserver, RouteAware {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  Timer? _scrollIdleTimer;
  bool _routeSubscribed = false;
  bool _routeIsCurrent = true;
  bool _appIsResumed = true;
  bool _liveCardsPausedForScroll = false;
  late final StateController<Set<String>> _liveGameCardsPauseReasons;
  static const Duration _scrollIdleDelay = Duration(milliseconds: 180);

  String get _liveCardsPauseReason => 'favorites_combined_scroll_$hashCode';
  // Keep rendering while backgrounded so the OS app-switcher snapshot is not
  // blank. Route coverage still removes the screen from active provider work.
  bool get _isActiveOnScreen => _routeIsCurrent;

  /// Selected player IDs for filtering - empty means show all
  final Set<String> _selectedPlayerIds = {};

  @override
  void initState() {
    super.initState();
    _liveGameCardsPauseReasons = ref.read(
      liveGameCardsPauseReasonsProvider.notifier,
    );
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    routeObserver.subscribe(this, route);
    _routeSubscribed = true;
    _routeIsCurrent = route.isCurrent;
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      routeObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    ForegroundTaskScheduler.cancel('favorites_combined_resume_$hashCode');
    _debounceTimer?.cancel();
    _scrollIdleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didPush() {
    _setRouteActive(true);
  }

  @override
  void didPopNext() {
    _setRouteActive(true);
  }

  @override
  void didPushNext() {
    _setRouteActive(false);
  }

  @override
  void didPop() {
    _setRouteActive(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      ForegroundTaskScheduler.cancel('favorites_combined_resume_$hashCode');
      _setAppResumed(false);
      return;
    }
    if (!mounted) return;

    _setAppResumed(true);
    ForegroundTaskScheduler.schedule(
      key: 'favorites_combined_resume_$hashCode',
      task: () {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route?.isCurrent != true) return;

        ref.invalidate(gameUpdatesStreamProvider);
        ref.invalidate(liveGameUpdateStreamProvider);
        ref.invalidate(gameUpdatesBatchStreamProvider);
        unawaited(
          ref.read(favoritesCombinedGamesProvider.notifier).refreshGames(),
        );
      },
    );
  }

  void _setRouteActive(bool isActive) {
    if (!mounted) return;
    if (_routeIsCurrent != isActive) {
      setState(() => _routeIsCurrent = isActive);
    }
    if (!isActive) {
      ForegroundTaskScheduler.cancel('favorites_combined_resume_$hashCode');
      _stopLiveCardsForHiddenRoute();
    }
  }

  void _setAppResumed(bool isResumed) {
    if (!mounted) return;
    if (_appIsResumed != isResumed) {
      setState(() => _appIsResumed = isResumed);
    }
    if (!isResumed) {
      _stopLiveCardsForHiddenRoute();
    }
  }

  void _onScroll() {
    _markLiveCardsScrolling();
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(favoritesCombinedGamesProvider);
      if (state.isSearching) {
        ref
            .read(favoritesCombinedGamesProvider.notifier)
            .loadMoreSearchResults();
      } else {
        ref.read(favoritesCombinedGamesProvider.notifier).loadMoreGames();
      }
    }
  }

  void _markLiveCardsScrolling() {
    _setLiveCardsPausedForScroll(true);
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(_scrollIdleDelay, _markLiveCardsIdle);
  }

  void _markLiveCardsIdle() {
    _setLiveCardsPausedForScroll(false);
  }

  void _stopLiveCardsForHiddenRoute() {
    _scrollIdleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
  }

  void _setLiveCardsPausedForScroll(bool paused) {
    if (_liveCardsPausedForScroll == paused) return;
    _liveCardsPausedForScroll = paused;
    setLiveGameCardsPausedWithNotifier(
      _liveGameCardsPauseReasons,
      reason: _liveCardsPauseReason,
      paused: paused,
    );
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(favoritesCombinedGamesProvider.notifier).searchGames(value);
    });
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(favoritesCombinedGamesProvider.notifier).clearSearch();
  }

  List<GamesTourModel> _filterGames(
    List<GamesTourModel> games,
    List<FavoritePlayer> favorites,
  ) {
    var filtered = games;

    // Filter by selected players if any are selected
    if (_selectedPlayerIds.isNotEmpty) {
      final selectedFavorites =
          favorites.where((f) => _selectedPlayerIds.contains(f.id)).toList();

      // Stale selection (favorite removed while chip still tracked) — skip
      // filtering rather than nuking the list to an empty state. Pruning of
      // the underlying Set happens out-of-band via post-frame callback.
      if (selectedFavorites.isEmpty) return filtered;

      filtered =
          filtered.where((game) {
            for (final favorite in selectedFavorites) {
              // 1. Try FIDE ID match first (most reliable)
              if (favorite.fideId != null && favorite.fideId!.isNotEmpty) {
                final favFideId = int.tryParse(favorite.fideId!);
                if (favFideId != null) {
                  final whiteId = game.whitePlayer.fideId;
                  final blackId = game.blackPlayer.fideId;
                  if (whiteId == favFideId || blackId == favFideId) {
                    return true;
                  }
                }
              }

              // 2. Fall back to name matching
              final favName = _normalizeNameForMatch(favorite.playerName);
              final whiteName = _normalizeNameForMatch(game.whitePlayer.name);
              final blackName = _normalizeNameForMatch(game.blackPlayer.name);

              if (_namesMatch(favName, whiteName) ||
                  _namesMatch(favName, blackName)) {
                return true;
              }
            }
            return false;
          }).toList();
    }

    return filtered;
  }

  /// Drop any tracked selection IDs that no longer correspond to a current
  /// favorite (e.g. user unfavorited a player while their chip was selected).
  void _pruneStaleSelections(List<FavoritePlayer> favorites) {
    if (_selectedPlayerIds.isEmpty) return;
    final liveIds = favorites.map((f) => f.id).toSet();
    final stale = _selectedPlayerIds.difference(liveIds);
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedPlayerIds.removeAll(stale));
    });
  }

  /// Normalize name for matching: lowercase, remove titles, handle "Last, First" format
  String _normalizeNameForMatch(String name) {
    var normalized = name.toLowerCase().trim();
    // Remove extra whitespace
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
    // Remove common chess title prefixes (GM, IM, FM, WGM, WIM, WFM, CM, WCM, NM)
    normalized = normalized.replaceFirst(
      RegExp(r'^(gm|im|fm|wgm|wim|wfm|cm|wcm|nm)\s+'),
      '',
    );
    return normalized;
  }

  /// Check if two names match (handles "Last, First" vs "First Last" formats)
  bool _namesMatch(String name1, String name2) {
    // Direct match
    if (name1 == name2) return true;

    // Extract last name (before comma or last word)
    final lastName1 = _extractLastName(name1);
    final lastName2 = _extractLastName(name2);

    // If last names match, it's likely the same person
    if (lastName1.isNotEmpty && lastName1 == lastName2) {
      return true;
    }

    // Check if one contains the other (for partial matches)
    if (name1.contains(name2) || name2.contains(name1)) {
      return true;
    }

    return false;
  }

  /// Extract last name from a player name
  String _extractLastName(String name) {
    // Handle "Last, First" format
    if (name.contains(',')) {
      return name.split(',').first.trim();
    }
    // Handle "First Last" format
    final parts = name.split(' ');
    if (parts.length > 1) {
      return parts.last.trim();
    }
    return name;
  }

  void _togglePlayerFilter(String playerId) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedPlayerIds.contains(playerId)) {
        _selectedPlayerIds.remove(playerId);
      } else {
        _selectedPlayerIds.add(playerId);
      }
    });
  }

  void _clearAllFilters() {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedPlayerIds.clear();
    });
  }

  String? _extractFederation(FavoritePlayer player) {
    final metadata = player.metadata;
    if (metadata.containsKey('federation')) {
      return metadata['federation']?.toString();
    }
    if (metadata.containsKey('fed')) {
      return metadata['fed']?.toString();
    }
    if (metadata.containsKey('country')) {
      return metadata['country']?.toString();
    }
    if (metadata.containsKey('countryCode')) {
      return metadata['countryCode']?.toString();
    }
    return null;
  }

  String _getDisplayName(String fullName) {
    final parts = fullName.split(',');
    if (parts.length > 1) {
      return parts[0].trim();
    }
    final words = fullName.trim().split(' ');
    if (words.length > 1) {
      return words.last;
    }
    return fullName.length > 12 ? '${fullName.substring(0, 10)}...' : fullName;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isActiveOnScreen) {
      return const SizedBox.shrink();
    }

    final state = ref.watch(favoritesCombinedGamesProvider);
    final favoritesAsync = ref.watch(favoritePlayersProviderNew);
    final favorites = favoritesAsync.valueOrNull ?? [];
    final favoriteCount = favorites.length;
    final showsPlayerFilters = favorites.length > 1;
    final controlExtent = _controlExtent(context);
    final topContentInset = _topContentInset(
      context,
      includesPlayerFilters: showsPlayerFilters,
    );
    _pruneStaleSelections(favorites);

    return GlassFullScreenPage(
      backgroundColor: context.colors.background,
      includeContentSafeArea: false,
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.isTablet
                    ? ResponsiveHelper.contentMaxWidth
                    : double.infinity,
          ),
          child: GlassIslandStack(
            includeStatusBar: false,
            gap: 8,
            children: [
              _buildTopBar(context, favoriteCount, state, controlExtent),
              _buildSearchBar(state, controlExtent),
              if (showsPlayerFilters)
                _buildFilterChips(favorites, controlExtent),
            ],
          ),
        ),
      ),
      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.isTablet
                    ? ResponsiveHelper.contentMaxWidth
                    : double.infinity,
          ),
          child: RefreshIndicator(
            onRefresh: () async {
              HapticFeedbackService.medium();
              await ref
                  .read(favoritesCombinedGamesProvider.notifier)
                  .refreshGames();
            },
            color: context.colors.textPrimary,
            backgroundColor: context.colors.surface,
            edgeOffset: topContentInset,
            child: CustomScrollView(
              controller: _scrollController,
              scrollCacheExtent: kListScrollCacheExtent,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // This spacer belongs to the scroll content, so the cards can
                // travel behind the floating controls without a sticky band.
                SliverToBoxAdapter(child: SizedBox(height: topContentInset)),
                _buildContentSliver(state, favorites),
                SliverToBoxAdapter(
                  child: SizedBox(height: _bottomContentInset(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _controlExtent(BuildContext context) {
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(16);
    final dynamicExtent = scaledLabelHeight + 28;
    return dynamicExtent < 48 ? 48 : dynamicExtent;
  }

  double _topContentInset(
    BuildContext context, {
    required bool includesPlayerFilters,
  }) {
    final controlExtent = _controlExtent(context);
    final rowCount = includesPlayerFilters ? 3 : 2;
    const overlayTopPadding = 4.0;
    const topBarBottomPadding = 6.0;
    const rowGap = 8.0;
    const stackBottomPadding = 4.0;
    const contentGap = 8.0;
    return MediaQuery.viewPaddingOf(context).top +
        overlayTopPadding +
        (controlExtent * rowCount) +
        topBarBottomPadding +
        (rowGap * (rowCount - 1)) +
        stackBottomPadding +
        contentGap;
  }

  double _bottomContentInset(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.viewPadding.bottom + media.viewInsets.bottom + 24.h;
  }

  Widget _buildTopBar(
    BuildContext context,
    int favoriteCount,
    FavoritesCombinedGamesState state,
    double controlExtent,
  ) {
    final hasActiveFilters = state.filter.hasActiveFilters;
    final activeFilterCount = state.filter.activeFilterCount;

    void openFilters() => _showFilterDialog(state);
    final filterLabel =
        hasActiveFilters ? 'Filters, $activeFilterCount active' : 'Filters';

    return GlassIslandTopBar(
      topPadding: 0,
      height: controlExtent,
      horizontalPadding: ResponsiveHelper.adaptive(phone: 12, tablet: 24),
      leading: const GlassBackButton(),
      title: GlassTitleChip(
        label: favoriteCount > 0 ? 'Favorites · $favoriteCount' : 'Favorites',
        height: controlExtent,
        icon: Icon(
          Icons.favorite_rounded,
          color: context.colors.danger,
          size: 16,
        ),
      ),
      trailing: [
        Semantics(
          label: filterLabel,
          button: true,
          onTap: openFilters,
          child: ExcludeSemantics(
            child: GlassBadge(
              count: hasActiveFilters ? activeFilterCount : 0,
              backgroundColor: context.colors.danger,
              child: GlassIconButton(
                icon: Icon(
                  Icons.tune_rounded,
                  color:
                      hasActiveFilters
                          ? context.colors.iconPrimary
                          : context.colors.iconSecondary,
                ),
                onPressed: openFilters,
                size: 48,
                iconSize: 18,
                useOwnLayer: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showFilterDialog(FavoritesCombinedGamesState state) async {
    HapticFeedbackService.buttonPress();
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: state.filter,
      showFormatFilter: false,
    );
    if (result != null && mounted) {
      ref.read(favoritesCombinedGamesProvider.notifier).applyFilter(result);
    }
  }

  Widget _buildSearchBar(
    FavoritesCombinedGamesState state,
    double controlExtent,
  ) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 32.w,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.standard,
        height: controlExtent,
        padding: EdgeInsets.only(left: 14.w),
        shape: LiquidRoundedSuperellipse(borderRadius: controlExtent / 2),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.search,
                size: 20.sp,
                color: context.colors.iconSecondary,
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textAlignVertical: TextAlignVertical.center,
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textPrimary,
                ),
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  isCollapsed: true,
                  hintText: 'Search',
                  hintStyle: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textSecondary,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, _) {
                if (value.text.isEmpty && !state.isSearching) {
                  return SizedBox(width: 8.w);
                }
                return Semantics(
                  label: 'Clear search',
                  button: true,
                  onTap: _clearSearch,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _clearSearch,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Icon(
                          Icons.close_rounded,
                          size: 20.sp,
                          color: context.colors.iconSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(
    List<FavoritePlayer> favorites,
    double controlExtent,
  ) {
    final hasSelection = _selectedPlayerIds.isNotEmpty;
    final reduceMotion = GlassMotion.reduceMotion(context);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 32.w,
    );

    return SizedBox(
      height: controlExtent,
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0.0, 0.03, 0.97, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          itemCount: favorites.length + (hasSelection ? 1 : 0),
          itemBuilder: (context, index) {
            // Clear button at the end when there's a selection
            if (hasSelection && index == favorites.length) {
              return Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: Semantics(
                  label: 'Clear player filters',
                  button: true,
                  onTap: _clearAllFilters,
                  child: ExcludeSemantics(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: controlExtent),
                      child: GlassChip(
                        label: 'Clear',
                        icon: Icon(
                          Icons.close_rounded,
                          color: context.colors.iconSecondary,
                        ),
                        onTap: _clearAllFilters,
                        useOwnLayer: true,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 12.h,
                        ),
                        labelStyle: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textSecondary,
                        ),
                        iconColor: context.colors.iconSecondary,
                        interactionScale: reduceMotion ? 1 : 1.03,
                        stretch: reduceMotion ? 0 : 0.3,
                      ),
                    ),
                  ),
                ),
              );
            }

            final player = favorites[index];
            final isSelected = _selectedPlayerIds.contains(player.id);
            final federation = _extractFederation(player);
            final displayName = _getDisplayName(player.playerName);

            return Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: Semantics(
                label: 'Filter games by $displayName',
                button: true,
                selected: isSelected,
                onTap: () => _togglePlayerFilter(player.id),
                child: ExcludeSemantics(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: controlExtent),
                    child: GlassChip(
                      label: displayName,
                      icon: FederationFlag(
                        federation: federation,
                        width: 16.w,
                        height: 12.h,
                        borderRadius: BorderRadius.circular(2.br),
                      ),
                      onTap: () => _togglePlayerFilter(player.id),
                      selected: isSelected,
                      selectedColor: context.colors.danger.withValues(
                        alpha:
                            Theme.of(context).brightness == Brightness.dark
                                ? 0.28
                                : 0.16,
                      ),
                      useOwnLayer: true,
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.w,
                        vertical: 12.h,
                      ),
                      labelStyle: AppTypography.textSmMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      interactionScale: reduceMotion ? 1 : 1.03,
                      stretch: reduceMotion ? 0 : 0.3,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContentSliver(
    FavoritesCombinedGamesState state,
    List<FavoritePlayer> favorites,
  ) {
    if (state.isLoading && state.games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildLoadingState(),
      );
    }

    if (state.error != null && state.games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildErrorState(state.error!),
      );
    }

    if (state.games.isEmpty) {
      if (state.isSearching) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildNoSearchResultsState(),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      );
    }

    // Apply local favorite player chip filter — composes with search results
    var filteredGames = _filterGames(state.games, favorites);

    // Then apply the game filter (result, color, time control, year, rating)
    if (state.filter.hasActiveFilters) {
      filteredGames = GameFilterHelper.applyFilter(filteredGames, state.filter);
    }

    if (filteredGames.isEmpty && _selectedPlayerIds.isNotEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildNoChipResultsState(),
      );
    }

    // Show filter empty state when game filter excludes all games
    if (filteredGames.isEmpty && state.filter.hasActiveFilters) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildNoFilterResultsState(),
      );
    }

    // Show loading indicator when fetching more
    final showLoadingIndicator =
        (state.hasMore || state.isLoading) && filteredGames.isNotEmpty;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index >= filteredGames.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: Center(
                child:
                    state.isLoading
                        ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24.w,
                              height: 24.h,
                              child: CircularProgressIndicator(
                                color: context.colors.textPrimary,
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              'Loading more games...',
                              style: AppTypography.textXsRegular.copyWith(
                                color: context.colors.textSecondary,
                              ),
                            ),
                          ],
                        )
                        : state.hasMore
                        ? const SizedBox.shrink()
                        : Text(
                          'No more games',
                          style: AppTypography.textXsRegular.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
              ),
            );
          }

          final game = filteredGames[index];
          return Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: LiveGamebaseSearchGameCard(
              game: game,
              allGames: filteredGames,
              gameIndex: index,
              animationIndex: index,
              showRound: true,
              streamEnabled: true,
              onAdd: () => _showAddToFolderSheet(context, game),
              onLiveAdd: (liveGame) => _showAddToFolderSheet(context, liveGame),
            ),
          );
        }, childCount: filteredGames.length + (showLoadingIndicator ? 1 : 0)),
      ),
    );
  }

  Widget _buildLoadingState() {
    return _withEntranceMotion(
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48.w,
              height: 48.h,
              child: CircularProgressIndicator(
                color: context.colors.textPrimary,
                strokeWidth: 2.5,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'Loading games...',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Fetching from multiple sources',
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return _withEntranceMotion(
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64.w,
              height: 64.h,
              decoration: BoxDecoration(
                color: context.colors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16.br),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: context.colors.danger,
                size: 32.ic,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'Failed to load games',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.w),
              child: Text(
                error,
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 24.h),
            TextButton(
              onPressed:
                  () =>
                      ref
                          .read(favoritesCombinedGamesProvider.notifier)
                          .refreshGames(),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: context.colors.textPrimary.withValues(
                  alpha: 0.1,
                ),
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.br),
                ),
              ),
              child: Text(
                'Retry',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return _withEntranceMotion(
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80.w,
              height: 80.h,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    context.colors.textPrimary.withValues(alpha: 0.15),
                    context.colors.textPrimary.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(20.br),
              ),
              child: Icon(
                Icons.sports_esports_outlined,
                color: context.colors.textPrimary.withValues(alpha: 0.7),
                size: 40.ic,
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'No games found',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 40.w),
              child: Text(
                'Your favorite players haven\'t played any games yet, or add some favorite players first.',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 24.h),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: context.colors.textPrimary.withValues(
                  alpha: 0.1,
                ),
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.br),
                ),
              ),
              child: Text(
                'Add favorites',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
      scale: true,
    );
  }

  Widget _buildNoSearchResultsState() {
    return _withEntranceMotion(
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 56.sp,
              color: context.colors.iconSecondary,
            ),
            SizedBox(height: 12.h),
            Text(
              'No results',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Try a different filter',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoChipResultsState() {
    final selectedCount = _selectedPlayerIds.length;
    return _withEntranceMotion(
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off_outlined,
              size: 56.sp,
              color: context.colors.iconSecondary,
            ),
            SizedBox(height: 12.h),
            Text(
              selectedCount == 1
                  ? 'No games for this player'
                  : 'No games for these players',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Clear chips or load more games',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20.h),
            TextButton(
              onPressed: _clearAllFilters,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: context.colors.textPrimary.withValues(
                  alpha: 0.1,
                ),
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.br),
                ),
              ),
              child: Text(
                'Clear Chips',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoFilterResultsState() {
    return _withEntranceMotion(
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 56.sp,
              color: context.colors.iconSecondary,
            ),
            SizedBox(height: 12.h),
            Text(
              'No matching games',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Try adjusting your filters',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20.h),
            TextButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                ref.read(favoritesCombinedGamesProvider.notifier).clearFilter();
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: context.colors.textPrimary.withValues(
                  alpha: 0.1,
                ),
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.br),
                ),
              ),
              child: Text(
                'Clear Filters',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _withEntranceMotion(Widget child, {bool scale = false}) {
    if (GlassMotion.reduceMotion(context)) return child;
    if (scale) {
      return child
          .animate()
          .fadeIn(duration: 300.ms)
          .scale(begin: const Offset(0.95, 0.95));
    }
    return child.animate().fadeIn(duration: 300.ms);
  }

  void _showAddToFolderSheet(BuildContext context, GamesTourModel game) {
    showAddToFolderSheet(context: context, game: game);
  }
}
