import 'dart:async';

import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_combined_games_provider.dart';
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
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_stack.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class CountrymenCombinedGamesScreen extends ConsumerStatefulWidget {
  const CountrymenCombinedGamesScreen({super.key});

  @override
  ConsumerState<CountrymenCombinedGamesScreen> createState() =>
      _CountrymenCombinedGamesScreenState();
}

class _CountrymenCombinedGamesScreenState
    extends ConsumerState<CountrymenCombinedGamesScreen>
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

  String get _liveCardsPauseReason => 'countrymen_combined_scroll_$hashCode';
  // Keep rendering while backgrounded so the OS app-switcher snapshot is not
  // blank. Route coverage still removes the screen from active provider work.
  bool get _isActiveOnScreen => _routeIsCurrent;

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
    ForegroundTaskScheduler.cancel('countrymen_combined_resume_$hashCode');
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
      ForegroundTaskScheduler.cancel('countrymen_combined_resume_$hashCode');
      _setAppResumed(false);
      return;
    }
    if (!mounted) return;

    _setAppResumed(true);
    ForegroundTaskScheduler.schedule(
      key: 'countrymen_combined_resume_$hashCode',
      task: () {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route?.isCurrent != true) return;

        ref.invalidate(gameUpdatesStreamProvider);
        ref.invalidate(liveGameUpdateStreamProvider);
        ref.invalidate(gameUpdatesBatchStreamProvider);
        unawaited(
          ref.read(countrymenCombinedGamesProvider.notifier).refreshGames(),
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
      ForegroundTaskScheduler.cancel('countrymen_combined_resume_$hashCode');
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
      final state = ref.read(countrymenCombinedGamesProvider);
      if (state.isSearching) {
        ref
            .read(countrymenCombinedGamesProvider.notifier)
            .loadMoreSearchResults();
      } else {
        ref.read(countrymenCombinedGamesProvider.notifier).loadMoreGames();
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
      ref.read(countrymenCombinedGamesProvider.notifier).searchGames(value);
    });
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(countrymenCombinedGamesProvider.notifier).clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isActiveOnScreen) {
      return const SizedBox.shrink();
    }

    final state = ref.watch(countrymenCombinedGamesProvider);
    final controlExtent = _controlExtent(context);
    final topContentInset = _topContentInset(context);

    return GlassFullScreenPage(
      backgroundColor: context.colors.background,
      includeContentSafeArea: false,
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: GlassIslandStack(
            includeStatusBar: false,
            gap: 8,
            children: [
              _buildTopBar(context, state, controlExtent),
              _buildSearchBar(controlExtent),
            ],
          ),
        ),
      ),
      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: RefreshIndicator(
            onRefresh: () async {
              HapticFeedbackService.medium();
              await ref
                  .read(countrymenCombinedGamesProvider.notifier)
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
                // This spacer scrolls away with the content. It protects the
                // first card at rest without creating a sticky top region.
                SliverToBoxAdapter(child: SizedBox(height: topContentInset)),
                _buildContentSliver(state),
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

  double _topContentInset(BuildContext context) {
    final controlExtent = _controlExtent(context);
    const overlayTopPadding = 4.0;
    const topBarBottomPadding = 6.0;
    const rowGap = 8.0;
    const stackBottomPadding = 4.0;
    const contentGap = 8.0;
    return MediaQuery.viewPaddingOf(context).top +
        overlayTopPadding +
        (controlExtent * 2) +
        topBarBottomPadding +
        rowGap +
        stackBottomPadding +
        contentGap;
  }

  double _bottomContentInset(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.viewPadding.bottom + media.viewInsets.bottom + 24.h;
  }

  Widget _buildTopBar(
    BuildContext context,
    CountrymenCombinedGamesState state,
    double controlExtent,
  ) {
    final countryCode = state.countryCode ?? '';
    final countryName = state.countryName ?? 'Your Country';
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
        label: countryName,
        height: controlExtent,
        maxWidth: 200.w,
        icon:
            countryCode.isEmpty
                ? null
                : CountryFlag.fromCountryCode(
                  countryCode,
                  theme: ImageTheme(
                    height: 14.h,
                    width: 20.w,
                    shape: RoundedRectangle(3.br),
                  ),
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

  Future<void> _showFilterDialog(CountrymenCombinedGamesState state) async {
    HapticFeedbackService.buttonPress();
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: state.filter,
      showFormatFilter: false,
    );
    if (result != null && mounted) {
      ref.read(countrymenCombinedGamesProvider.notifier).applyFilter(result);
    }
  }

  Widget _buildSearchBar(double controlExtent) {
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
                if (value.text.isEmpty) return SizedBox(width: 8.w);
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

  Widget _buildContentSliver(CountrymenCombinedGamesState state) {
    if (state.isLoading && state.games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildLoadingState(state.countryName ?? 'your country'),
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
        child: _buildEmptyState(state.countryName ?? 'your country'),
      );
    }

    // Use filtered games based on filter settings
    final games = state.filteredGames;

    // Show empty state if filter excludes all games
    if (games.isEmpty && state.filter.hasActiveFilters) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildNoFilterResultsState(),
      );
    }

    // Show loading indicator when fetching more
    final showLoadingIndicator =
        (state.hasMore || state.isLoading) && games.isNotEmpty;

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 32.w,
    );
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 4.h,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index >= games.length) {
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

          final game = games[index];
          return Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: LiveGamebaseSearchGameCard(
              game: game,
              allGames: games,
              gameIndex: index,
              animationIndex: index,
              showRound: true,
              streamEnabled: true,
              onAdd: () => _showAddToFolderSheet(context, game),
              onLiveAdd: (liveGame) => _showAddToFolderSheet(context, liveGame),
            ),
          );
        }, childCount: games.length + (showLoadingIndicator ? 1 : 0)),
      ),
    );
  }

  Widget _buildLoadingState(String countryName) {
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
              'Finding games from $countryName',
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
                          .read(countrymenCombinedGamesProvider.notifier)
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

  Widget _buildEmptyState(String countryName) {
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
                Icons.public_outlined,
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
                'No recent games found for players from $countryName',
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
                          .read(countrymenCombinedGamesProvider.notifier)
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
                'Refresh',
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
              'Try a different search term',
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
                ref
                    .read(countrymenCombinedGamesProvider.notifier)
                    .clearFilter();
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
