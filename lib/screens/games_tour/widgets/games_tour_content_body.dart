import 'package:chessever2/screens/games_tour/widgets/game_error_widget.dart';
import 'package:chessever2/screens/games_tour/widgets/games_list_view.dart';
import 'package:chessever2/screens/group_event/model/games_tour_model.dart';
import 'package:chessever2/screens/group_event/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/group_event/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/empty_widget.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesTourContentBody extends ConsumerWidget {
  final AsyncValue gamesAppBarAsync;
  final AsyncValue<GamesScreenModel> gamesTourAsync;
  final bool isChessBoardVisible;
  final ScrollController scrollController;
  final Map<String, GlobalKey> headerKeys;
  final Map<String, List<GlobalKey>> gameKeys;
  final GlobalKey Function(String) getHeaderKey;
  final GlobalKey Function(String, int) getGameKey;
  final GamesScreenModel? lastGamesData;
  final Function(GamesScreenModel?) onGamesDataUpdate;

  const GamesTourContentBody({
    super.key,
    required this.gamesAppBarAsync,
    required this.gamesTourAsync,
    required this.isChessBoardVisible,
    required this.scrollController,
    required this.headerKeys,
    required this.gameKeys,
    required this.getHeaderKey,
    required this.getGameKey,
    required this.lastGamesData,
    required this.onGamesDataUpdate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tourId = ref.watch(selectedTourIdProvider);
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

    if (gamesTourAsync.hasValue) {
      onGamesDataUpdate(gamesTourAsync.valueOrNull);
    }

    if ((gamesAppBarAsync.isLoading || gamesTourAsync.isLoading) &&
        lastGamesData == null) {
      return const TourLoadingWidget();
    }

    if (gamesAppBarAsync.hasError || gamesTourAsync.hasError) {
      return GamesErrorWidget(
        errorMessage:
            gamesAppBarAsync.error?.toString() ??
            gamesTourAsync.error?.toString() ??
            "An error occurred",
      );
    }

    final gamesData = lastGamesData ?? gamesTourAsync.valueOrNull;
    if (gamesData == null) return const TourLoadingWidget();

    if (gamesData.gamesTourModels.isEmpty && !gamesTourAsync.isLoading) {
      return const Center(
        child: EmptyWidget(
          title:
              "No games available yet. Check back soon or set a\nreminder for updates.",
        ),
      );
    }

    return GamesTourMainContent(
      gamesData: gamesData,
      isChessBoardVisible: isChessBoardVisible,
      scrollController: scrollController,
      headerKeys: headerKeys,
      gameKeys: gameKeys,
      getHeaderKey: getHeaderKey,
      getGameKey: getGameKey,
    );
  }
}

class GamesTourMainContent extends ConsumerWidget {
  final GamesScreenModel gamesData;
  final bool isChessBoardVisible;
  final ScrollController scrollController;
  final Map<String, GlobalKey> headerKeys;
  final Map<String, List<GlobalKey>> gameKeys;
  final GlobalKey Function(String) getHeaderKey;
  final GlobalKey Function(String, int) getGameKey;

  const GamesTourMainContent({
    super.key,
    required this.gamesData,
    required this.isChessBoardVisible,
    required this.scrollController,
    required this.headerKeys,
    required this.gameKeys,
    required this.getHeaderKey,
    required this.getGameKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rounds =
        ref.watch(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in gamesData.gamesTourModels) {
      gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
    }

    final visibleRounds =
        rounds
            .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
            .toList();

    return GamesListView(
      key: ValueKey('games_list_${isChessBoardVisible ? 'chess' : 'card'}'),
      rounds: visibleRounds,
      gamesByRound: gamesByRound,
      gamesData: gamesData,
      isChessBoardVisible: isChessBoardVisible,
      scrollController: scrollController,
      headerKeys: headerKeys,
      gameKeys: gameKeys,
      getHeaderKey: getHeaderKey,
      getGameKey: getGameKey,
    );
  }
}
