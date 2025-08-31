import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesListView extends ConsumerWidget {
  final List rounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesScreenModel gamesData;
  final bool isChessBoardVisible;
  final ScrollController scrollController;
  final Map<String, GlobalKey> headerKeys;
  final Map<String, List<GlobalKey>> gameKeys;
  final GlobalKey Function(String) getHeaderKey;
  final GlobalKey Function(String, int) getGameKey;

  const GamesListView({
    super.key,
    required this.rounds,
    required this.gamesByRound,
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
    final reversedRounds = rounds.reversed.toList();
    final roundPositionMap = <String, int>{};
    for (int i = 0; i < reversedRounds.length; i++) {
      roundPositionMap[reversedRounds[i].id] = i;
    }

    // Always include all round headers and all games
    int itemCount = reversedRounds.length;
    for (final round in reversedRounds) {
      itemCount += gamesByRound[round.id]?.length ?? 0;
    }

    return ListView.builder(
      controller: scrollController,
      cacheExtent: MediaQuery.of(context).size.height * 2,
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        top: 16.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
      itemCount: itemCount,
      itemBuilder:
          (context, index) => _GameListItemBuilder(
            index: index,
            rounds: reversedRounds,
            originalRounds: rounds,
            gamesByRound: gamesByRound,
            gamesData: gamesData,
            isChessBoardVisible: isChessBoardVisible,
            getHeaderKey: getHeaderKey,
            getGameKey: getGameKey,
            roundPositionMap: roundPositionMap,
            selectedRoundId:
                ref.watch(gamesAppBarProvider).valueOrNull?.selectedId,
          ),
    );
  }
}

class _GameListItemBuilder extends ConsumerWidget {
  final int index;
  final List rounds;
  final List originalRounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesScreenModel gamesData;
  final bool isChessBoardVisible;
  final GlobalKey Function(String) getHeaderKey;
  final GlobalKey Function(String, int) getGameKey;
  final Map<String, int> roundPositionMap;
  final String? selectedRoundId;

  const _GameListItemBuilder({
    super.key,
    required this.index,
    required this.rounds,
    required this.originalRounds,
    required this.gamesByRound,
    required this.gamesData,
    required this.isChessBoardVisible,
    required this.getHeaderKey,
    required this.getGameKey,
    required this.roundPositionMap,
    required this.selectedRoundId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int currentIndex = 0;

    for (final round in rounds) {
      final roundGames = gamesByRound[round.id] ?? [];

      // Always show the round header
      if (index == currentIndex) {
        return RoundHeader(
          round: round,
          roundGames: roundGames,
          headerKey: getHeaderKey(round.id),
        );
      }
      currentIndex += 1;

      // Show games for all rounds in both view modes
      // Remove the condition that limited chess board view to selected round only
      final gamesToShow = roundGames;
      if (index < currentIndex + gamesToShow.length) {
        final gameIndexInRound = index - currentIndex;
        final game = gamesToShow[gameIndexInRound];
        final globalGameIndex = gamesData.gamesTourModels.indexOf(game);

        return Container(
          key: getGameKey(round.id, gameIndexInRound),
          child: Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: GameCardWrapperWidget(
              game: game,
              gamesData: gamesData,
              gameIndex: globalGameIndex,
              isChessBoardVisible: isChessBoardVisible,
            ),
          ),
        );
      }
      currentIndex += gamesToShow.length;
    }

    return const SizedBox.shrink();
  }
}
