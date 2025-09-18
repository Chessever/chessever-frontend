import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_list_view.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesTourContentBody extends ConsumerWidget {
  final GamesScreenModel gamesScreenModel;
  final bool isChessBoardVisible;

  const GamesTourContentBody({
    super.key,
    required this.gamesScreenModel,
    required this.isChessBoardVisible,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamesAppBar = ref.watch(gamesAppBarProvider);

    // Show shimmer if any critical data is still loading
    if (gamesAppBar.isLoading || !gamesAppBar.hasValue) {
      return const TourLoadingWidget();
    }

    final rounds =
        ref.watch(gamesAppBarProvider).value?.gamesAppBarModels ?? [];

    // Group games by round while preserving the original sorting within each round
    final gamesByRound = <String, List<GamesTourModel>>{};

    // Initialize empty lists for each round first
    for (final round in rounds) {
      gamesByRound[round.id] = [];
    }

    // Add games to their respective rounds in the order they appear in the sorted list
    for (final game in gamesScreenModel.gamesTourModels) {
      if (gamesByRound.containsKey(game.roundId)) {
        gamesByRound[game.roundId]!.add(game);
      }
    }

    final visibleRounds =
        rounds
            .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
            .toList();

    // Create a properly ordered flat list that matches the ListView display order
    final orderedGamesForChessBoard = <GamesTourModel>[];

    for (final round in visibleRounds.reversed) {
      final roundGames = gamesByRound[round.id] ?? [];
      orderedGamesForChessBoard.addAll(roundGames);
    }

    // Create a new GamesScreenModel with the ListView-ordered games for ChessBoard navigation
    final orderedGamesData = GamesScreenModel(
      gamesTourModels: orderedGamesForChessBoard,
      pinnedGamedIs: gamesScreenModel.pinnedGamedIs,
    );

    final itemScrollController = ref.watch(gamesTourScrollProvider);
    final itemPositionsListener =
        ref.read(gamesTourScrollProvider.notifier).itemPositionsListener;

    return GamesListView(
      key: ValueKey('games_list_${isChessBoardVisible ? 'chess' : 'card'}'),
      rounds: visibleRounds,
      gamesByRound: gamesByRound,
      gamesData: orderedGamesData,
      isChessBoardVisible: isChessBoardVisible,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
    );
  }
}
