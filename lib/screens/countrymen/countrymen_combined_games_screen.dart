import 'dart:async';

import 'package:chessever2/screens/countrymen/provider/countrymen_combined_games_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CountrymenCombinedGamesScreen extends ConsumerStatefulWidget {
  const CountrymenCombinedGamesScreen({super.key});

  @override
  ConsumerState<CountrymenCombinedGamesScreen> createState() =>
      _CountrymenCombinedGamesScreenState();
}

class _CountrymenCombinedGamesScreenState
    extends ConsumerState<CountrymenCombinedGamesScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

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
      final state = ref.read(countrymenCombinedGamesProvider);
      if (state.isSearching) {
        ref.read(countrymenCombinedGamesProvider.notifier).loadMoreSearchResults();
      } else {
        ref.read(countrymenCombinedGamesProvider.notifier).loadMoreGames();
      }
    }
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
    final state = ref.watch(countrymenCombinedGamesProvider);

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () async {
          HapticFeedbackService.medium();
          await ref.read(countrymenCombinedGamesProvider.notifier).refreshGames();
        },
        color: kWhiteColor,
        backgroundColor: kBlack2Color,
        edgeOffset: 120,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // Pinned app bar
            _buildPinnedAppBar(context, state),

            // Pinned search bar
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverSearchBarDelegate(
                child: _buildSearchBar(),
                height: 68.h,
              ),
            ),

            // Content
            _buildContentSliver(state),
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedAppBar(BuildContext context, CountrymenCombinedGamesState state) {
    final countryCode = state.countryCode ?? '';
    final countryName = state.countryName ?? 'Your Country';
    final hasActiveFilters = state.filter.hasActiveFilters;
    final activeFilterCount = state.filter.activeFilterCount;

    return SliverAppBar(
      pinned: true,
      floating: false,
      backgroundColor: kBackgroundColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: 64.h,
      titleSpacing: 0,
      title: Row(
        children: [
          SizedBox(width: 8.w),
          IconButton(
            iconSize: 24.ic,
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_ios_new_outlined,
              size: 22.ic,
              color: kWhiteColor,
            ),
          ),
          SizedBox(width: 8.w),
          if (countryCode.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4.br),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: CountryFlag.fromCountryCode(
                countryCode,
                height: 18.h,
                width: 26.w,
                shape: RoundedRectangle(4.br),
              ),
            ),
            SizedBox(width: 10.w),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  countryName,
                  style: AppTypography.textLgBold.copyWith(
                    color: kWhiteColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Games with 2000+ rated players',
                  style: AppTypography.textXsRegular.copyWith(
                    color: const Color(0xFFA1A1AA),
                  ),
                ),
              ],
            ),
          ),
          // Filter button
          GestureDetector(
            onTap: () => _showFilterDialog(state),
            child: Container(
              padding: EdgeInsets.all(8.w),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 22.ic,
                    color: hasActiveFilters ? kWhiteColor : const Color(0xFFA1A1AA),
                  ),
                  // Badge showing active filter count
                  if (hasActiveFilters)
                    Positioned(
                      right: -4.w,
                      top: -4.h,
                      child: Container(
                        padding: EdgeInsets.all(4.w),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: 16.w,
                          minHeight: 16.h,
                        ),
                        child: Text(
                          '$activeFilterCount',
                          style: AppTypography.textXsBold.copyWith(
                            color: kWhiteColor,
                            fontSize: 10.sp,
                            height: 1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(width: 12.w),
        ],
      ),
    );
  }

  Future<void> _showFilterDialog(CountrymenCombinedGamesState state) async {
    HapticFeedbackService.buttonPress();
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: state.filter,
    );
    if (result != null && mounted) {
      ref.read(countrymenCombinedGamesProvider.notifier).applyFilter(result);
    }
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF09090B),
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: const Color(0xFF27272A)),
        ),
        child: Row(
          children: [
            SizedBox(width: 12.w),
            Icon(
              Icons.search,
              size: 20.sp,
              color: const Color(0xFFA1A1AA),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: AppTypography.textSmRegular.copyWith(
                  color: const Color(0xFFFAFAFA),
                ),
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search',
                  hintStyle: AppTypography.textSmRegular.copyWith(
                    color: const Color(0xFFA1A1AA),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty) ...[
              GestureDetector(
                onTap: _clearSearch,
                child: Icon(
                  Icons.close,
                  size: 20.sp,
                  color: const Color(0xFFA1A1AA),
                ),
              ),
              SizedBox(width: 8.w),
            ],
            SizedBox(width: 8.w),
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
    final showLoadingIndicator = (state.hasMore || state.isLoading) &&
        games.isNotEmpty;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= games.length) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 24.h),
                child: Center(
                  child: state.isLoading
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24.w,
                              height: 24.h,
                              child: const CircularProgressIndicator(
                                color: kWhiteColor,
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              'Loading more games...',
                              style: AppTypography.textXsRegular.copyWith(
                                color: const Color(0xFF71717A),
                              ),
                            ),
                          ],
                        )
                      : state.hasMore
                          ? const SizedBox.shrink()
                          : Text(
                              'No more games',
                              style: AppTypography.textXsRegular.copyWith(
                                color: const Color(0xFF52525B),
                              ),
                            ),
                ),
              );
            }

            final game = games[index];
            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: GamebaseSearchGameCard(
                game: game,
                allGames: games,
                gameIndex: index,
                animationIndex: index,
                showRound: false,
                onAdd: () => _showAddToFolderSheet(context, game),
              ),
            );
          },
          childCount: games.length + (showLoadingIndicator ? 1 : 0),
        ),
      ),
    );
  }

  Widget _buildLoadingState(String countryName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48.w,
            height: 48.h,
            child: CircularProgressIndicator(
              color: kWhiteColor,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Loading games...',
            style: AppTypography.textSmRegular.copyWith(
              color: const Color(0xFFA1A1AA),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Finding games from $countryName',
            style: AppTypography.textXsRegular.copyWith(
              color: const Color(0xFF71717A),
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
            'Failed to load games',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
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
            onPressed: () => ref
                .read(countrymenCombinedGamesProvider.notifier)
                .refreshGames(),
            style: TextButton.styleFrom(
              backgroundColor: kWhiteColor.withValues(alpha: 0.1),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.br),
              ),
            ),
            child: Text(
              'Retry',
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildEmptyState(String countryName) {
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
                  kWhiteColor.withValues(alpha: 0.15),
                  kWhiteColor.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20.br),
            ),
            child: Icon(
              Icons.public_outlined,
              color: kWhiteColor.withValues(alpha: 0.7),
              size: 40.ic,
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'No games found',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              'No recent games found for players from $countryName with rating 2300+',
              style: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFA1A1AA),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 24.h),
          TextButton(
            onPressed: () => ref
                .read(countrymenCombinedGamesProvider.notifier)
                .refreshGames(),
            style: TextButton.styleFrom(
              backgroundColor: kWhiteColor.withValues(alpha: 0.1),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.br),
              ),
            ),
            child: Text(
              'Refresh',
              style: AppTypography.textSmMedium.copyWith(
                color: kWhiteColor,
              ),
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
            color: kWhiteColor.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No results',
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try a different search term',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildNoFilterResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 56.sp,
            color: kWhiteColor.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No matching games',
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try adjusting your filters',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20.h),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              ref.read(countrymenCombinedGamesProvider.notifier).clearFilter();
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: kWhiteColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Text(
                'Clear Filters',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor,
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  void _showAddToFolderSheet(BuildContext context, GamesTourModel game) {
    showAddToFolderSheet(context: context, game: game);
  }
}

/// Delegate for pinned search bar in sliver list
class _SliverSearchBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverSearchBarDelegate({
    required this.child,
    required this.height,
  });

  final Widget child;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Use SizedBox to ensure the child respects the exact height
    // This prevents layoutExtent from exceeding paintExtent
    return SizedBox(
      height: maxExtent,
      child: Container(
        color: kBackgroundColor,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(_SliverSearchBarDelegate oldDelegate) {
    return child != oldDelegate.child || height != oldDelegate.height;
  }
}
