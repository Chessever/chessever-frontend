import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_list_view.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesTourContentBody extends ConsumerWidget {
  final GamesScreenModel gamesScreenModel;
  final GamesListViewMode gamesListViewMode;

  const GamesTourContentBody({
    super.key,
    required this.gamesScreenModel,
    required this.gamesListViewMode,
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
    final selectedRoundId = gamesAppBar.value?.selectedId;
    final userSelected = gamesAppBar.value?.userSelectedId ?? false;

    final tourId =
        ref.read(tourDetailScreenProvider).value?.aboutTourModel.id;
    final knockoutState =
        ref.watch(knockoutTournamentStateProvider(tourId));
    final isKnockoutTournament = knockoutState.isKnockout;

    final allGames = gamesScreenModel.gamesTourModels;

    // Group games by round while preserving the original sorting within each round
    final gamesByRound = <String, List<GamesTourModel>>{};

    // Initialize empty lists for each round first
    for (final round in rounds) {
      gamesByRound[round.id] = [];
    }

    if (isKnockoutTournament && rounds.any((r) => r.id.startsWith('$kKnockoutStagePrefix-'))) {
      // For knockout tournaments with stage-based rounds, all games belong to the single stage
      // Since rounds are already pre-filtered by games_app_bar_provider, assign all games to each stage round
      for (final round in rounds) {
        if (round.id.startsWith('$kKnockoutStagePrefix-')) {
          gamesByRound[round.id] = List<GamesTourModel>.from(allGames);
        }
      }
    } else {
      // For regular tournaments, add games to their respective rounds
      for (final game in allGames) {
        if (gamesByRound.containsKey(game.roundId)) {
          gamesByRound[game.roundId]!.add(game);
        }
      }
    }

    // Smart filtering: Show upcoming rounds intelligently
    // 1. If there are live/ongoing rounds → hide upcoming rounds (unless explicitly selected)
    // 2. If only completed rounds exist → show next upcoming round
    // 3. If all rounds are upcoming → show all upcoming rounds

    final hasLiveOrOngoing = rounds.any((r) =>
      r.roundStatus == RoundStatus.live || r.roundStatus == RoundStatus.ongoing
    );

    final hasCompleted = rounds.any((r) => r.roundStatus == RoundStatus.completed);

    final allAreUpcoming = rounds.every((r) =>
      r.roundStatus == RoundStatus.upcoming || gamesByRound[r.id]?.isEmpty == true
    );

    final visibleRounds = rounds.where((round) {
      final roundGames = gamesByRound[round.id] ?? [];
      if (roundGames.isEmpty) return false;

      // Always include explicitly user-selected round
      if (userSelected && round.id == selectedRoundId) return true;

      // If all rounds are upcoming, show them all
      if (allAreUpcoming) return true;

      // If there are live/ongoing rounds, hide upcoming
      if (hasLiveOrOngoing) {
        return round.roundStatus != RoundStatus.upcoming;
      }

      // If only completed rounds exist, show completed + first upcoming
      if (hasCompleted && round.roundStatus == RoundStatus.upcoming) {
        // Find the first upcoming round and only show that one
        final upcomingRounds = rounds.where((r) =>
          r.roundStatus == RoundStatus.upcoming &&
          (gamesByRound[r.id]?.isNotEmpty ?? false)
        ).toList();
        return upcomingRounds.isNotEmpty && upcomingRounds.first.id == round.id;
      }

      // Show completed/ongoing/live rounds
      return round.roundStatus != RoundStatus.upcoming;
    }).toList();

    // Create a properly ordered flat list that matches the ListView display order
    final orderedGamesForChessBoard = <GamesTourModel>[];

    for (final round in visibleRounds) {
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
      key: ValueKey('games_list_${gamesListViewMode.name}'),
      rounds: visibleRounds,
      gamesByRound: gamesByRound,
      gamesData: orderedGamesData,
      isKnockoutTournament: isKnockoutTournament,
      gamesListViewMode: gamesListViewMode,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      onReturnFromChessboard: (returnedIndex) {
        // The scrolling is already handled in GamesListView
        // This callback can be used for additional logic if needed
      },
    );
  }
}
