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

    return Container(
      margin: EdgeInsets.symmetric(vertical: 12.sp),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius:
            _isExpanded
                ? BorderRadius.circular(4.br)
                : BorderRadius.only(
                  topLeft: Radius.circular(4.br),
                  topRight: Radius.circular(4.br),
                ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: _toggleExpand,
            child: Container(
              height: 60.h,
              padding: EdgeInsets.only(left: 12.sp, right: 12.sp),
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
                            ref
                                .read(stringUtilsProvider)
                                .getTrimmedStringWithScore(
                                  team1Name,
                                  matchScore.first,
                                ),
                            maxLines: 1,
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
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

                  Expanded(
                    child: Row(
                      children: [
                        if (country2.isNotEmpty) ...[
                          CountryFlag.fromCountryCode(
                            country2,
                            height: 12.h,
                            width: 16.w,
                          ),
                          SizedBox(width: 4.w),
                        ],
                        Expanded(
                          child: Text(
                            ref
                                .read(stringUtilsProvider)
                                .getTrimmedStringWithScore(
                                  team1Name,
                                  matchScore.last,
                                ),
                            maxLines: 1,
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
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
          padding: EdgeInsets.only(bottom: 5.sp),
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

    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: games.length,
      itemBuilder: (context, index) {
        final matchWithComparison = games[index];
        final gameIndex = widget.gamesData.gamesTourModels.indexOf(
          matchWithComparison.game,
        );

        return GameCardWrapperWidget(
          game: matchWithComparison.game,
          gamesData: widget.gamesData,
          gameIndex: gameIndex,
          isChessBoardVisible: true,
          onReturnFromChessboard: widget.onReturnFromChessboard,
        );
      },
    );
  }

  Widget _buildGridChessBoard(MatchWithComparison matchWithComparison) {
    final gameIndex = widget.gamesData.gamesTourModels.indexOf(
      matchWithComparison.game,
    );

    return GridChessBoardFromFENNew(
      key: ValueKey('game_${matchWithComparison.game.gameId}'),
      gamesTourModel: matchWithComparison.game,
      onChanged:
          () => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: widget.gamesData.gamesTourModels,
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
