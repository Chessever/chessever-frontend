import 'dart:async';

import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/miniatures/miniature_player_scorecard_screen.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/library/miniatures/widgets/miniature_players_filter_dialog.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/scroll_to_top_button.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Leaderboard of the players who appear in the most miniatures, on either
/// colour, rendered with the same [FigmaPlayerCard] used by the tournament
/// Standings tab (real avatar photo, W-L in the score slot). Title (GM / IM /
/// FM) and sort live behind the filter icon next to search, matching the
/// Favorites and Countrymen games tabs. Tapping a player opens their own
/// miniature scorecard.
class MiniaturesPlayersTab extends ConsumerStatefulWidget {
  const MiniaturesPlayersTab({super.key});

  @override
  ConsumerState<MiniaturesPlayersTab> createState() =>
      _MiniaturesPlayersTabState();
}

class _MiniaturesPlayersTabState extends ConsumerState<MiniaturesPlayersTab>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 350);

  /// Latched true the first time this tab becomes the selected one.
  bool _activated = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

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
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(miniaturePlayersPaginatedProvider);
      if (!state.isLoading && state.hasMore) {
        ref.read(miniaturePlayersPaginatedProvider.notifier).loadNextPage();
      }
    }
  }

  void _onSearchChanged(String query) {
    final trimmed = query.trim();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (!mounted) return;
      final current = ref.read(miniaturePlayersQueryProvider);
      ref.read(miniaturePlayersQueryProvider.notifier).state = current.copyWith(
        search: trimmed.isEmpty ? null : trimmed,
        clearSearch: trimmed.isEmpty,
      );
    });
  }

  Future<void> _openFilters() async {
    HapticFeedbackService.buttonPress();
    final result = await showMiniaturePlayersFilterDialog(
      context: context,
      currentQuery: ref.read(miniaturePlayersQueryProvider),
    );
    if (result != null && mounted) {
      ref.read(miniaturePlayersQueryProvider.notifier).state = result;
    }
  }

  void _openPlayer(MiniaturePlayer player) {
    HapticFeedbackService.cardTap();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => MiniaturePlayerScorecardScreen(
              player: player,
              avatarHeroTag: player.avatarHeroTag,
            ),
      ),
    );
  }

  /// Maps the leaderboard row onto [PlayerStandingModel] so the card can
  /// reuse [FigmaPlayerCard] verbatim — same avatar, same layout as Standings.
  PlayerStandingModel _toStandingModel(MiniaturePlayer player) {
    return PlayerStandingModel(
      countryCode: CountryUtils.toIso2Code(player.fed ?? ''),
      title: player.title,
      name: player.name,
      score: player.rating ?? 0,
      scoreChange: 0,
      matchScore: '${player.wins}W-${player.losses}L',
      fideId: player.fideId,
      gamebasePlayerId: player.playerId,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // The leaderboard is not fetched until the tab is first opened, but once
    // it has been the watches stay put: dropping them on a tab switch would
    // auto-dispose the paginated provider and reset the list.
    _activated |=
        ref.watch(selectedMiniaturesModeProvider) ==
        MiniaturesScreenMode.players;
    if (!_activated) return const SizedBox.shrink();

    final state = ref.watch(miniaturePlayersPaginatedProvider);
    final query = ref.watch(miniaturePlayersQueryProvider);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref.read(miniaturePlayersPaginatedProvider.notifier).refresh();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: CustomScrollView(
        controller: _scrollController,
        scrollCacheExtent: kListScrollCacheExtent,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                12.h,
                horizontalPadding,
                8.h,
              ),
              child: _buildSearchBar(query),
            ),
          ),
          _buildContentSliver(state, query, horizontalPadding),
          SliverToBoxAdapter(child: SizedBox(height: 24.h)),
        ],
      ),
    );

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
        Positioned(
          bottom: 0,
          right: 0,
          child: ScrollToTopButton(scrollController: _scrollController),
        ),
      ],
    );
  }

  Widget _buildSearchBar(MiniaturePlayersQuery query) {
    final hasActiveFilters = query.hasActiveFilters;
    final activeFilterCount = query.activeFilterCount;
    final searchBarHeight = 48.h;

    return SizedBox(
      height: searchBarHeight,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: context.colors.surfaceRecessed),
              ),
              child: Row(
                children: [
                  SizedBox(width: 12.w),
                  Icon(
                    Icons.search,
                    size: 20.sp,
                    color: context.colors.textSecondary,
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textPrimary,
                      ),
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search players',
                        hintStyle: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty) ...[
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      child: Icon(
                        Icons.close,
                        size: 20.sp,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    SizedBox(width: 8.w),
                  ],
                  SizedBox(width: 8.w),
                ],
              ),
            ),
          ),
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: _openFilters,
            child: Container(
              width: searchBarHeight,
              height: searchBarHeight,
              decoration: BoxDecoration(
                color:
                    hasActiveFilters
                        ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                        : context.colors.background,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(
                  color:
                      hasActiveFilters
                          ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                          : context.colors.surfaceRecessed,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20.sp,
                    color:
                        hasActiveFilters
                            ? const Color(0xFFEF4444)
                            : context.colors.textSecondary,
                  ),
                  if (hasActiveFilters)
                    Positioned(
                      right: 6.w,
                      top: 6.h,
                      child: Container(
                        width: 14.w,
                        height: 14.h,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$activeFilterCount',
                            style: AppTypography.textXsBold.copyWith(
                              color: context.colors.textPrimary,
                              fontSize: 9.sp,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentSliver(
    MiniaturePlayersState state,
    MiniaturePlayersQuery query,
    double horizontalPadding,
  ) {
    if (state.isLoading && state.items.isEmpty) {
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          8.h,
          horizontalPadding,
          24.h,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => const _MiniaturePlayerCardSkeleton(),
            childCount: 10,
          ),
        ),
      );
    }

    if (state.items.isEmpty) {
      final hasQuery =
          query.titles.isNotEmpty ||
          (query.search ?? '').isNotEmpty ||
          query.hasActiveFilters;
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 48.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  state.error != null
                      ? Icons.cloud_off_rounded
                      : Icons.person_search_rounded,
                  size: 40.sp,
                  color: context.colors.textSecondary,
                ),
                SizedBox(height: 16.h),
                Text(
                  state.error != null
                      ? 'Could not load players'
                      : hasQuery
                      ? 'No players match this filter'
                      : 'No players yet',
                  textAlign: TextAlign.center,
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                if (state.error != null) ...[
                  SizedBox(height: 16.h),
                  TextButton(
                    onPressed: () {
                      HapticFeedbackService.buttonPress();
                      ref
                          .read(miniaturePlayersPaginatedProvider.notifier)
                          .refresh();
                    },
                    child: Text(
                      'Try again',
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final showFooter = state.isLoading || !state.hasMore;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        8.h,
        horizontalPadding,
        0,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index >= state.items.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 20.h),
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
                              'Loading more…',
                              style: AppTypography.textXsRegular.copyWith(
                                color: const Color(0xFF71717A),
                              ),
                            ),
                          ],
                        )
                        : Text(
                          'No more players',
                          style: AppTypography.textXsRegular.copyWith(
                            color: const Color(0xFF52525B),
                          ),
                        ),
              ),
            );
          }

          final player = state.items[index];
          return FigmaPlayerCard(
            key: ValueKey('mini_player_${player.playerId}'),
            player: _toStandingModel(player),
            rank: index + 1,
            showFavoriteButton: false,
            avatarHeroTag: player.avatarHeroTag,
            onTap: () => _openPlayer(player),
          );
        }, childCount: state.items.length + (showFooter ? 1 : 0)),
      ),
    );
  }
}

/// Card-shaped shimmer that matches [FigmaPlayerCard] layout (rank + avatar +
/// name/rating + W-L). Plain [Container]s under [SkeletonWidget] do not
/// shimmer because containers are ignored — bones give a real animation.
class _MiniaturePlayerCardSkeleton extends StatelessWidget {
  const _MiniaturePlayerCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final avatarSize = 56.w;
    return SkeletonWidget(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFF1F1F1F), width: 1),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24.w,
              child: Text(
                '00',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(width: 12.w),
            Bone.square(
              size: avatarSize,
              borderRadius: BorderRadius.circular(8.br),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Player Name Placeholder',
                    style: AppTypography.textSmBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '2500',
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: 8.w),
              child: Text(
                '0W-0L',
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
