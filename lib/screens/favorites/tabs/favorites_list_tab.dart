import 'dart:async';

import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/tablet_safe_menu.dart';
import 'package:chessever2/widgets/scroll_to_top_button.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:chessever2/widgets/standing_score_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';

class FavoritesListTab extends ConsumerStatefulWidget {
  const FavoritesListTab({super.key});

  @override
  ConsumerState<FavoritesListTab> createState() => _FavoritesListTabState();
}

class _FavoritesListTabState extends ConsumerState<FavoritesListTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    _focusNode.unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Stack(
      children: [
        ref.watch(favoritePlayersNotifierProvider).when(
          data: (_) {
            final filteredPlayers = ref.read(
              filteredFavoritePlayersProvider(_searchController.text),
            );
            return _buildContent(filteredPlayers);
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: kWhiteColor),
          ),
          error: (error, stack) => _buildErrorState(error.toString()),
        ),
        // Scroll to top button
        Positioned(
          bottom: 0,
          right: 0,
          child: ScrollToTopButton(scrollController: _scrollController),
        ),
      ],
    );
  }

  Widget _buildContent(List<PlayerStandingModel> filteredPlayers) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.contentMaxWidth,
        ),
        child: RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref
            .read(favoritePlayersNotifierProvider.notifier)
            .refreshFavorites();
      },
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
              child: AnimatedBuilder(
                animation: _searchController,
                builder: (context, _) {
                  return SearchBarWidget(
                    hintText: 'Search favorites',
                    margin: 0.sp,
                    autoFocus: false,
                    controller: _searchController,
                    focusNode: _focusNode,
                    onChanged: (_) => setState(() {}),
                    onClose: _clearSearch,
                  );
                },
              ),
            ),
          ),

          // Content
          _buildPlayersSliver(filteredPlayers),

          // Bottom padding
          SliverToBoxAdapter(child: SizedBox(height: 24.h)),
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildPlayersSliver(List<PlayerStandingModel> players) {
    if (players.isEmpty) {
      if (_searchController.text.isNotEmpty) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyState(
            'No players found',
            'No favorites match "${_searchController.text}"',
          ),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(
          'No favorite players yet',
          'Tap the heart icon on players to add them to favorites',
        ),
      );
    }

    final sortedPlayers = [...players]
      ..sort((a, b) => b.score.compareTo(a.score));

    // Tablet-specific padding
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 24.sp,
    );

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            // First item is the column header
            if (index == 0) {
              return Padding(
                padding: EdgeInsets.only(bottom: 4.h),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.sp),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Rank header
                      SizedBox(
                        width: 28.w,
                        child: Text(
                          '#',
                          style: AppTypography.textSmMedium.copyWith(
                            color: kWhiteColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            SizedBox(width: 20.w),
                            Flexible(
                              child: Text(
                                'Player',
                                style: AppTypography.textSmMedium.copyWith(
                                  color: kWhiteColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 100.w,
                        child: Text(
                          'Elo',
                          style: AppTypography.textSmMedium.copyWith(
                            color: kWhiteColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(width: 60.w),
                    ],
                  ),
                ),
              );
            }

            // Adjust index for player items (subtract 1 for header)
            final playerIndex = index - 1;
            final player = sortedPlayers[playerIndex];
            return StandingScoreCard(
              countryCode: player.countryCode,
              title: player.title,
              name: player.name,
              score: player.score,
              scoreChange: player.scoreChange,
              matchScore: player.matchScore,
              index: playerIndex,
              rank: playerIndex + 1,
              isFirst: playerIndex == 0,
              isLast: playerIndex == sortedPlayers.length - 1,
              onTap: () {
                FocusScope.of(context).unfocus();
                ref.read(selectedBroadcastModelProvider.notifier).state = null;
                ref.read(selectedPlayerProvider.notifier).state = player;
                // Clear games context to use fallback (fetches all player games globally)
                ref.read(scoreCardGamesContextProvider.notifier).state = null;
                // No event context from favorites tab
                ref.read(scoreCardHasEventContextProvider.notifier).state = false;
                Navigator.pushNamed(context, '/scorecard_screen');
              },
              onToggleFavorite: () => _removeFavoritePlayer(player),
              onLongPress: (details) {
                _showContextMenu(
                  context,
                  details.globalPosition,
                  player,
                );
              },
              isFav: true,
              hideScore: true,
            );
          },
          // +1 for header row
          childCount: sortedPlayers.length + 1,
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_outline,
            size: 48.ic,
            color: kWhiteColor.withValues(alpha: 0.5),
          ),
          SizedBox(height: 16.h),
          Text(
            title,
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48.ic, color: kRedColor),
          SizedBox(height: 16.h),
          Text(
            'Error loading favorites',
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          ElevatedButton(
            onPressed: () {
              ref
                  .read(favoritePlayersNotifierProvider.notifier)
                  .refreshFavorites();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeFavoritePlayer(PlayerStandingModel player) async {
    final allowed = await requireFullAuthGuard(context);
    if (!allowed) return;

    await ref
        .read(favoritePlayersNotifierProvider.notifier)
        .removeFavorite(player);
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset position,
    PlayerStandingModel player,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final value = await showTabletSafeMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: kBlack2Color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.br)),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: kRedColor, size: 20.ic),
              SizedBox(width: 12.w),
              Text(
                'Remove from favorites',
                style: AppTypography.textSmRegular.copyWith(color: kRedColor),
              ),
            ],
          ),
        ),
      ],
    );

    if (!mounted || value != 'delete') return;

    final confirmed = await _showDeleteConfirmation(player);
    if (confirmed == true && mounted) {
      HapticFeedback.mediumImpact();
    }
  }

  Future<bool?> _showDeleteConfirmation(PlayerStandingModel player) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: kBlack2Color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.br),
          ),
          title: Text(
            'Remove from favorites?',
            style: AppTypography.textMdBold.copyWith(color: kWhiteColor),
          ),
          content: Text(
            'Are you sure you want to remove ${player.name} from your favorites?',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Cancel',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.7),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
                _removeFavoritePlayer(player);
              },
              child: Text(
                'Remove',
                style: AppTypography.textSmMedium.copyWith(color: kRedColor),
              ),
            ),
          ],
        );
      },
    );
  }
}
