import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
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

    // Check if this is a multi-stage knockout and ensure ALL stages have loaded before proceeding
    if (isKnockoutTournament && rounds.any((r) => r.id.startsWith('$kKnockoutStagePrefix-'))) {
      // Extract all stage tour IDs
      final stageTourIds = rounds
          .where((r) => r.id.startsWith('$kKnockoutStagePrefix-'))
          .map((r) => r.id.replaceFirst('$kKnockoutStagePrefix-', ''))
          .toList();

      // Check if ANY stage provider is still loading
      for (final stageTourId in stageTourIds) {
        // Check if the provider's underlying games data is still loading
        final stageGamesAsync = ref.watch(gamesTourProvider(stageTourId));
        if (stageGamesAsync.isLoading || !stageGamesAsync.hasValue) {
          debugPrint('⏳ Waiting for stage $stageTourId to finish loading...');
          return const TourLoadingWidget();
        }
      }
      debugPrint('✅ All ${stageTourIds.length} stages loaded, proceeding with render');
      // For knockout tournaments with stage-based rounds (multi-stage knockouts),
      // fetch and assign games for EACH stage from ALL tours in the group broadcast
      print('🎮 Multi-stage knockout detected, loading games for ${rounds.length} stages');
      for (final round in rounds) {
        if (round.id.startsWith('$kKnockoutStagePrefix-')) {
          // Extract the tour ID from the stage ID: "knockout-stage-{tourId}"
          final stageTourId = round.id.replaceFirst('$kKnockoutStagePrefix-', '');

          // Get the knockout state for this specific tour to access its games
          // Changed from ref.read to ref.watch to properly handle async loading
          final stageKnockoutState = ref.watch(knockoutTournamentStateProvider(stageTourId));

          // Assign all games from this stage's tour
          gamesByRound[round.id] = List<GamesTourModel>.from(stageKnockoutState.allGames);
          print('  📦 Stage "${round.name}" (tourId: $stageTourId): ${stageKnockoutState.allGames.length} games');
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
    // FOR MULTI-STAGE KNOCKOUTS: Show ALL stages with games (no status filtering)
    // FOR REGULAR EVENTS:
    // 1. If there are live/ongoing rounds → hide upcoming rounds (unless explicitly selected)
    // 2. If only completed rounds exist → show next upcoming round
    // 3. If all rounds are upcoming → show all upcoming rounds

    final isMultiStageKnockout = isKnockoutTournament && rounds.any((r) => r.id.startsWith('$kKnockoutStagePrefix-'));

    final visibleRounds = rounds.where((round) {
      final roundGames = gamesByRound[round.id] ?? [];
      if (roundGames.isEmpty) {
        print('❌ Filtering out "${round.name}" - no games');
        return false;
      }

      // For multi-stage knockouts, show ALL stages with games (no status filtering)
      if (isMultiStageKnockout) {
        print('✅ Including "${round.name}" - multi-stage knockout (${roundGames.length} games)');
        return true;
      }

      // Regular tournament filtering logic below
      final hasLiveOrOngoing = rounds.any((r) =>
        r.roundStatus == RoundStatus.live || r.roundStatus == RoundStatus.ongoing
      );

      final hasCompleted = rounds.any((r) => r.roundStatus == RoundStatus.completed);

      final allAreUpcoming = rounds.every((r) =>
        r.roundStatus == RoundStatus.upcoming || gamesByRound[r.id]?.isEmpty == true
      );

      // Always include explicitly user-selected round
      if (userSelected && round.id == selectedRoundId) {
        print('✅ Including "${round.name}" - user selected');
        return true;
      }

      // If all rounds are upcoming, show them all
      if (allAreUpcoming) {
        print('✅ Including "${round.name}" - all are upcoming');
        return true;
      }

      // If there are live/ongoing rounds, hide upcoming
      if (hasLiveOrOngoing) {
        final include = round.roundStatus != RoundStatus.upcoming;
        print('${include ? "✅" : "❌"} "${round.name}" - hasLiveOrOngoing, status: ${round.roundStatus}');
        return include;
      }

      // If only completed rounds exist, show completed + first upcoming
      if (hasCompleted && round.roundStatus == RoundStatus.upcoming) {
        // Find the first upcoming round and only show that one
        final upcomingRounds = rounds.where((r) =>
          r.roundStatus == RoundStatus.upcoming &&
          (gamesByRound[r.id]?.isNotEmpty ?? false)
        ).toList();
        final include = upcomingRounds.isNotEmpty && upcomingRounds.first.id == round.id;
        print('${include ? "✅" : "❌"} "${round.name}" - first upcoming round check');
        return include;
      }

      // Show completed/ongoing/live rounds
      final include = round.roundStatus != RoundStatus.upcoming;
      print('${include ? "✅" : "❌"} "${round.name}" - default filter, status: ${round.roundStatus}');
      return include;
    }).toList();

    print('🎯 Final visible rounds: ${visibleRounds.length}');
    for (final r in visibleRounds) {
      print('   - ${r.name}: ${gamesByRound[r.id]?.length ?? 0} games');
    }

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
