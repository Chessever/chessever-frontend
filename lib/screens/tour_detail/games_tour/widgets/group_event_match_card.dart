import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_games_tour_content_body.dart';
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
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
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
    final team2Name = widget.roundTitle.split(' vs ').last;
    return Container(
      margin: EdgeInsets.only(bottom: 12.sp),
      decoration: BoxDecoration(
        color: kBlackColor.withValues(alpha: 0.7),
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
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      team1Name,
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                  ),

                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.sp),
                    child: Text(
                      'VS',
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  Expanded(
                    child: Text(
                      team2Name,
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),

                  SizedBox(width: 12.sp),

                  RotationTransition(
                    turns: _rotationAnimation,
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: kWhiteColor,
                      size: 20.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),

          AnimatedCrossFade(
            firstChild: Column(
              children: [
                Container(height: 10.h, color: kBlackColor),
                SizedBox(height: 12.sp),
                _buildGamesList(),
              ],
            ),
            secondChild: const SizedBox.shrink(),
            crossFadeState:
                _isExpanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 300),
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: games.length,
      itemBuilder: (context, index) {
        final game = games[index];

        return Column(
          children: [
            if (index > 0) SizedBox(height: 8.sp),
            _buildGameRow(game),
            Divider(height: 0.5.h, color: kDarkGreyColor),
          ],
        );
      },
    );
  }

  Widget _buildChessBoardGridView() {
    final games = widget.games;

    return ListView.builder(
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
                SizedBox(width: 8.sp),
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
                    game.comparison == MatchComparison.sameOrder
                        ? ChessProgressBar(gamesTourModel: game.game)
                        : ChessProgressBar.reversedMode(
                          gamesTourModel: game.game,
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
