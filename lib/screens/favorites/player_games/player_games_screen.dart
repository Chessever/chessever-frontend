import 'package:chessever2/screens/favorites/player_games/provider/player_games_provider.dart';
import 'package:chessever2/screens/favorites/player_games/view_model/player_games_state.dart';
import 'package:chessever2/screens/favorites/player_games/widgets/tournament_group_header.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_typography.dart';

class PlayerGamesScreen extends ConsumerStatefulWidget {
  final String fideId;
  final String playerName;
  final String? playerTitle;
  final String? countryCode;

  const PlayerGamesScreen({
    super.key,
    required this.fideId,
    required this.playerName,
    this.playerTitle,
    this.countryCode,
  });

  @override
  ConsumerState<PlayerGamesScreen> createState() => _PlayerGamesScreenState();
}

class _PlayerGamesScreenState extends ConsumerState<PlayerGamesScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Check if user scrolled to 80% of the list
    final scrollPosition = _scrollController.position;
    if (scrollPosition.pixels >= scrollPosition.maxScrollExtent * 0.8) {
      // Load more games
      ref.read(playerGamesProvider(widget.fideId).notifier).loadMoreGames();
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerGamesAsync = ref.watch(playerGamesProvider(widget.fideId));

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Column(
        children: [
          // Header
          SizedBox(height: MediaQuery.of(context).viewPadding.top + 16.h),
          _buildHeader(),
          SizedBox(height: 16.h),

          // Games content
          Expanded(
            child: playerGamesAsync.when(
              data: (playerGamesState) => _buildContent(playerGamesState),
              loading: () => _buildLoadingState(),
              error: (error, stack) {
                debugPrint('===== PlayerGamesScreen AsyncValue error =====');
                debugPrint('Error type: ${error.runtimeType}');
                debugPrint('Error: $error');
                debugPrint('Stack: $stack');
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const GenericErrorWidget(),
                      SizedBox(height: 16.h),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32.sp),
                        child: Text(
                          'Error: $error',
                          style: AppTypography.textSmRegular.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.sp),
      child: Row(
        children: [
          IconButton(
            iconSize: 24.ic,
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24.ic),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (widget.playerTitle?.isNotEmpty == true) ...[
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                        margin: EdgeInsets.only(right: 8.w),
                        decoration: BoxDecoration(
                          color: kGreenColor,
                          borderRadius: BorderRadius.circular(12.sp),
                        ),
                        child: Text(
                          widget.playerTitle!,
                          style: AppTypography.textXsMedium.copyWith(
                            color: Colors.white,
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        widget.playerName,
                        style: AppTypography.textLgBold.copyWith(
                          color: kWhiteColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  'All Games',
                  style: AppTypography.textSmRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(PlayerGamesState playerGamesState) {
    final tournamentGroups = playerGamesState.tournamentGroups;
    final isLoading = playerGamesState.isLoading;
    final error = playerGamesState.error;

    // Error state
    if (error != null && tournamentGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const GenericErrorWidget(),
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.sp),
              child: Text(
                error,
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    // Empty state (no loading, no groups)
    if (!isLoading && tournamentGroups.isEmpty) {
      return _buildEmptyState();
    }

    // Has data
    return RefreshIndicator(
      onRefresh: () async {
        await ref
            .read(playerGamesProvider(widget.fideId).notifier)
            .refreshGames();
      },
      color: kWhiteColor70,
      backgroundColor: kDarkGreyColor,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(
          left: 20.sp,
          right: 20.sp,
          bottom: MediaQuery.of(context).viewPadding.bottom + 20.sp,
        ),
        itemCount: _calculateItemCount(tournamentGroups, isLoading),
        itemBuilder: (context, index) {
          return _buildListItem(index, tournamentGroups, isLoading);
        },
      ),
    );
  }

  int _calculateItemCount(List<TournamentGamesGroup> tournamentGroups, bool isLoading) {
    int count = 0;
    for (final group in tournamentGroups) {
      count++; // Header
      count += group.games.length; // Games
    }
    if (isLoading) count++; // Loading indicator
    return count;
  }

  Widget _buildListItem(int index, List<TournamentGamesGroup> tournamentGroups, bool isLoadingMore) {
    int currentIndex = 0;

    // Iterate through tournament groups
    for (final group in tournamentGroups) {
      // Tournament header
      if (currentIndex == index) {
        return TournamentGroupHeader(tournamentGroup: group);
      }
      currentIndex++;

      // Games in this tournament
      for (int gameIdx = 0; gameIdx < group.games.length; gameIdx++) {
        if (currentIndex == index) {
          final game = group.games[gameIdx];

          // Create a GamesScreenModel with just this tournament's games
          final gamesData = GamesScreenModel(
            gamesTourModels: group.games,
            pinnedGamedIs: [],
            isSearchMode: false,
          );

          return Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: GameCardWrapperWidget(
              game: game,
              gamesData: gamesData,
              gameIndex: gameIdx,
              isChessBoardVisible: false,
              onReturnFromChessboard: (returnedIndex) {},
            ),
          );
        }
        currentIndex++;
      }
    }

    // Loading indicator at the end
    if (isLoadingMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 20.sp),
        child: Center(
          child: CircularProgressIndicator(
            color: kPrimaryColor,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sports_esports_outlined,
            size: 48.ic,
            color: kWhiteColor.withValues(alpha: 0.5),
          ),
          SizedBox(height: 16.h),
          Text(
            'No games found',
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.sp),
            child: Text(
              'This player has not played any games yet',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return SkeletonWidget(
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 20.sp),
        itemCount: 3,
        itemBuilder: (context, index) => Column(
          children: [
            Container(
              height: 70.h,
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: BorderRadius.circular(8.br),
              ),
            ),
            SizedBox(height: 12.h),
            ...List.generate(
              2,
              (i) => Padding(
                padding: EdgeInsets.only(bottom: 12.sp),
                child: Container(
                  height: 84.h,
                  decoration: BoxDecoration(
                    color: kBlack2Color,
                    borderRadius: BorderRadius.circular(12.br),
                  ),
                ),
              ),
            ),
            SizedBox(height: 20.h),
          ],
        ),
      ),
    );
  }
}
