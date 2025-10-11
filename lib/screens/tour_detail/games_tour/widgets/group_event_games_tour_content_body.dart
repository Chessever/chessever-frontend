import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_match_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/app_typography.dart';

class GroupEventGamesTourContentBody extends ConsumerStatefulWidget {
  final GamesScreenModel gamesScreenModel;
  final GamesListViewMode gamesListViewMode;
  final void Function(int)? onReturnFromChessboard;

  const GroupEventGamesTourContentBody({
    super.key,
    required this.gamesScreenModel,
    required this.gamesListViewMode,
    this.onReturnFromChessboard,
  });

  @override
  ConsumerState<GroupEventGamesTourContentBody> createState() =>
      _GroupEventGamesTourContentBodyState();
}

class _GroupEventGamesTourContentBodyState
    extends ConsumerState<GroupEventGamesTourContentBody> {
  int _selectedRoundIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gamesAppBar = ref.watch(gamesAppBarProvider);

    if (gamesAppBar.isLoading || !gamesAppBar.hasValue) {
      return const TourLoadingWidget();
    }

    final rounds =
        ref.watch(gamesAppBarProvider).value?.gamesAppBarModels ?? [];

    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final round in rounds) {
      gamesByRound[round.id] = [];
    }

    for (final game in widget.gamesScreenModel.gamesTourModels) {
      if (gamesByRound.containsKey(game.roundId)) {
        gamesByRound[game.roundId]!.add(game);
      }
    }

    final visibleRounds =
        rounds
            .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
            .toList();

    if (_selectedRoundIndex >= visibleRounds.length) {
      _selectedRoundIndex = 0;
    }

    final selectedRound =
        visibleRounds.isNotEmpty ? visibleRounds[_selectedRoundIndex] : null;

    final orderedGamesForChessBoard = <GamesTourModel>[];
    final gameIndexMap = <String, int>{};

    int currentIndex = 0;
    for (final round in visibleRounds) {
      final roundGames = gamesByRound[round.id] ?? [];
      for (final game in roundGames) {
        gameIndexMap[game.gameId] = currentIndex;
        orderedGamesForChessBoard.add(game);
        currentIndex++;
      }
    }

    final orderedGamesData = GamesScreenModel(
      gamesTourModels: orderedGamesForChessBoard,
      pinnedGamedIs: widget.gamesScreenModel.pinnedGamedIs,
    );

    return Column(
      children: [
        Expanded(
          child:
              selectedRound != null
                  ? ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.sp,
                      vertical: 12.sp,
                    ),
                    children: [
                      GroupEventMatchCard(
                        key: ValueKey('round_${selectedRound.id}'),
                        round: selectedRound,
                        games: gamesByRound[selectedRound.id] ?? [],
                        gamesData: orderedGamesData,
                        gameIndexMap: gameIndexMap,
                        gamesListViewMode: widget.gamesListViewMode,
                        onReturnFromChessboard: widget.onReturnFromChessboard,
                      ),
                    ],
                  )
                  : const SizedBox.shrink(),
        ),
        if (visibleRounds.isNotEmpty)
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.5,
              height: 48,
              margin: EdgeInsets.only(right: 16.sp, bottom: 16.sp),
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: List.generate(visibleRounds.length, (i) {
                    final index = visibleRounds.length - 1 - i;
                    final round = visibleRounds[index];
                    final isSelected = index == _selectedRoundIndex;

                    String roundNumber = '${index + 1}';
                    final numberMatch = RegExp(r'\d+').firstMatch(round.name);
                    if (numberMatch != null) {
                      roundNumber = numberMatch.group(0)!;
                    }

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedRoundIndex = index;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: EdgeInsets.only(right: 12.sp),
                        padding: EdgeInsets.symmetric(
                          horizontal: 20.sp,
                          vertical: 12.sp,
                        ),
                        decoration: BoxDecoration(
                          color: kDarkGreyColor,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              isSelected
                                  ? Border.all(
                                    color: const Color(0xFF404040),
                                    width: 1,
                                  )
                                  : null,
                        ),
                        child: Text(
                          roundNumber,
                          style: AppTypography.textSmMedium.copyWith(
                            color:
                                isSelected
                                    ? Colors.white
                                    : const Color(0xFF666666),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
