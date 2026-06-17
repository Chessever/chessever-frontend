import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/responsive_helper.dart';

class GroupEventGamesCard extends StatelessWidget {
  const GroupEventGamesCard({
    required this.games,
    required this.gamesData,
    required this.onReturnFromChessboard,
    this.liveBatchKeyByGameId = const <String, LiveGamesBatchKey>{},
    this.allowStockfishFallback = true,
    this.streamEnabled = true,
    super.key,
  });

  final List<MatchWithComparison> games;
  final GamesScreenModel gamesData;
  final void Function(int)? onReturnFromChessboard;
  final Map<String, LiveGamesBatchKey> liveBatchKeyByGameId;
  final bool allowStockfishFallback;
  final bool streamEnabled;

  @override
  Widget build(BuildContext buildCxt) {
    // Use the games list from widget data to maintain correct order for group events
    final fullGamesList = gamesData.gamesTourModels;

    // Audit optimization: Precompute indices to avoid O(N^2) indexWhere lookups
    final gameIndexMap = {
      for (int i = 0; i < fullGamesList.length; i++) fullGamesList[i].gameId: i,
    };

    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: games.length,
      separatorBuilder: (context, _) => SizedBox(height: 12.sp),
      itemBuilder: (context, index) {
        final match = games[index];
        return _GroupEventGameCardTile(
          key: ValueKey('group_event_game_${match.game.gameId}'),
          match: match,
          gamesData: gamesData,
          gameIndex: gameIndexMap[match.game.gameId] ?? -1,
          liveBatchKey: liveBatchKeyByGameId[match.game.gameId],
          allowStockfishFallback: allowStockfishFallback,
          streamEnabled: streamEnabled,
          onReturnFromChessboard: onReturnFromChessboard,
        );
      },
    );
  }
}

class _GroupEventGameCardTile extends ConsumerWidget {
  const _GroupEventGameCardTile({
    required this.match,
    required this.gamesData,
    required this.gameIndex,
    required this.onReturnFromChessboard,
    required this.allowStockfishFallback,
    required this.streamEnabled,
    this.liveBatchKey,
    super.key,
  });

  final MatchWithComparison match;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final void Function(int)? onReturnFromChessboard;
  final bool allowStockfishFallback;
  final bool streamEnabled;
  final LiveGamesBatchKey? liveBatchKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveGame = watchLiveGame(
      ref,
      match.game,
      batchKey: liveBatchKey,
      streamEnabled: streamEnabled,
    );
    final liveMatch = MatchWithComparison(
      game: liveGame,
      comparison: match.comparison,
    );

    List<GamesTourModel> buildUpdatedGamesList() {
      final updatedGames = List<GamesTourModel>.from(gamesData.gamesTourModels);
      if (gameIndex >= 0 && gameIndex < updatedGames.length) {
        updatedGames[gameIndex] = liveGame;
      }
      return updatedGames;
    }

    return GameCard(
      // Use actual comparison to maintain team positions.
      matchComparison: liveMatch,
      onPinToggle: (game) async {
        await ref
            .read(gamesTourScreenProvider.notifier)
            .togglePinGame(game.gameId, sourceTourId: game.tourId);
      },
      pinnedIds: gamesData.pinnedGamedIs,
      allowStockfishFallback: allowStockfishFallback,
      onTap: () {
        ref
            .read(gameCardWrapperProvider)
            .navigateToChessBoard(
              context: context,
              orderedGames: buildUpdatedGamesList(),
              gameIndex: gameIndex,
              onReturnFromChessboard: onReturnFromChessboard,
            );
      },
    );
  }
}
