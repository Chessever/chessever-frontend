import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Widget for displaying the "For You" personalized games feed
/// Optimized with:
/// - AutoDispose providers (disposed when tab changes)
/// - Cached game conversions (O(n) instead of O(n²))
/// - Efficient ListView.builder (only builds visible items)
class ForYouGamesWidget extends ConsumerWidget {
  const ForYouGamesWidget({
    super.key,
    required this.scrollController,
  });

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamesAsync = ref.watch(forYouGamesProvider);
    // Watch the converted games provider - this is cached and only computed once!
    final convertedGames = ref.watch(convertedForYouGamesProvider);

    return gamesAsync.when(
      data: (games) {
        if (games.isEmpty) {
          return _buildEmptyState(context);
        }

        // Create GamesScreenModel once, not per item!
        final gamesData = GamesScreenModel(
          gamesTourModels: convertedGames,
          pinnedGamedIs: const [], // No pinning for For You feed
        );

        return ListView.builder(
          controller: scrollController,
          padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
          itemCount: convertedGames.length + 1, // +1 for loading indicator
          // ListView.builder only builds visible items - this is already optimized!
          itemBuilder: (context, index) {
            // Show loading indicator at the end if we're loading more
            if (index == convertedGames.length) {
              final isLoadingMore =
                  ref.read(forYouGamesProvider.notifier).isFetchingMore;
              if (isLoadingMore) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.sp),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: kWhiteColor70,
                      strokeWidth: 2.sp,
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }

            // Get the pre-converted game from cache
            final gamesTourModel = convertedGames[index];

            return Padding(
              padding: EdgeInsets.only(bottom: 12.sp),
              child: GameCardWrapperWidget(
                key: ValueKey('game_${gamesTourModel.gameId}'),
                game: gamesTourModel,
                gamesData: gamesData, // Reuse the same instance!
                gameIndex: index,
                isChessBoardVisible: false,
              ),
            );
          },
        );
      },
      loading: () => _buildLoadingState(),
      error: (error, stackTrace) {
        debugPrint('[ForYouGamesWidget] Error: $error');
        debugPrint('[ForYouGamesWidget] Stack: $stackTrace');
        return const GenericErrorWidget();
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              size: 64.sp,
              color: kDarkGreyColor,
            ),
            SizedBox(height: 16.sp),
            Text(
              'No games to show',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: kWhiteColor70,
              ),
            ),
            SizedBox(height: 8.sp),
            Text(
              'Add favorite players or select your country\nto see personalized games',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: kDarkGreyColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      itemCount: 10,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: SkeletonWidget(
            child: Container(
              height: 100.sp,
              decoration: BoxDecoration(
                color: kDarkGreyColor,
                borderRadius: BorderRadius.circular(12.sp),
              ),
            ),
          ),
        );
      },
    );
  }
}
