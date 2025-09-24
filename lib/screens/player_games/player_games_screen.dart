import 'package:chessever2/screens/player_games/providers/player_games_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_typography.dart';

class PlayerGamesScreen extends ConsumerStatefulWidget {
  final String playerName;
  final String? playerTitle;
  final String? countryCode;

  const PlayerGamesScreen({
    super.key,
    required this.playerName,
    this.playerTitle,
    this.countryCode,
  });

  @override
  ConsumerState<PlayerGamesScreen> createState() => _PlayerGamesScreenState();
}

class _PlayerGamesScreenState extends ConsumerState<PlayerGamesScreen> {
  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener = ItemPositionsListener.create();

  @override
  Widget build(BuildContext context) {
    final playerGamesAsync = ref.watch(playerGamesProvider(widget.playerName));

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
              data: (gamesData) => _buildGamesList(gamesData),
              loading: () => _buildLoadingState(),
              error: (error, stack) => const GenericErrorWidget(),
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

  Widget _buildGamesList(GamesScreenModel gamesData) {
    if (gamesData.gamesTourModels.isEmpty) {
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
            Text(
              'This player has not played any games yet',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    // For now, let's just display all games in chronological order without grouping by date
    // We can add date grouping later if needed
    final games = gamesData.gamesTourModels.asMap().entries.map((entry) => {
      'game': entry.value,
      'index': entry.key,
    }).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(playerGamesProvider(widget.playerName));
      },
      color: kWhiteColor70,
      backgroundColor: kDarkGreyColor,
      child: ListView.builder(
        padding: EdgeInsets.only(
          left: 20.sp,
          right: 20.sp,
          bottom: MediaQuery.of(context).viewPadding.bottom + 20.sp,
        ),
        itemCount: games.length,
        itemBuilder: (context, index) {
          final gameData = games[index];
          final game = gameData['game'] as GamesTourModel;
          final globalIndex = gameData['index'] as int;

          return Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: GameCardWrapperWidget(
              game: game,
              gamesData: gamesData,
              gameIndex: globalIndex,
              isChessBoardVisible: false,
              onReturnFromChessboard: (returnedIndex) {
                // Handle return from chessboard if needed
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return SkeletonWidget(
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 20.sp),
        itemCount: 5,
        itemBuilder: (context, index) => Padding(
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
    );
  }

}