import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/utils/location_service_provider.dart';
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
              padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
              child: LayoutBuilder(
                builder: (context, constrains) {
                  final titleWidth = ((40 / 100) * constrains.maxWidth);
                  final vsWidth = ((20 / 100) * constrains.maxWidth);
                  return Row(
                    children: [
                      SizedBox(
                        width: titleWidth,
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
                                style: AppTypography.textXsMedium.copyWith(
                                  color: kWhiteColor,
                                ),
                                textAlign: TextAlign.left,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        width: vsWidth,

                        alignment: Alignment.center,
                        child: Text(
                          'VS',
                          style: AppTypography.textXsMedium.copyWith(
                            color: kWhiteColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      SizedBox(
                        width: titleWidth,
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
                                team2Name,
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
                  );
                },
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
        return _buildGamesCardView();
      case GamesListViewMode.chessBoardGrid:
        return _buildChessBoardGridView();
      case GamesListViewMode.chessBoard:
        return _buildChessBoardView();
    }
  }

  Widget _buildGamesCardView() {
    final games = widget.games;

    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: games.length,
      itemBuilder: (context, index) {
        final game = games[index];

        return Container(
          padding: EdgeInsets.symmetric(vertical: 8.sp),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: kDarkGreyColor,
                width: index == (games.length - 1) ? 0 : 0.5.h,
              ),
            ),
          ),
          child: _buildGameRow(game),
        );
      },
    );
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

  Widget _buildGameRow(MatchWithComparison game) {
    final gameIndex = widget.gamesData.gamesTourModels.indexOf(game.game);

    // Combine title + name + rating
    String formatPlayer(PlayerCard player) {
      final title = player.title.isNotEmpty == true ? '${player.title} ' : '';
      final rating = player.rating > 0 ? ' (${player.rating})' : '';
      return '$title${player.name}$rating';
    }

    final player1 =
        game.comparison == MatchComparison.sameOrder
            ? game.game.whitePlayer
            : game.game.blackPlayer;

    final player2 =
        game.comparison == MatchComparison.sameOrder
            ? game.game.blackPlayer
            : game.game.whitePlayer;

    return InkWell(
      onTap:
          () => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: widget.gamesData.gamesTourModels,
                gameIndex: gameIndex,
                onReturnFromChessboard: widget.onReturnFromChessboard,
              ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
        child: Row(
          children: [
            // Left player
            Expanded(
              flex: 4,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  formatPlayer(player1),
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // Middle progress bar
            Expanded(
              flex: 2,
              child: Center(
                child:
                    game.game.gameStatus == GameStatus.ongoing
                        ? game.comparison == MatchComparison.sameOrder
                            ? ChessProgressBar(gamesTourModel: game.game)
                            : ChessProgressBar.reversedMode(
                              gamesTourModel: game.game,
                            )
                        : StatusText(
                          status: _displayTextSupporter(game),
                          color: kWhiteColor,
                        ),
              ),
            ),

            // Right player
            Expanded(
              flex: 4,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  formatPlayer(player2),
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ],
        ),
      ),
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

String _displayTextSupporter(MatchWithComparison game) {
  if (game.comparison == MatchComparison.sameOrder) {
    switch (game.game.gameStatus) {
      case GameStatus.whiteWins:
        return '1-0';
      case GameStatus.blackWins:
        return '0-1';
      case GameStatus.draw:
        return '½-½';
      case GameStatus.ongoing:
        return '*';
      case GameStatus.unknown:
        return '';
    }
  } else {
    switch (game.game.gameStatus) {
      case GameStatus.whiteWins:
        return '0-1';
      case GameStatus.blackWins:
        return '1-0';
      case GameStatus.draw:
        return '½-½';
      case GameStatus.ongoing:
        return '*';
      case GameStatus.unknown:
        return '';
    }
  }
}
