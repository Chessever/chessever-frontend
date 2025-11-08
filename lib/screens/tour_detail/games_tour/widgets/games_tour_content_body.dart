import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_list_view.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
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

    final rounds = gamesAppBar.value?.gamesAppBarModels ?? [];
    final selectedRoundId = gamesAppBar.value?.selectedId;
    final userSelected = gamesAppBar.value?.userSelectedId ?? false;

    final tourId =
        ref.read(tourDetailScreenProvider).value?.aboutTourModel.id;
    final knockoutState =
        ref.watch(knockoutTournamentStateProvider(tourId));
    final isKnockoutTournament = knockoutState.isKnockout;

    final allGames = gamesScreenModel.gamesTourModels;
    final isSearchMode = gamesScreenModel.isSearchMode;

    // Group games by round while preserving the original sorting within each round
    final gamesByRound = <String, List<GamesTourModel>>{};
    final roundLookup = <String, GamesAppBarModel>{
      for (final round in rounds) round.id: round,
    };

    final Set<String>? searchGameIds =
        isSearchMode ? allGames.map((g) => g.gameId).toSet() : null;

    void ensureRoundEntry(String roundId) {
      gamesByRound.putIfAbsent(roundId, () => <GamesTourModel>[]);
    }

    // Initialize empty lists for each known round
    for (final round in rounds) {
      ensureRoundEntry(round.id);
    }

    // Check if this is a multi-stage knockout and ensure ALL stages have loaded before proceeding
    // IMPORTANT: Skip multi-stage loading when in search mode - use filtered games instead
    final isMultiStageKnockout = isKnockoutTournament &&
        rounds.any((r) => r.id.startsWith('$kKnockoutStagePrefix-'));

    if (isMultiStageKnockout) {
      // Extract all stage tour IDs
      final stageTourIds = rounds
          .where((r) => r.id.startsWith('$kKnockoutStagePrefix-'))
          .map((r) => r.id.replaceFirst('$kKnockoutStagePrefix-', ''))
          .toList();

      // Check if ANY stage provider is still loading (watch to detect loading completion)
      var isAnyStageLoading = false;
      for (final stageTourId in stageTourIds) {
        final stageGamesAsync = ref.watch(gamesTourProvider(stageTourId));
        if (stageGamesAsync.isLoading || !stageGamesAsync.hasValue) {
          isAnyStageLoading = true;
          break; // Early exit - no need to check other stages
        }
      }

      if (isAnyStageLoading) {
        return const TourLoadingWidget();
      }

      // For knockout tournaments with stage-based rounds (multi-stage knockouts),
      // fetch and assign games for EACH stage from ALL tours in the group broadcast
      for (final round in rounds) {
        if (round.id.startsWith('$kKnockoutStagePrefix-')) {
          // Extract the tour ID from the stage ID: "knockout-stage-{tourId}"
          final stageTourId = round.id.replaceFirst('$kKnockoutStagePrefix-', '');

          // Watch the state to rebuild when games update
          final stageKnockoutState =
              ref.watch(knockoutTournamentStateProvider(stageTourId));
          final stageGames = stageKnockoutState.allGames
              .where(
                (game) => searchGameIds == null || searchGameIds.contains(game.gameId),
              )
              .toList();
          gamesByRound[round.id] = stageGames;
        }
      }

      // CRITICAL: Sort games in each round by pin status (pinned games first)
      final pinnedGameIds = gamesScreenModel.pinnedGamedIs;
      if (pinnedGameIds.isNotEmpty) {
        for (final roundId in gamesByRound.keys) {
          final roundGames = gamesByRound[roundId]!;
          roundGames.sort((a, b) {
            final aPinned = pinnedGameIds.contains(a.gameId);
            final bPinned = pinnedGameIds.contains(b.gameId);
            if (aPinned != bPinned) {
              return aPinned ? -1 : 1; // Pinned games first
            }
            return 0; // Keep original order for same pin status
          });
        }
      }
    } else {
      // For regular tournaments OR search mode, use the (filtered) games from gamesScreenModel
      for (final game in allGames) {
        ensureRoundEntry(game.roundId);
        gamesByRound[game.roundId]!.add(game);

        if (isSearchMode && !roundLookup.containsKey(game.roundId)) {
          final slug = game.roundSlug;
          final friendlyName =
              (slug != null && slug.isNotEmpty)
                  ? KnockoutMatchDetector.formatRoundSlug(slug)
                  : (game.tourSlug ?? game.roundId);
          roundLookup[game.roundId] = GamesAppBarModel(
            id: game.roundId,
            name: friendlyName,
            startsAt: game.lastMoveTime,
            roundStatus: RoundStatus.live,
          );
        }
      }

      if (isSearchMode) {
        debugPrint('🔍 Search mode active: Using ${allGames.length} filtered games');
      }
    }

    // Determine effective round list (original or search-specific)
    final List<GamesAppBarModel> effectiveRounds;
    if (isSearchMode) {
      effectiveRounds = roundLookup.values
          .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
          .toList();

      // Preserve original ordering when possible
      final originalOrder = {
        for (var i = 0; i < rounds.length; i++) rounds[i].id: i,
      };
      effectiveRounds.sort((a, b) {
        final ia = originalOrder[a.id];
        final ib = originalOrder[b.id];
        if (ia != null && ib != null) return ia.compareTo(ib);
        if (ia != null) return -1;
        if (ib != null) return 1;
        final aTime = gamesByRound[a.id]?.first.lastMoveTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = gamesByRound[b.id]?.first.lastMoveTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
    } else {
      effectiveRounds = rounds;
    }

    // Smart filtering: Show upcoming rounds intelligently
    // FOR SEARCH MODE: Show ALL rounds with matching games (ignore status)
    // FOR MULTI-STAGE KNOCKOUTS: Show ALL stages with games (no status filtering)
    // FOR REGULAR EVENTS:
    // 1. If there are live/ongoing rounds → hide upcoming rounds (unless explicitly selected)
    // 2. If only completed rounds exist → show next upcoming round
    // 3. If all rounds are upcoming → show all upcoming rounds

    final sourceRounds = isSearchMode ? effectiveRounds : rounds;
    final visibleRounds = sourceRounds.where((round) {
      final roundGames = gamesByRound[round.id] ?? [];
      if (roundGames.isEmpty) {
        return false;
      }

      // In search mode, show ALL rounds that have matching games
      if (isSearchMode) {
        return true;
      }

      // For multi-stage knockouts, show ALL stages with games (no status filtering)
      if (isMultiStageKnockout) {
        return true;
      }

      // Regular tournament filtering logic below
      final hasLiveOrOngoing = sourceRounds.any((r) =>
        r.roundStatus == RoundStatus.live || r.roundStatus == RoundStatus.ongoing
      );

      final hasCompleted = sourceRounds.any((r) => r.roundStatus == RoundStatus.completed);

      final allAreUpcoming = sourceRounds.every((r) =>
        r.roundStatus == RoundStatus.upcoming || gamesByRound[r.id]?.isEmpty == true
      );

      // Always include explicitly user-selected round
      if (userSelected && round.id == selectedRoundId) {
        return true;
      }

      // If all rounds are upcoming, show them all
      if (allAreUpcoming) {
        return true;
      }

      // If there are live/ongoing rounds, hide upcoming
      if (hasLiveOrOngoing) {
        return round.roundStatus != RoundStatus.upcoming;
      }

      // If only completed rounds exist, show completed + first upcoming
      if (hasCompleted && round.roundStatus == RoundStatus.upcoming) {
        // Find the first upcoming round and only show that one
      final upcomingRounds = sourceRounds.where((r) =>
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

    final orderedGamesData = gamesScreenModel.copyWith(
      gamesTourModels: orderedGamesForChessBoard,
    );

    final itemScrollController = ref.watch(gamesTourScrollProvider);
    final itemPositionsListener =
        ref.read(gamesTourScrollProvider.notifier).itemPositionsListener;

    return GamesListView(
      key: ValueKey('games_list_${gamesListViewMode.name}_search_$isSearchMode'),
      rounds: visibleRounds,
      gamesByRound: gamesByRound,
      gamesData: orderedGamesData,
      isKnockoutTournament: isKnockoutTournament,
      gamesListViewMode: gamesListViewMode,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      isSearchMode: isSearchMode,
      onReturnFromChessboard: (returnedIndex) {
        // The scrolling is already handled in GamesListView
        // This callback can be used for additional logic if needed
      },
    );
  }
}
