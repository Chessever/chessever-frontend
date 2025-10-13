import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'widgets/player_favorite_card.dart';

class FavoriteScreen extends ConsumerStatefulWidget {
  const FavoriteScreen({super.key});

  @override
  ConsumerState<FavoriteScreen> createState() => _FavoriteScreenState();
}

class _FavoriteScreenState extends ConsumerState<FavoriteScreen> {
  final TextEditingController searchController = TextEditingController();
  final focusNode = FocusNode();

  @override
  void dispose() {
    searchController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    searchController.clear();
    focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.sp),
              child: AnimatedBuilder(
                animation: searchController,
                builder: (cxt, _) {
                  return Row(
                    children: [
                      IconButton(
                        iconSize: 24.ic,
                        padding: EdgeInsets.zero,
                        onPressed: _handleBackPress,
                        icon: Icon(
                          Icons.arrow_back_ios_new_outlined,
                          size: 24.ic,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.sp),
                          child: SearchBarWidget(
                            hintText: 'Search Favorite Player',
                            autoFocus: false,
                            controller: searchController,
                            focusNode: focusNode,
                            onClose: _clearSearch,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: 16.h),
            Expanded(
              child: ref
                  .watch(favoritePlayersNotifierProvider)
                  .when(
                    data: (_) {
                      final filteredPlayers = ref.read(
                        filteredFavoritePlayersProvider(searchController.text),
                      );

                      return _buildPlayersList(filteredPlayers);
                    },
                    loading:
                        () => const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => _buildErrorState(error.toString()),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayersList(List<PlayerStandingModel> players) {
    if (players.isEmpty) {
      if (searchController.text.isNotEmpty) {
        return _buildEmptyState(
          'No players found',
          'No favorites match "${searchController.text}"',
        );
      }
      return _buildEmptyState(
        'No favorite players yet',
        'Tap the heart icon on players to add them to favorites',
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref
            .read(favoritePlayersNotifierProvider.notifier)
            .refreshFavorites();
      },
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: Row(
              children: [
                SizedBox(width: 24.w),
                Expanded(
                  child: Text(
                    'Player',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
                SizedBox(width: 16.w),
                SizedBox(
                  width: 60.w,
                  child: Text(
                    'Elo',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                      fontSize: 14.sp,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(width: 72.w),
              ],
            ),
          ),

          SizedBox(height: 8.h),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.sp),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.br),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];

                    final isEven = index % 2 == 0;

                    return PlayerFavoriteCard(
                      playerData: player,
                      rank: index + 1,
                      isEven: isEven,
                      onRemoveFavorite: () => _removeFavoritePlayer(player),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
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
            color: kWhiteColor.withOpacity(0.5),
          ),
          SizedBox(height: 16.h),
          Text(
            title,
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withOpacity(0.7),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withOpacity(0.5),
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
              color: kWhiteColor.withOpacity(0.7),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withOpacity(0.5),
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

  void _handleBackPress() {
    try {
      Navigator.of(context).pop();
    } catch (e) {
      // Error navigating back
    }
  }

  Future<void> _removeFavoritePlayer(PlayerStandingModel player) async {
    await ref
        .read(favoritePlayersNotifierProvider.notifier)
        .removeFavorite(player);
  }
}
