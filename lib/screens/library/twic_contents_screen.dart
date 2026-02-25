import 'dart:async';

import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/gamebase_filter_provider.dart';
import 'package:chessever2/screens/library/providers/twic_event_aggregates_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:chessever2/screens/library/widgets/library_search_bar.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// TWIC book contents screen.
///
/// Queries the gamebase (4M+ games) with search, filters, and pagination.
/// Uses [gamebaseDatabaseGamesPaginatedProvider] directly for a focused
/// game-only experience with infinite scroll.
class TwicContentsScreen extends ConsumerStatefulWidget {
  const TwicContentsScreen({super.key});

  @override
  ConsumerState<TwicContentsScreen> createState() => _TwicContentsScreenState();
}

class _TwicContentsScreenState extends ConsumerState<TwicContentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _chipScrollController = ScrollController();

  // Scroll-collapse state
  bool _showChipRow = true;
  double _lastScrollOffset = 0.0;
  double _scrollAccumulator = 0.0;
  static const _scrollCollapseThreshold = 40.0;

  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _chipScrollController.addListener(_onChipScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _chipScrollController.removeListener(_onChipScroll);
    _scrollController.dispose();
    _chipScrollController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Pagination trigger
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(gamebaseDatabaseGamesPaginatedProvider);
      if (!state.isLoading && state.hasMore) {
        ref
            .read(gamebaseDatabaseGamesPaginatedProvider.notifier)
            .loadNextPage();
      }
    }

    // Scroll-collapse direction detection
    final offset = _scrollController.position.pixels;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    // Force show at top
    if (offset <= 0) {
      if (!_showChipRow) setState(() => _showChipRow = true);
      _scrollAccumulator = 0.0;
      return;
    }

    // Reset accumulator on direction change
    if ((delta > 0 && _scrollAccumulator < 0) ||
        (delta < 0 && _scrollAccumulator > 0)) {
      _scrollAccumulator = 0.0;
    }
    _scrollAccumulator += delta;

    if (_scrollAccumulator > _scrollCollapseThreshold && _showChipRow) {
      setState(() => _showChipRow = false);
    } else if (_scrollAccumulator < -_scrollCollapseThreshold &&
        !_showChipRow) {
      setState(() => _showChipRow = true);
    }
  }

  void _onChipScroll() {
    if (!_chipScrollController.hasClients) return;
    if (_chipScrollController.position.pixels >=
        _chipScrollController.position.maxScrollExtent - 150) {
      final eventState = ref.read(twicEventAggregatesPaginatedProvider);
      if (!eventState.isLoading && eventState.hasMore) {
        ref.read(twicEventAggregatesPaginatedProvider.notifier).loadNextPage();
      }
    }
  }

  void _onSearchChanged(String query) {
    final trimmed = query.trim();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted) {
        ref.read(twicSelectedEventProvider.notifier).state = null;
        ref.read(librarySearchQueryProvider.notifier).state = trimmed;
      }
    });
  }

  Future<void> _openFilters() async {
    HapticFeedbackService.light();

    final currentFilter = ref.read(gamebaseFilterProvider);
    final newFilter = await showLibraryGamebaseFilterDialog(
      context: context,
      currentFilter: currentFilter,
    );

    if (newFilter != null) {
      ref.read(gamebaseFilterProvider.notifier).state = newFilter;
    }
  }

  void _toggleSelectedEvent(String? event, {int chipIndex = 0}) {
    final current = ref.read(twicSelectedEventProvider);
    if (event == null || event.trim().isEmpty) {
      ref.read(twicSelectedEventProvider.notifier).state = null;
      _scrollChipToIndex(0);
      return;
    }
    final normalized = event.trim();
    final isDeselecting = current == normalized;
    ref.read(twicSelectedEventProvider.notifier).state =
        isDeselecting ? null : normalized;
    _scrollChipToIndex(isDeselecting ? 0 : chipIndex);
  }

  void _scrollChipToIndex(int index) {
    if (!_chipScrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chipScrollController.hasClients) return;
      final estimatedItemWidth = 200.w + 8.w;
      final viewportWidth = _chipScrollController.position.viewportDimension;
      final targetOffset =
          (index * estimatedItemWidth) -
          (viewportWidth / 2) +
          (estimatedItemWidth / 2);
      _chipScrollController.animateTo(
        targetOffset.clamp(0.0, _chipScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: ScreenWrapper(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  ResponsiveHelper.isTablet
                      ? ResponsiveHelper.contentMaxWidth
                      : double.infinity,
            ),
            child: Column(
              children: [_buildTopArea(), Expanded(child: _buildContent())],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header & Search
  // ---------------------------------------------------------------------------

  Widget _buildTopArea() {
    final topPadding = MediaQuery.of(context).viewPadding.top;

    return Container(
      padding: EdgeInsets.only(top: topPadding + 8.h, bottom: 6.h),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kBlackColor, kBackgroundColor],
        ),
      ),
      child: Column(
        children: [_buildHeader(), _buildSearchRow(), _buildResultCount()],
      ),
    );
  }

  Widget _buildHeader() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 8.w,
      tablet: 16.w,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        8.h,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () {
                HapticFeedbackService.light();
                Navigator.of(context).pop();
              },
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: kWhiteColor.withValues(alpha: 0.7),
                size: 20.ic,
              ),
            ),
          ),
          Opacity(
            opacity: 0.8,
            child: Text(
              'TWIC Database',
              style: AppTypography.textMdMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: kWhiteColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        8.h,
      ),
      child: LibrarySearchBar(
        controller: _searchController,
        focusNode: _searchFocusNode,
        enableOverlay: false,
        hintText: 'Search',
        onChanged: _onSearchChanged,
        onFilterTap: _openFilters,
      ),
    );
  }

  Widget _buildResultCount() {
    final paginationState = ref.watch(gamebaseDatabaseGamesPaginatedProvider);
    final searchQuery = ref.watch(librarySearchQueryProvider).trim();
    final hasActiveFilters = ref.watch(hasActiveGamebaseFiltersProvider);
    final selectedEvent = ref.watch(twicSelectedEventProvider);
    final rootTotalAsync = ref.watch(twicDatabaseTotalGamesProvider);

    final isDefaultView =
        searchQuery.isEmpty &&
        !hasActiveFilters &&
        (selectedEvent == null || selectedEvent.trim().isEmpty);

    final int? totalCount;
    final bool isEstimate;

    if (isDefaultView) {
      // Never show the estimated search count on default TWIC view.
      final exactTotal = rootTotalAsync.valueOrNull;
      totalCount = (exactTotal != null && exactTotal > 0) ? exactTotal : null;
      isEstimate = false;
    } else {
      final fallbackTotal =
          paginationState.totalCount > 0 ? paginationState.totalCount : null;
      totalCount = fallbackTotal;
      isEstimate = paginationState.totalCountIsEstimate;
    }

    if (totalCount == null || totalCount <= 0) return const SizedBox.shrink();

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        4.h,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${isEstimate ? '~' : ''}${formatCompactCount(totalCount)} games',
          style: AppTypography.textXsRegular.copyWith(
            color: kWhiteColor.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Content — event row is always stable; game list handles its own loading
  // ---------------------------------------------------------------------------

  Widget _buildContent() {
    final paginationState = ref.watch(gamebaseDatabaseGamesPaginatedProvider);
    final selectedEvent = ref.watch(twicSelectedEventProvider);
    final eventState = ref.watch(twicEventAggregatesPaginatedProvider);
    final eventCards = ref.watch(twicEventCardModelsProvider);
    final hasUserInput = ref.watch(hasUserInputProvider);

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    // Build display items from paginated event state
    final aggregates = eventState.events;
    final eventItems = <_TwicEventDisplayItem>[];
    for (var i = 0; i < eventCards.length; i++) {
      final agg = i < aggregates.length ? aggregates[i] : null;
      eventItems.add(
        _TwicEventDisplayItem(
          event: eventCards[i].title,
          gameCount: agg?.gameCount ?? 0,
          cardModel: eventCards[i],
          avgElo: agg?.avgElo,
          maxElo: agg?.maxElo,
          site: agg?.site,
          startDate: agg?.startDate,
          endDate: agg?.endDate,
          timeControl: agg?.dominantTimeControl,
        ),
      );
    }

    // Find selected event item for detail bar
    final selectedItem =
        selectedEvent != null
            ? eventItems.cast<_TwicEventDisplayItem?>().firstWhere(
              (item) => item!.event == selectedEvent,
              orElse: () => null,
            )
            : null;

    // Determine event row widget — hidden when no user input
    Widget eventRow;
    if (!hasUserInput) {
      eventRow = const SizedBox.shrink();
    } else if (eventState.isLoading && eventItems.isEmpty) {
      eventRow = _buildSkeletonCardsRow(horizontalPadding);
    } else if (eventItems.isNotEmpty) {
      eventRow = _buildEventCardsRow(
        eventItems: eventItems,
        selectedEvent: selectedEvent,
        horizontalPadding: horizontalPadding,
        isLoadingMore: eventState.isLoading && eventItems.isNotEmpty,
        hasMore: eventState.hasMore,
      );
    } else {
      eventRow = const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Collapsible chip row + detail bar ──
        _buildCollapsibleHeader(
          eventRow: eventRow,
          selectedItem: selectedItem,
          horizontalPadding: horizontalPadding,
        ),

        // ── Games list (keeps previous content while loading new results) ──
        Expanded(child: _buildGamesList(paginationState, horizontalPadding)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Collapsible header — scroll-linked collapse of chip row + detail bar
  // ---------------------------------------------------------------------------

  Widget _buildCollapsibleHeader({
    required Widget eventRow,
    required _TwicEventDisplayItem? selectedItem,
    required double horizontalPadding,
  }) {
    return SingleMotionBuilder(
      motion: const CupertinoMotion.snappy(),
      value: _showChipRow ? 1.0 : 0.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          eventRow,
          _buildSelectedEventDetailBar(
            selectedItem: selectedItem,
            horizontalPadding: horizontalPadding,
          ),
        ],
      ),
      builder: (context, progress, child) {
        final clamped = progress.clamp(0.0, 1.0);
        return ClipRect(
          child: Align(
            heightFactor: clamped,
            alignment: Alignment.topCenter,
            child: Opacity(opacity: clamped, child: child),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Games list — shimmer overlay while loading, staggered entry animations
  // ---------------------------------------------------------------------------

  Widget _buildGamesList(
    DatabaseGamesPaginationState paginationState,
    double horizontalPadding,
  ) {
    final games = paginationState.games;

    // Error with no games at all
    if (paginationState.error != null && games.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 40.sp,
                color: kWhiteColor.withValues(alpha: 0.3),
              ),
              SizedBox(height: 12.h),
              Text(
                'Search failed',
                style: AppTypography.textSmRegular.copyWith(
                  color: const Color(0xFFA1A1AA),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // No games and not loading — empty state
    if (games.isEmpty && !paginationState.isLoading) {
      return Center(
        child: Text(
          'No games found',
          style: AppTypography.textSmRegular.copyWith(
            color: const Color(0xFFA1A1AA),
          ),
        ),
      );
    }

    // Initial load — show skeleton game cards
    if (games.isEmpty && paginationState.isLoading) {
      return _buildSkeletonGamesList(horizontalPadding);
    }

    final itemCount = games.length + (paginationState.hasMore ? 1 : 0);
    // Show shimmer overlay on existing list when loading new page 1 results
    // (i.e. filter/event changed and games are being replaced)
    final isRefreshing =
        paginationState.isLoading && paginationState.currentPage <= 1;

    Widget list = ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        100.h,
      ),
      itemCount: itemCount,
      separatorBuilder: (_, __) => SizedBox(height: 12.h),
      itemBuilder: (context, index) {
        // Load-more indicator at the end
        if (index >= games.length) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: kWhiteColor,
                  strokeWidth: 2,
                ),
              ),
            ),
          );
        }

        final game = games[index];
        return GamebaseSearchGameCard(
          game: game,
          allGames: games,
          gameIndex: index,
          animationIndex: index,
          onAdd: () => showAddToFolderSheet(context: context, game: game),
          showSwipeHint: index == 0,
          hideEventInfo: false,
          playerProfileDataSource: PlayerProfileDataSource.twic,
        );
      },
    );

    if (isRefreshing) {
      list = AnimatedOpacity(
        opacity: 0.4,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(child: list),
      );
    }

    return list;
  }

  Widget _buildSkeletonGamesList(double horizontalPadding) {
    return Skeletonizer(
      enabled: true,
      ignoreContainers: true,
      effect: const ShimmerEffect(
        baseColor: Color(0xFF2E2E32),
        highlightColor: Color(0xFF48484E),
        duration: Duration(milliseconds: 1200),
      ),
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          0,
          horizontalPadding,
          100.h,
        ),
        itemCount: 10,
        separatorBuilder: (_, __) => SizedBox(height: 12.h),
        itemBuilder: (context, index) => const _SkeletonGameCard(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Event cards row (mini cards with image thumbnails)
  // ---------------------------------------------------------------------------

  Widget _buildEventCardsRow({
    required List<_TwicEventDisplayItem> eventItems,
    required String? selectedEvent,
    required double horizontalPadding,
    required bool isLoadingMore,
    required bool hasMore,
  }) {
    // +1 for "All" chip at start, +1 for loading indicator if loading more
    final extraEnd = isLoadingMore ? 1 : 0;
    final itemCount = eventItems.length + 1 + extraEnd;

    return Padding(
      padding: EdgeInsets.fromLTRB(0, 6.h, 0, 12.h),
      child: SizedBox(
        height: 40.h,
        child: ListView.separated(
          controller: _chipScrollController,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          itemCount: itemCount,
          separatorBuilder: (_, __) => SizedBox(width: 8.w),
          itemBuilder: (context, index) {
            final isAllChip = index == 0;

            // Loading indicator at the end
            if (index > eventItems.length) {
              return SizedBox(
                width: 32.w,
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: kWhiteColor,
                      strokeWidth: 1.5,
                    ),
                  ),
                ),
              );
            }

            final isSelected =
                isAllChip
                    ? selectedEvent == null
                    : selectedEvent == eventItems[index - 1].event;

            if (isAllChip) {
              return _TwicEventCard(
                label: 'All Events',
                isSelected: isSelected,
                isAllCard: true,
                onTap: () => _toggleSelectedEvent(null, chipIndex: 0),
              );
            }

            final item = eventItems[index - 1];
            return _TwicEventCard(
              label: item.event,
              gameCount: item.gameCount,
              isSelected: isSelected,
              isAllCard: false,
              onTap: () => _toggleSelectedEvent(item.event, chipIndex: index),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSkeletonCardsRow(double horizontalPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 6.h, 0, 12.h),
      child: SizedBox(
        height: 40.h,
        child: Skeletonizer(
          enabled: true,
          ignoreContainers: true,
          effect: const ShimmerEffect(
            baseColor: Color(0xFF2E2E32),
            highlightColor: Color(0xFF48484E),
            duration: Duration(milliseconds: 1200),
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            itemCount: 5,
            separatorBuilder: (_, __) => SizedBox(width: 8.w),
            itemBuilder: (context, index) {
              return Bone(
                width: index == 0 ? 50.w : (80 + index * 20).w,
                height: 40.h,
                borderRadius: BorderRadius.circular(999.br),
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Selected Event Detail Bar (replaces event cards carousel)
  // ---------------------------------------------------------------------------

  Widget _buildSelectedEventDetailBar({
    required _TwicEventDisplayItem? selectedItem,
    required double horizontalPadding,
  }) {
    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      value: selectedItem != null ? 1.0 : 0.0,
      builder: (context, progress, child) {
        if (progress < 0.01) return const SizedBox.shrink();
        final clamped = progress.clamp(0.0, 1.0);
        return ClipRect(
          child: Align(
            heightFactor: clamped,
            alignment: Alignment.topCenter,
            child: Opacity(
              opacity: clamped,
              child: Transform.translate(
                offset: Offset(-12 * (1 - clamped), 0),
                child: child,
              ),
            ),
          ),
        );
      },
      child:
          selectedItem != null
              ? _buildDetailBarContent(selectedItem, horizontalPadding)
              : const SizedBox.shrink(),
    );
  }

  Widget _buildDetailBarContent(
    _TwicEventDisplayItem item,
    double horizontalPadding,
  ) {
    final infoStyle = AppTypography.textXsRegular.copyWith(
      color: kWhiteColor.withValues(alpha: 0.55),
    );
    final separatorStyle = infoStyle.copyWith(
      color: kWhiteColor.withValues(alpha: 0.3),
    );

    final infoParts = <Widget>[];

    if (item.site != null && item.site!.trim().isNotEmpty) {
      infoParts.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_rounded,
              size: 11.ic,
              color: kWhiteColor.withValues(alpha: 0.45),
            ),
            SizedBox(width: 2.w),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 120.w),
              child: Text(
                item.site!.trim(),
                style: infoStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final dateStr = TimeUtils.formatDateRange(item.startDate, item.endDate);
    if (dateStr.isNotEmpty) {
      infoParts.add(Text(dateStr, style: infoStyle));
    }

    if (item.avgElo != null) {
      infoParts.add(Text('\u2300${item.avgElo}', style: infoStyle));
    }

    if (item.maxElo != null) {
      infoParts.add(Text('\u2605${item.maxElo}', style: infoStyle));
    }

    final infoChildren = <Widget>[];
    for (var i = 0; i < infoParts.length; i++) {
      if (i > 0) {
        infoChildren.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 5.w),
            child: Text('\u00B7', style: separatorStyle),
          ),
        );
      }
      infoChildren.add(infoParts[i]);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        10.h,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.br),
        child: Container(
          decoration: BoxDecoration(
            color: kBlack2Color,
            border: Border(left: BorderSide(color: kPrimaryColor, width: 2.5)),
          ),
          padding: EdgeInsets.fromLTRB(12.w, 10.h, 8.w, 10.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.event,
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  GestureDetector(
                    onTap: () {
                      HapticFeedbackService.light();
                      ref.read(twicSelectedEventProvider.notifier).state = null;
                      _scrollChipToIndex(0);
                    },
                    child: Container(
                      padding: EdgeInsets.all(4.w),
                      decoration: BoxDecoration(
                        color: kWhiteColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6.br),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 14.ic,
                        color: kWhiteColor.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
              if (infoChildren.isNotEmpty) ...[
                SizedBox(height: 4.h),
                Row(children: infoChildren),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton game card — mirrors LibraryGameCard layout for Skeletonizer
// ---------------------------------------------------------------------------

class _SkeletonGameCard extends StatelessWidget {
  const _SkeletonGameCard();

  // Passive variants of real LibraryGameCard colors:
  // Real top gradient: 0xFFDDDDE0 → 0xFFADAEB3
  // Real bottom: 0xFF1A1A1C
  // Real outer: 0xFF2E2E2E
  static const _outerBg = Color(0xFF242426);
  static const _topBg = Color(0xFF38383C);
  static const _bottomBg = Color(0xFF1C1C1E);
  static const _boneRadius = 4.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _outerBg,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        children: [
          // Top section — muted version of the light player area
          Container(
            padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 10.h),
            decoration: BoxDecoration(
              color: _topBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12.br)),
            ),
            child: Row(
              children: [
                // Left player
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Bone(
                        width: 100.w,
                        height: 14.h,
                        borderRadius: BorderRadius.circular(_boneRadius.br),
                      ),
                      SizedBox(height: 4.h),
                      Bone(
                        width: 60.w,
                        height: 12.h,
                        borderRadius: BorderRadius.circular(_boneRadius.br),
                      ),
                    ],
                  ),
                ),
                // Center result
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10.w),
                  child: Bone(
                    width: 40.w,
                    height: 20.h,
                    borderRadius: BorderRadius.circular(_boneRadius.br),
                  ),
                ),
                // Right player
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Bone(
                          width: 90.w,
                          height: 14.h,
                          borderRadius: BorderRadius.circular(_boneRadius.br),
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Bone(
                          width: 50.w,
                          height: 12.h,
                          borderRadius: BorderRadius.circular(_boneRadius.br),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Bottom section — muted dark bar
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 5.h),
            decoration: BoxDecoration(
              color: _bottomBg,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(12.br),
              ),
            ),
            child: Row(
              children: [
                Bone.square(
                  size: 14.sp,
                  borderRadius: BorderRadius.circular(2.br),
                ),
                SizedBox(width: 4.w),
                Bone(
                  width: 120.w,
                  height: 12.h,
                  borderRadius: BorderRadius.circular(_boneRadius.br),
                ),
                const Spacer(),
                Bone(
                  width: 60.w,
                  height: 12.h,
                  borderRadius: BorderRadius.circular(_boneRadius.br),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class _TwicEventDisplayItem {
  const _TwicEventDisplayItem({
    required this.event,
    required this.gameCount,
    required this.cardModel,
    this.avgElo,
    this.maxElo,
    this.site,
    this.startDate,
    this.endDate,
    this.timeControl,
  });

  final String event;
  final int gameCount;
  final GroupEventCardModel cardModel;
  final int? avgElo;
  final int? maxElo;
  final String? site;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? timeControl;
}

// ---------------------------------------------------------------------------
// Stadium chip for event selection — motor press scale + selection bounce
// ---------------------------------------------------------------------------

class _TwicEventCard extends StatefulWidget {
  final String label;
  final int? gameCount;
  final bool isSelected;
  final bool isAllCard;
  final VoidCallback onTap;

  const _TwicEventCard({
    required this.label,
    required this.isSelected,
    required this.isAllCard,
    required this.onTap,
    this.gameCount,
  });

  @override
  State<_TwicEventCard> createState() => _TwicEventCardState();
}

class _TwicEventCardState extends State<_TwicEventCard> {
  double _pressScale = 1.0;

  void _onTapDown(TapDownDetails _) {
    setState(() => _pressScale = 0.92);
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _pressScale = 1.0);
    HapticFeedbackService.light();
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
              final bgColor =
                  Color.lerp(
                    kBlack2Color,
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
                  Color.lerp(
                    kWhiteColor.withValues(alpha: 0.7),
                    kPrimaryColor,
                    selectProgress,
                  )!;
              final borderWidth = selectProgress * 2.0;
              final selectScale = 1.0 + (selectProgress * 0.04);
              final combinedScale = pressScale * selectScale;
              final clampedSelect = selectProgress.clamp(0.0, 1.0);

              return Transform.scale(
                scale: combinedScale,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 6.h,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(999.br),
                    border:
                        borderWidth > 0.01
                            ? Border.all(color: borderColor, width: borderWidth)
                            : null,
                    boxShadow:
                        clampedSelect > 0.01
                            ? [
                              BoxShadow(
                                color: kPrimaryColor.withValues(
                                  alpha: 0.25 * clampedSelect,
                                ),
                                blurRadius: 10 * clampedSelect,
                              ),
                            ]
                            : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.label,
                          style: AppTypography.textXsMedium.copyWith(
                            color: labelColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.gameCount != null && !widget.isAllCard) ...[
                        SizedBox(width: 4.w),
                        Text(
                          '${widget.gameCount}',
                          style: AppTypography.textXsRegular.copyWith(
                            color: labelColor.withValues(alpha: 0.6),
                            fontSize: 10.sp,
                          ),
                        ),
                      ],
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
