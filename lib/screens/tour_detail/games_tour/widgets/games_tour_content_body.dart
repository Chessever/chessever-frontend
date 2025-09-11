import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_error_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_list_view.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesTourContentBody extends ConsumerWidget {
  final GamesScreenModel gamesScreenModel;
  final bool isChessBoardVisible;
  final ScrollController scrollController;
  final GlobalKey Function(String) getHeaderKey;
  final GlobalKey Function(String, int) getGameKey;

  const GamesTourContentBody({
    super.key,
    required this.gamesScreenModel,
    required this.isChessBoardVisible,
    required this.scrollController,
    required this.getHeaderKey,
    required this.getGameKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tourId = ref.watch(tourDetailScreenProvider).value?.aboutTourModel.id;
    final tourDetails = ref.watch(tourDetailScreenProvider);

    if (tourId == null ||
        tourDetails.isLoading ||
        !tourDetails.hasValue ||
        tourDetails.valueOrNull?.aboutTourModel == null) {
      return const TourLoadingWidget();
    }

    if (tourDetails.hasError) {
      return GamesErrorWidget(
        errorMessage: 'Error loading tournament: ${tourDetails.error}',
      );
    }

    return GamesTourMainContent(
      gamesData: gamesScreenModel,
      isChessBoardVisible: isChessBoardVisible,
      scrollController: scrollController,
      getHeaderKey: getHeaderKey,
      getGameKey: getGameKey,
    );
  }
}

class GamesTourMainContent extends ConsumerWidget {
  final GamesScreenModel gamesData;
  final bool isChessBoardVisible;
  final ScrollController scrollController;
  final GlobalKey Function(String) getHeaderKey;
  final GlobalKey Function(String, int) getGameKey;

  const GamesTourMainContent({
    super.key,
    required this.gamesData,
    required this.isChessBoardVisible,
    required this.scrollController,
    required this.getHeaderKey,
    required this.getGameKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rounds =
        ref.watch(gamesAppBarProvider).value?.gamesAppBarModels ?? [];

    final gamesByRound = <String, List<GamesTourModel>>{};

    for (final round in rounds) {
      gamesByRound[round.id] = [];
    }

    for (final game in gamesData.gamesTourModels) {
      if (gamesByRound.containsKey(game.roundId)) {
        gamesByRound[game.roundId]!.add(game);
      }
    }

    final visibleRounds =
        rounds
            .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
            .toList();

    final orderedGamesForChessBoard = <GamesTourModel>[];

    for (final round in visibleRounds.reversed) {
      final roundGames = gamesByRound[round.id] ?? [];
      orderedGamesForChessBoard.addAll(roundGames);
    }

    final orderedGamesData = GamesScreenModel(
      gamesTourModels: orderedGamesForChessBoard,
      pinnedGamedIs: gamesData.pinnedGamedIs,
      scrollToIndex: gamesData.scrollToIndex,
    );

    return GamesListView(
      key: ValueKey('games_list_${isChessBoardVisible ? 'chess' : 'card'}'),
      rounds: visibleRounds,
      gamesByRound: gamesByRound,
      gamesData: orderedGamesData,
      isChessBoardVisible: isChessBoardVisible,
      scrollController: scrollController,
      getHeaderKey: getHeaderKey,
      getGameKey: getGameKey,
    );
  }
}
