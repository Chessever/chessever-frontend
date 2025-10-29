import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:chessever2/widgets/standing_score_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';

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
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            AnimatedBuilder(
              animation: searchController,
              builder: (cxt, _) {
                return Padding(
                  padding: EdgeInsets.only(left: 4.sp, right: 16.sp),
                  child: Row(
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
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.sp),
                          child: SearchBarWidget(
                            hintText: 'Search Favorite Player',
                            margin: 0.sp,
                            autoFocus: false,
                            controller: searchController,
                            focusNode: focusNode,
                            onChanged: (_) {
                              setState(() {});
                            },
                            onClose: _clearSearch,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
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

    final sortedPlayers = [...players]
      ..sort((a, b) => b.score.compareTo(a.score));

    return RefreshIndicator(
      onRefresh: () async {
        await ref
            .read(favoritePlayersNotifierProvider.notifier)
            .refreshFavorites();
      },
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 8.0.sp,
            ), // Matches StandingScoreCard padding
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Player column (Expanded — same as in ScoreCard)
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20.w,
                      ), // Space for flag area (16.w + 4.w spacing)
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

                // Elo column (fixed width 100.w)
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

                // Favorite icon column (fixed width 60.w)
                SizedBox(width: 60.w),
              ],
            ),
          ),

          SizedBox(height: 8.h),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.sp),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.br),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16.sp,
                  ),
                  itemCount: sortedPlayers.length,
                  itemBuilder: (context, index) {
                    final player = sortedPlayers[index];
                    return StandingScoreCard(
                      countryCode: player.countryCode,
                      title: player.title,
                      name: player.name,
                      score: player.score,
                      scoreChange: player.scoreChange,
                      matchScore: player.matchScore,
                      index: index,
                      isFirst: index == 0,
                      isLast: index == sortedPlayers.length - 1,
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        ref.read(selectedPlayerProvider.notifier).state =
                            player;
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

  void _showContextMenu(
    BuildContext context,
    Offset position,
    PlayerStandingModel player,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
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
    ).then((value) {
      if (value == 'delete') {
        _showDeleteConfirmation(context, player).then((confirmed) {
          if (confirmed == true) {
            HapticFeedback.mediumImpact();
          }
        });
      }
    });
  }

  Future<bool?> _showDeleteConfirmation(
    BuildContext context,
    PlayerStandingModel player,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
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
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.7),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
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
