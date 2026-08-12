import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filter_controls.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/favorite_limit_guard.dart';
import 'package:chessever2/utils/transient_request_retry.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/scroll_to_top_button.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- Provider ---

/// Fetches one page of the country-scoped ranking.
///
/// Behind a provider rather than called straight off the repository so a test
/// can swap it: [ChessPlayerRepository] grabs `Supabase.instance.client` in its
/// field initialiser, so it cannot be faked by subclassing without booting
/// Supabase first.
typedef CountryRankingsFetcher =
    Future<List<ChessPlayer>> Function({
      required String countryCode,
      required RankingFilters filters,
      required String searchQuery,
      required int limit,
      required int offset,
    });

final countryRankingsFetcherProvider = Provider<CountryRankingsFetcher>((ref) {
  return ({
    required String countryCode,
    required RankingFilters filters,
    required String searchQuery,
    required int limit,
    required int offset,
  }) => ref
      .read(chessPlayerRepositoryProvider)
      .getRankedPlayers(
        countryCode: countryCode,
        filters: filters,
        searchQuery: searchQuery,
        limit: limit,
        offset: offset,
      );
});

final countrymenPlayersProvider = StateNotifierProvider.autoDispose<
  CountrymenPlayersNotifier,
  CountrymenPlayersState
>((ref) => CountrymenPlayersNotifier(ref));

class CountrymenPlayersState {
  final List<PlayerStandingModel> players;
  final Set<int> inactivePlayerIds;
  final RankingFilters filters;
  final bool isLoading;
  final bool hasMore;
  final int offset;
  final String searchQuery;
  final String? error;

  const CountrymenPlayersState({
    this.players = const [],
    this.inactivePlayerIds = const {},
    this.filters = RankingFilters.defaults,
    this.isLoading = false,
    this.hasMore = true,
    this.offset = 0,
    this.searchQuery = '',
    this.error,
  });

  bool get isSearching => searchQuery.isNotEmpty;

  CountrymenPlayersState copyWith({
    List<PlayerStandingModel>? players,
    Set<int>? inactivePlayerIds,
    RankingFilters? filters,
    bool? isLoading,
    bool? hasMore,
    int? offset,
    String? searchQuery,
    String? error,
  }) {
    return CountrymenPlayersState(
      players: players ?? this.players,
      inactivePlayerIds: inactivePlayerIds ?? this.inactivePlayerIds,
      filters: filters ?? this.filters,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
      searchQuery: searchQuery ?? this.searchQuery,
      error: error,
    );
  }
}

class CountrymenPlayersNotifier extends StateNotifier<CountrymenPlayersState> {
  CountrymenPlayersNotifier(this._ref)
    : super(const CountrymenPlayersState(isLoading: true)) {
    _loadInitial();

    // Listen to effective country changes (includes temporary selections).
    _ref.listen(effectiveCountryProvider, (previous, next) {
      next.whenData((country) {
        if (previous?.valueOrNull?.countryCode != country.countryCode) {
          refresh();
        }
      });
    });
  }

  final Ref _ref;
  static const int _pageSize = 30;

  /// Bumped by every call that invalidates the visible page (filters, search,
  /// country change). A reply carrying a stale generation is dropped, so a
  /// slow Classical page can never land on top of the Blitz list the user is
  /// already looking at.
  int _requestGeneration = 0;

  String? _getCountryCode() {
    final country = _ref.read(effectiveCountryProvider).valueOrNull;
    if (country == null) return null;
    // Convert to FIDE federation code.
    return CountryUtils.toFideCode(country.countryCode);
  }

  Future<void> _loadInitial() => _fetchPlayers(isInitial: true);

  Future<void> _fetchPlayers({required bool isInitial}) async {
    if (!mounted) return;

    final countryCode = _getCountryCode();
    if (countryCode == null) {
      state = state.copyWith(isLoading: false, hasMore: false);
      return;
    }

    final generation = _requestGeneration;
    final requestedFilters = state.filters;
    final requestedSearch = state.searchQuery;
    final offset = isInitial ? 0 : state.offset;
    state = state.copyWith(isLoading: true);

    try {
      final fetchRankings = _ref.read(countryRankingsFetcherProvider);
      final players = await retryTransientRead(
        () => fetchRankings(
          countryCode: countryCode,
          filters: requestedFilters,
          searchQuery: requestedSearch,
          limit: _pageSize,
          offset: offset,
        ),
      );

      if (!mounted || generation != _requestGeneration) return;

      final playerModels =
          players
              .map(
                (player) => PlayerStandingModel(
                  name: player.name,
                  countryCode: _fideFedToCountryCode(player.country),
                  score: player.ratingFor(requestedFilters.timeControl) ?? 0,
                  scoreChange: 0,
                  matchScore: null,
                  title: player.title,
                  fideId: player.fideid,
                ),
              )
              .toList();
      final allPlayers =
          isInitial ? playerModels : [...state.players, ...playerModels];
      final inactiveIds = <int>{
        if (!isInitial) ...state.inactivePlayerIds,
        ...players.where((player) => player.isInactive).map((p) => p.fideid),
      };

      state = state.copyWith(
        players: allPlayers,
        inactivePlayerIds: inactiveIds,
        isLoading: false,
        hasMore: players.length >= _pageSize,
        offset: offset + players.length,
      );
    } catch (e) {
      debugPrint('[CountrymenRankings] Error: $e');
      if (!mounted || generation != _requestGeneration) return;
      final error = userFacingError(
        e,
        fallback: 'Could not load rankings. Please try again.',
      );
      state = state.copyWith(
        isLoading: false,
        error: state.players.isEmpty ? error : null,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchPlayers(isInitial: false);
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed == state.searchQuery) return;

    _requestGeneration++;
    state = state.copyWith(
      searchQuery: trimmed,
      players: const [],
      inactivePlayerIds: const {},
      offset: 0,
      hasMore: true,
      isLoading: true,
    );
    await _fetchPlayers(isInitial: true);
  }

  Future<void> clearSearch() => search('');

  Future<void> updateFilters(RankingFilters filters) async {
    if (filters == state.filters) return;

    _requestGeneration++;
    state = state.copyWith(
      filters: filters,
      players: const [],
      inactivePlayerIds: const {},
      offset: 0,
      hasMore: true,
      isLoading: true,
    );
    await _fetchPlayers(isInitial: true);
  }

  /// Reloads the list for the current country. Filters and the search term are
  /// deliberately kept: switching country is a change of scope, not a reset of
  /// what the user asked to see.
  Future<void> refresh() async {
    _requestGeneration++;
    state = state.copyWith(
      players: const [],
      inactivePlayerIds: const {},
      offset: 0,
      hasMore: true,
      isLoading: true,
    );
    await _fetchPlayers(isInitial: true);
  }

  /// Convert FIDE federation code to ISO country code.
  String _fideFedToCountryCode(String? fed) {
    if (fed == null || fed.isEmpty) return '';
    return CountryUtils.toIso2Code(fed);
  }
}

// --- Tab Widget ---

class CountrymenPlayersTab extends ConsumerStatefulWidget {
  const CountrymenPlayersTab({super.key});

  @override
  ConsumerState<CountrymenPlayersTab> createState() =>
      _CountrymenPlayersTabState();
}

class _CountrymenPlayersTabState extends ConsumerState<CountrymenPlayersTab>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(countrymenPlayersProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(countrymenPlayersProvider.notifier).search(value);
    });
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(countrymenPlayersProvider.notifier).clearSearch();
  }

  Future<void> _onFiltersChanged(RankingFilters filters) async {
    HapticFeedback.selectionClick();
    _searchFocusNode.unfocus();
    await ref.read(countrymenPlayersProvider.notifier).updateFilters(filters);
    if (!mounted || !_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final state = ref.watch(countrymenPlayersProvider);
    // Watch favoritePlayersProviderNew for up-to-date state
    final favoritesAsync = ref.watch(favoritePlayersProviderNew);
    final favoriteIds =
        favoritesAsync.valueOrNull
            ?.map((p) => int.tryParse(p.fideId ?? ''))
            .where((id) => id != null)
            .cast<int>()
            .toSet() ??
        <int>{};

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref.read(countrymenPlayersProvider.notifier).refresh();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // Search row + ranking filters (scroll with content).
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Only the search row is inset here. The filter strip scrolls
                // horizontally and carries its own inset, so it must span the
                // full width or its edge fade would sit inside a gutter
                // instead of at the screen edge.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    10.h,
                    horizontalPadding,
                    0,
                  ),
                  // Centred so the search field and the Active/All chips share
                  // a mid-line. The chips carry invisible touch padding, so
                  // they are taller than they look and would sit off-axis if
                  // this stretched them instead.
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: SearchBarWidget(
                          hintText: 'Search',
                          margin: 0.sp,
                          autoFocus: false,
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _onSearchChanged,
                          onClose: _clearSearch,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      RankingActivityControl(
                        value: state.filters.activity,
                        onChanged:
                            (value) => _onFiltersChanged(
                              state.filters.copyWith(activity: value),
                            ),
                      ),
                    ],
                  ),
                ),
                RankingFilterControls(
                  filters: state.filters,
                  showActivity: false,
                  horizontalInset: horizontalPadding,
                  onChanged: _onFiltersChanged,
                ),
                SizedBox(height: 4.h),
              ],
            ),
          ),
          // Content
          _buildContentSliver(state, favoriteIds),
          // Bottom padding
          SliverToBoxAdapter(child: SizedBox(height: 24.h)),
        ],
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

    return Stack(
      children: [
        content,
        // Scroll to top button
        Positioned(
          bottom: 0,
          right: 0,
          child: ScrollToTopButton(scrollController: _scrollController),
        ),
      ],
    );
  }

  Widget _buildContentSliver(
    CountrymenPlayersState state,
    Set<int> favoriteIds,
  ) {
    if (state.isLoading && state.players.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildLoadingState(),
      );
    }

    if (state.error != null && state.players.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildErrorState(state.error!),
      );
    }

    if (state.players.isEmpty) {
      if (state.isSearching) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildNoSearchResultsState(),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(state.filters),
      );
    }

    return _buildPlayersSliver(state, favoriteIds);
  }

  Widget _buildPlayersSliver(
    CountrymenPlayersState state,
    Set<int> favoriteIds,
  ) {
    final players = state.players;
    final showLoadingIndicator =
        (state.hasMore || state.isLoading) && players.isNotEmpty;

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 8.h,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index >= players.length) {
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
                              'Loading more players...',
                              style: AppTypography.textXsRegular.copyWith(
                                color: const Color(0xFF71717A),
                              ),
                            ),
                          ],
                        )
                        : state.hasMore
                        ? const SizedBox.shrink()
                        : Text(
                          'No more players',
                          style: AppTypography.textXsRegular.copyWith(
                            color: const Color(0xFF52525B),
                          ),
                        ),
              ),
            );
          }

          final player = players[index];
          final isFavorite = favoriteIds.contains(player.fideId);

          return FigmaPlayerCard(
            player: player,
            isFavorite: isFavorite,
            rank: index + 1,
            // Search results are matches, not standings — numbering them 1..n
            // would claim a national rank the player does not hold.
            showRank: !state.isSearching,
            showFavoriteButton: true,
            isInactive:
                player.fideId != null &&
                state.inactivePlayerIds.contains(player.fideId),
            onTap: () => _navigateToPlayerDetail(player),
            onToggleFavorite: () => _toggleFavorite(player, isFavorite),
          );
        }, childCount: players.length + (showLoadingIndicator ? 1 : 0)),
      ),
    );
  }

  void _navigateToPlayerDetail(PlayerStandingModel player) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => PlayerProfileScreen(
              fideId: player.fideId,
              playerName: player.name,
              title: player.title,
              federation: player.countryCode,
              rating: player.score,
            ),
      ),
    );
  }

  void _toggleFavorite(PlayerStandingModel player, bool currentlyFavorite) {
    // Check auth first, then toggle without blocking
    requireFullAuthGuard(context).then((allowed) async {
      if (!allowed) return;
      if (!mounted) return;

      // Check favorite limit before adding
      if (!currentlyFavorite) {
        final canAdd = await canAddMoreFavorites(context, ref);
        if (!canAdd) return;
      }

      HapticFeedback.mediumImpact();

      try {
        if (currentlyFavorite) {
          await ref
              .read(favoritePlayersProviderNew.notifier)
              .removeFavorite(player.name);
        } else {
          await ref
              .read(favoritePlayersProviderNew.notifier)
              .addFavorite(
                fideId: player.fideId?.toString(),
                playerName: player.name,
                countryCode: player.countryCode,
                rating: player.score,
                title: player.title,
              );
        }
      } on FavoriteLimitExceededException {
        if (mounted) {
          await showPremiumPaywallSheet(context: context);
        }
      } catch (e) {
        debugPrint('Error toggling favorite: $e');
      }
    });
  }

  Widget _buildLoadingState() {
    return Center(
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
            'Loading players...',
            style: AppTypography.textSmRegular.copyWith(
              color: const Color(0xFFA1A1AA),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64.w,
            height: 64.h,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16.br),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: const Color(0xFFEF4444),
              size: 32.ic,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Failed to load players',
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
                color: const Color(0xFFA1A1AA),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 24.h),
          TextButton(
            onPressed:
                () => ref.read(countrymenPlayersProvider.notifier).refresh(),
            style: TextButton.styleFrom(
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
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildEmptyState(RankingFilters filters) {
    final countryAsync = ref.watch(effectiveCountryProvider);
    final countryName = countryAsync.valueOrNull?.name ?? 'your country';
    // An empty page under a narrowed filter is not the same claim as an empty
    // federation — say which one it is rather than blaming the country.
    final message =
        filters == RankingFilters.defaults
            ? 'No registered chess players found from $countryName'
            : 'No ${filters.category.label.toLowerCase()} '
                '${filters.timeControl.label.toLowerCase()} players '
                'from $countryName match these filters';

    return Center(
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
              Icons.people_outline,
              color: context.colors.textPrimary.withValues(alpha: 0.7),
              size: 40.ic,
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'No players found',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              message,
              style: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFA1A1AA),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildNoSearchResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 56.sp,
            color: context.colors.textPrimary.withValues(alpha: 0.4),
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
            'Try a different search term',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}
