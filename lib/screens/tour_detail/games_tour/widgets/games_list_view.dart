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
  final List<GamesAppBarModel> rounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesScreenModel gamesData;
  final GamesListViewMode gamesListViewMode;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final void Function(int)? onReturnFromChessboard;

  /// Flattened items (header + games)
  late final List<_ListItem> _flattened;

  /// Direct lookup: globalGameIndex → listIndex
  late final Map<int, int> _scrollIndexMap;

  /// Direct lookup: gameId → globalIndex
  late final Map<String, int> _globalIndexMap;

  GamesListView({
    super.key,
    required this.rounds,
    required this.gamesByRound,
    required this.gamesData,
    required this.gamesListViewMode,
    required this.itemScrollController,
    required this.itemPositionsListener,
    this.onReturnFromChessboard,
  }) {
    _globalIndexMap = {
      for (var i = 0; i < gamesData.gamesTourModels.length; i++)
        gamesData.gamesTourModels[i].gameId: i,
    };

    _flattened = [];
    _scrollIndexMap = {};

    int listIndex = 0;
    int currentGameIndex = 0;

    for (final round in rounds) {
      final roundGames = gamesByRound[round.id] ?? [];

      // header
      _flattened.add(_HeaderItem(round, roundGames));
      listIndex++;

      if (gamesListViewMode == GamesListViewMode.chessBoardGrid) {
        for (int i = 0; i < roundGames.length; i += 2) {
          final game1 = roundGames[i];
          final game2 = i + 1 < roundGames.length ? roundGames[i + 1] : null;

          _flattened.add(
            _GameRowItem(
              game1,
              _globalIndexMap[game1.gameId]!,
              game2,
              game2 != null ? _globalIndexMap[game2.gameId]! : null,
            ),
          );

          // map both game indexes to same row index
          _scrollIndexMap[currentGameIndex] = listIndex;
          _scrollIndexMap[currentGameIndex + 1] = listIndex;

          currentGameIndex += 2;
          listIndex++;
        }
      } else {
        for (final game in roundGames) {
          final globalIndex = _globalIndexMap[game.gameId]!;
          _flattened.add(_GameRowItem(game, globalIndex));
          _scrollIndexMap[currentGameIndex] = listIndex;

          currentGameIndex++;
          listIndex++;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScrollablePositionedList.builder(
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      itemCount: _flattened.length,
      itemBuilder: (context, index) {
        final item = _flattened[index];

        if (item is _HeaderItem) {
          return RoundHeader(round: item.round, roundGames: item.roundGames);
        } else if (item is _GameRowItem) {
          return gamesListViewMode == GamesListViewMode.chessBoardGrid
              ? _buildGridRow(context, ref, item)
              : _buildCardRow(context, ref, item);
        }
        return const SizedBox.shrink();
      },
      padding: EdgeInsets.only(
        left:
            gamesListViewMode == GamesListViewMode.chessBoardGrid
                ? 12.sp
                : 20.sp,
        right:
            gamesListViewMode == GamesListViewMode.chessBoardGrid
                ? 12.sp
                : 20.sp,
        top: 16.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
    );
  }

  Widget _buildGridRow(BuildContext context, WidgetRef ref, _GameRowItem item) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.sp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildGridGame(context, ref, item.game1, item.globalIndex1),
          if (item.game2 != null)
            _buildGridGame(context, ref, item.game2!, item.globalIndex2!),
        ],
      ),
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
                  _scrollToGameIndex(returnedIndex);
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

  Widget _buildCardRow(BuildContext context, WidgetRef ref, _GameRowItem item) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.sp),
      child: GameCardWrapperWidget(
        game: item.game1,
        gamesData: gamesData,
        gameIndex: item.globalIndex1,
        isChessBoardVisible: gamesListViewMode == GamesListViewMode.chessBoard,
        onReturnFromChessboard: (returnedIndex) {
          _scrollToGameIndex(returnedIndex);
          onReturnFromChessboard?.call(returnedIndex);
        },
      ),
    );
  }

  void _scrollToGameIndex(int gameIndex) {
    final listIndex = _scrollIndexMap[gameIndex];
    if (listIndex != null) {
      itemScrollController.scrollTo(
        index: listIndex,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }
}

sealed class _ListItem {}

class _HeaderItem extends _ListItem {
  final GamesAppBarModel round;
  final List<GamesTourModel> roundGames;
  _HeaderItem(this.round, this.roundGames);
}

class _GameRowItem extends _ListItem {
  final GamesTourModel game1;
  final int globalIndex1;
  final GamesTourModel? game2;
  final int? globalIndex2;
  _GameRowItem(this.game1, this.globalIndex1, [this.game2, this.globalIndex2]);
}
