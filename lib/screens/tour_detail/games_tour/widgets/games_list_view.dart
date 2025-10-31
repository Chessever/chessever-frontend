import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class GamesListView extends ConsumerWidget {
  const GamesListView({
    super.key,
    required this.rounds,
    required this.gamesByRound,
    required this.gamesData,
    required this.gamesListViewMode,
    required this.itemScrollController,
    required this.itemPositionsListener,
    this.onReturnFromChessboard,
  });

  final List<GamesAppBarModel> rounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesScreenModel gamesData;
  final GamesListViewMode gamesListViewMode;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final void Function(int)? onReturnFromChessboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemCount = _computeItemCount(
      gamesListViewMode,
      rounds,
      gamesByRound,
    );

    if (itemCount == 0) {
      return const SizedBox.shrink();
    }

    return ScrollablePositionedList.builder(
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final lookup = _lookupItem(
          index: index,
          rounds: rounds,
          gamesByRound: gamesByRound,
          mode: gamesListViewMode,
        );

        if (lookup == null) {
          return const SizedBox.shrink();
        }

        if (lookup is _HeaderData) {
          return Padding(
            padding: EdgeInsets.only(bottom: 16.sp),
            child: RoundHeader(
              round: lookup.round,
              roundGames: lookup.roundGames,
            ),
          );
        }

        if (lookup is _GameRowData) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: lookup.isLastInSection ? 20.sp : 12.sp,
            ),
            child:
                gamesListViewMode == GamesListViewMode.chessBoardGrid
                    ? _buildGridRow(context, ref, lookup)
                    : _buildCardRow(context, ref, lookup),
          );
        }

        return const SizedBox.shrink();
      },
      padding: EdgeInsets.only(
        left: 16.sp,
        right: 16.sp,
        top: 16.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom + 8.sp,
      ),
    );
  }

  Widget _buildGridRow(BuildContext context, WidgetRef ref, _GameRowData item) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildGridGame(context, ref, item.game1, item.globalIndex1),
        if (item.game2 != null)
          _buildGridGame(context, ref, item.game2!, item.globalIndex2!),
      ],
    );
  }

  Widget _buildGridGame(
    BuildContext context,
    WidgetRef ref,
    GamesTourModel game,
    int globalIndex,
  ) {
    return GridChessBoardFromFENNew(
      key: ValueKey('game_${game.gameId}'),
      gamesTourModel: game,
      onChanged:
          () => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: gamesData.gamesTourModels,
                gameIndex: globalIndex,
                onReturnFromChessboard: (returnedIndex) {
                  _scrollToGameIndex(
                    returnedIndex,
                    rounds,
                    gamesByRound,
                    gamesListViewMode,
                  );
                  onReturnFromChessboard?.call(returnedIndex);
                },
              ),
      pinnedIds: gamesData.pinnedGamedIs,
      onPinToggle:
          (_) async => await ref
              .read(gamesTourScreenProvider.notifier)
              .togglePinGame(game.gameId),
    );
  }

  Widget _buildCardRow(BuildContext context, WidgetRef ref, _GameRowData item) {
    return GameCardWrapperWidget(
      game: item.game1,
      gamesData: gamesData,
      gameIndex: item.globalIndex1,
      isChessBoardVisible: gamesListViewMode == GamesListViewMode.chessBoard,
      onReturnFromChessboard: (returnedIndex) {
        _scrollToGameIndex(
          returnedIndex,
          rounds,
          gamesByRound,
          gamesListViewMode,
        );
        onReturnFromChessboard?.call(returnedIndex);
      },
    );
  }

  void _scrollToGameIndex(
    int gameIndex,
    List<GamesAppBarModel> rounds,
    Map<String, List<GamesTourModel>> gamesByRound,
    GamesListViewMode mode,
  ) {
    final listIndex = _listIndexForGameIndex(
      gameIndex: gameIndex,
      rounds: rounds,
      gamesByRound: gamesByRound,
      mode: mode,
    );
    if (listIndex != null) {
      itemScrollController.scrollTo(
        index: listIndex,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }
}

int _computeItemCount(
  GamesListViewMode mode,
  List<GamesAppBarModel> rounds,
  Map<String, List<GamesTourModel>> gamesByRound,
) {
  var count = 0;
  final isGrid = mode == GamesListViewMode.chessBoardGrid;

  for (final round in rounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) continue;

    count++; // header
    if (isGrid) {
      count += (roundGames.length / 2).ceil();
    } else {
      count += roundGames.length;
    }
  }

  return count;
}

Object? _lookupItem({
  required int index,
  required List<GamesAppBarModel> rounds,
  required Map<String, List<GamesTourModel>> gamesByRound,
  required GamesListViewMode mode,
}) {
  var currentIndex = 0;
  var globalGameIndex = 0;
  final isGrid = mode == GamesListViewMode.chessBoardGrid;

  for (final round in rounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) continue;

    final roundStartIndex = globalGameIndex;

    if (index == currentIndex) {
      return _HeaderData(round, roundGames);
    }

    currentIndex++; // move past header
    final gamesCount = roundGames.length;

    if (isGrid) {
      final rowCount = (gamesCount / 2).ceil();
      if (index < currentIndex + rowCount) {
        final row = index - currentIndex;
        final game1Index = row * 2;
        final game2Index = game1Index + 1;

        return _GameRowData(
          game1: roundGames[game1Index],
          globalIndex1: roundStartIndex + game1Index,
          game2: game2Index < gamesCount ? roundGames[game2Index] : null,
          globalIndex2:
              game2Index < gamesCount ? roundStartIndex + game2Index : null,
          isLastInSection: row == rowCount - 1,
        );
      }
      currentIndex += rowCount;
    } else {
      if (index < currentIndex + gamesCount) {
        final localIndex = index - currentIndex;
        return _GameRowData(
          game1: roundGames[localIndex],
          globalIndex1: roundStartIndex + localIndex,
          isLastInSection: localIndex == gamesCount - 1,
        );
      }
      currentIndex += gamesCount;
    }

    globalGameIndex = roundStartIndex + gamesCount;
  }

  return null;
}

int? _listIndexForGameIndex({
  required int gameIndex,
  required List<GamesAppBarModel> rounds,
  required Map<String, List<GamesTourModel>> gamesByRound,
  required GamesListViewMode mode,
}) {
  if (gameIndex < 0) return null;

  var currentIndex = 0;
  var globalGameIndex = 0;
  final isGrid = mode == GamesListViewMode.chessBoardGrid;

  for (final round in rounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) continue;

    final roundStartIndex = globalGameIndex;
    final gamesCount = roundGames.length;

    // skip header
    currentIndex++;

    if (gameIndex >= roundStartIndex &&
        gameIndex < roundStartIndex + gamesCount) {
      final localIndex = gameIndex - roundStartIndex;
      if (isGrid) {
        final row = localIndex ~/ 2;
        return currentIndex + row;
      } else {
        return currentIndex + localIndex;
      }
    }

    if (isGrid) {
      currentIndex += (gamesCount / 2).ceil();
    } else {
      currentIndex += gamesCount;
    }

    globalGameIndex = roundStartIndex + gamesCount;
  }

  return null;
}

class _HeaderData {
  _HeaderData(this.round, this.roundGames);

  final GamesAppBarModel round;
  final List<GamesTourModel> roundGames;
}

class _GameRowData {
  _GameRowData({
    required this.game1,
    required this.globalIndex1,
    this.game2,
    this.globalIndex2,
    required this.isLastInSection,
  });

  final GamesTourModel game1;
  final int globalIndex1;
  final GamesTourModel? game2;
  final int? globalIndex2;
  final bool isLastInSection;
}
