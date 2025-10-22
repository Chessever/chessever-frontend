import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_games_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_match_card_provider.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/string_utils_provider.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';

class GroupEventMatchCard extends ConsumerStatefulWidget {
  final String roundTitle;
  final List<MatchWithComparison> games;
  final GamesScreenModel gamesData;
  final GamesListViewMode gamesListViewMode;
  final void Function(int)? onReturnFromChessboard;

  const GroupEventMatchCard({
    super.key,
    required this.roundTitle,
    required this.games,
    required this.gamesData,
    required this.gamesListViewMode,
    this.onReturnFromChessboard,
  });

  @override
  ConsumerState<GroupEventMatchCard> createState() =>
      _GroupEventMatchCardState();
}

class _GroupEventMatchCardState extends ConsumerState<GroupEventMatchCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = true;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final team1Name = widget.roundTitle.split(' vs ').first;
    final country1 = ref
        .read(locationServiceProvider)
        .getValidCountryCodeFromName(team1Name);
    final team2Name = widget.roundTitle.split(' vs ').last;
    final country2 = ref
        .read(locationServiceProvider)
        .getValidCountryCodeFromName(team2Name);

    final matchScore = ref
        .read(groupEventMatchCardProvider)
        .getMatchScore(matchList: widget.games, team: team1Name);
    final team1ScoreStr = matchScore.first % 1 == 0
        ? matchScore.first.toStringAsFixed(0)
        : matchScore.first.toStringAsFixed(1);
    final team2ScoreStr = matchScore.last % 1 == 0
        ? matchScore.last.toStringAsFixed(0)
        : matchScore.last.toStringAsFixed(1);

    final radius = Radius.circular(12.br);
    final cardBorderRadius = BorderRadius.circular(12.br);
    final headerBorderRadius =
        _isExpanded
            ? BorderRadius.only(topLeft: radius, topRight: radius)
            : cardBorderRadius;

    return Container(
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: cardBorderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: _toggleExpand,
            child: Container(
              height: 60.h,
              padding: EdgeInsets.only(left: 12.sp, right: 12.sp),
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: headerBorderRadius,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (country1.isNotEmpty) ...[
                          CountryFlag.fromCountryCode(
                            country1,
                            height: 12.h,
                            width: 16.w,
                          ),
                          SizedBox(width: 4.w),
                        ],
                        Expanded(
                          child: Text(
                            team1Name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(
                    width: 36.w,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        team1ScoreStr,
                        style: AppTypography.textXsMedium.copyWith(
                          color: kWhiteColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(
                    width: 32.w,
                    child: Center(
                      child: Text(
                        'VS',
                        textAlign: TextAlign.center,
                        style: AppTypography.textXsMedium.copyWith(
                          color: kWhiteColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(
                    width: 36.w,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        team2ScoreStr,
                        style: AppTypography.textXsMedium.copyWith(
                          color: kWhiteColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            team2Name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        if (country2.isNotEmpty) ...[
                          SizedBox(width: 4.w),
                          CountryFlag.fromCountryCode(
                            country2,
                            height: 12.h,
                            width: 16.w,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child:
                _isExpanded
                    ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(height: 10.h, color: kBlackColor),
                        _buildGamesList(),
                      ],
                    )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildGamesList() {
    switch (widget.gamesListViewMode) {
      case GamesListViewMode.gamesCard:
        return GroupEventGamesCard(
          games: widget.games,
          gamesData: widget.gamesData,
          onReturnFromChessboard: widget.onReturnFromChessboard,
        );
      case GamesListViewMode.chessBoardGrid:
        return _buildChessBoardGridView();
      case GamesListViewMode.chessBoard:
        return _buildChessBoardView();
    }
  }

  Widget _buildChessBoardGridView() {
    final games = widget.games;

    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: (games.length / 2).ceil(), // Each row contains up to 2 games
      itemBuilder: (context, index) {
        final matchWithComparison = games[index * 2];
        final game2 =
            (index * 2 + 1) < games.length ? games[index * 2 + 1] : null;

        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: _buildGridChessBoard(matchWithComparison)),
              if (game2 != null) ...[
                Expanded(child: _buildGridChessBoard(game2)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildChessBoardView() {
    final games = widget.games;
    // Use the games list from widget data to maintain correct order for group events
    final fullGamesList = widget.gamesData.gamesTourModels;

    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: games.length,
      itemBuilder: (context, index) {
        final matchWithComparison = games[index];
        final gameIndex = fullGamesList.indexWhere(
          (g) => g.gameId == matchWithComparison.game.gameId,
        );

        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: GameCardWrapperWidget(
            game: matchWithComparison.game,
            gamesData: GamesScreenModel(
              gamesTourModels: fullGamesList,
              pinnedGamedIs: widget.gamesData.pinnedGamedIs,
            ),
            gameIndex: gameIndex,
            isChessBoardVisible: true,
            onReturnFromChessboard: widget.onReturnFromChessboard,
          ),
        );
      },
    );
  }

  Widget _buildGridChessBoard(MatchWithComparison matchWithComparison) {
    // Use the games list from widget data to maintain correct order for group events
    final fullGamesList = widget.gamesData.gamesTourModels;

    final gameIndex = fullGamesList.indexWhere(
      (g) => g.gameId == matchWithComparison.game.gameId,
    );

    return GridChessBoardFromFENNew(
      key: ValueKey('game_${matchWithComparison.game.gameId}'),
      gamesTourModel: matchWithComparison.game,
      onChanged:
          () => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: fullGamesList,
                gameIndex: gameIndex,
                onReturnFromChessboard: widget.onReturnFromChessboard,
              ),
      pinnedIds: widget.gamesData.pinnedGamedIs,
      onPinToggle:
          (_) async => await ref
              .read(gamesTourScreenProvider.notifier)
              .togglePinGame(matchWithComparison.game.gameId),
    );
  }
}
