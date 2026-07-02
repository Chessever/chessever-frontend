import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_list_view.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';

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
    final groupedData = ref.watch(gamesTourGroupedProvider);
    if (groupedData.isLoading) {
      return const TourLoadingWidget();
    }

    final gamesByRound = groupedData.gamesByRound;
    final effectiveRounds = groupedData.filteredRounds;
    final matchFormatHeader = groupedData.matchFormatHeader;
    final isKnockoutTournament = groupedData.isKnockoutTournament;
    final isMultiStageKnockout = groupedData.isMultiStageKnockout;
    final rounds = groupedData.rounds;
    final allGames = groupedData.allGames;
    final providerGameCount = groupedData.providerGameCount;

    final gamesAppBar = ref.watch(gamesAppBarProvider);
    final selectedRoundId = gamesAppBar.value?.selectedId;
    final userSelected = gamesAppBar.value?.userSelectedId ?? false;
    final isSearchMode = gamesScreenModel.isSearchMode;
    final displayMode = gamesScreenModel.gameDisplayMode;

    // Smart filtering: Show upcoming rounds intelligently
    // FOR SEARCH MODE: Show ALL rounds with matching games (ignore status)
    // FOR MULTI-STAGE KNOCKOUTS: Show ALL stages with games (no status filtering)
    // FOR REGULAR EVENTS:
    // 1. If there are live/ongoing rounds → hide upcoming rounds (unless explicitly selected)
    // 2. If only completed rounds exist → show next upcoming round
    // 3. If all rounds are upcoming → show all upcoming rounds

    final upcomingPairingIds = groupedData.upcomingPairingRoundIds;
    final sourceRounds =
        (isSearchMode ? effectiveRounds : rounds)
            .where((round) => !upcomingPairingIds.contains(round.id))
            .toList();

    // Debug: Log rounds with empty games to help diagnose timing issues
    if (!isSearchMode && !isMultiStageKnockout) {
      for (final round in sourceRounds) {
        final gamesInRound = gamesByRound[round.id]?.length ?? 0;
        if (gamesInRound == 0) {
          debugPrint(
            '⚠️ GamesTourContentBody: Round "${round.name}" (${round.id}) has 0 games. '
            'Total allGames: ${allGames.length}, Provider games: $providerGameCount',
          );
        }
      }
    }

    final isPreConfigured = sourceRounds.every((r) => r.startsAt != null);
    final hasLiveOrOngoing = sourceRounds.any(
      (r) =>
          r.roundStatus == RoundStatus.live ||
          r.roundStatus == RoundStatus.ongoing,
    );
    final hasCompleted = sourceRounds.any(
      (r) => r.roundStatus == RoundStatus.completed,
    );
    final allAreUpcoming = sourceRounds.every(
      (r) =>
          r.roundStatus == RoundStatus.upcoming ||
          gamesByRound[r.id]?.isEmpty == true,
    );

    final visibleRounds =
        sourceRounds.where((round) {
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

          if (isPreConfigured) return true;

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
            final upcomingRounds = _sortRoundsByStartAsc(
              sourceRounds
                  .where(
                    (r) =>
                        r.roundStatus == RoundStatus.upcoming &&
                        (gamesByRound[r.id]?.isNotEmpty ?? false),
                  )
                  .toList(),
            );
            return upcomingRounds.isNotEmpty &&
                upcomingRounds.first.id == round.id;
          }

          // Show completed/ongoing/live rounds
          return round.roundStatus != RoundStatus.upcoming;
        }).toList();

    final scopeId = ref.watch(gamesTourScrollScopeProvider);
    final autoScrollDone = ref.watch(gamesTourAutoScrollProvider(scopeId));
    if (!autoScrollDone &&
        !isSearchMode &&
        visibleRounds.isNotEmpty &&
        !userSelected &&
        _allRoundsUpcoming(visibleRounds)) {
      final targetRoundId = _pickUpcomingRoundId(
        visibleRounds,
        selectedRoundId,
      );
      if (targetRoundId != null) {
        final itemIndex = ref
            .read(gamesAppBarProvider.notifier)
            .calculateRoundIndex(targetRoundId);
        if (itemIndex >= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ref.read(gamesTourAutoScrollProvider(scopeId))) {
              return;
            }
            ref.read(gamesTourAutoScrollProvider(scopeId).notifier).state =
                true;
            final scrollNotifier = ref.read(
              gamesTourScrollProvider(scopeId).notifier,
            );
            final controller = scrollNotifier.scrollController;
            scrollNotifier.startProgrammaticScroll(
              targetRoundId: targetRoundId,
            );
            _attemptScrollToRound(
              controller,
              scrollNotifier,
              itemIndex,
              targetRoundId,
              0,
            );
          });
        }
      }
    }

    // Future rounds with published pairings render below everything else,
    // soonest first (effectiveRounds already carries them pre-sorted at the
    // tail).
    final upcomingPairingRounds =
        effectiveRounds
            .where((round) => upcomingPairingIds.contains(round.id))
            .toList();
    final displayRounds = [...visibleRounds, ...upcomingPairingRounds];

    // Create a properly ordered flat list that matches the ListView display order
    final orderedGamesForChessBoard = <GamesTourModel>[];
    for (final round in displayRounds) {
      final roundGames = gamesByRound[round.id] ?? [];
      orderedGamesForChessBoard.addAll(roundGames);
    }

    final orderedGamesData = gamesScreenModel.copyWith(
      gamesTourModels: orderedGamesForChessBoard,
    );

    final itemScrollController = ref.watch(gamesTourScrollProvider(scopeId));
    final itemPositionsListener =
        ref
            .read(gamesTourScrollProvider(scopeId).notifier)
            .itemPositionsListener;

    return GamesListView(
      key: ValueKey(
        'games_list_${gamesListViewMode.name}_search_$isSearchMode',
      ),
      rounds: displayRounds,
      gamesByRound: gamesByRound,
      gamesData: orderedGamesData,
      isKnockoutTournament: isKnockoutTournament,
      gamesListViewMode: gamesListViewMode,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      isSearchMode: isSearchMode,
      displayMode: displayMode,
      matchFormatHeader: matchFormatHeader,
      onReturnFromChessboard: (returnedIndex) {
        // The scrolling is already handled in GamesListView
        // This callback can be used for additional logic if needed
      },
    );
  }
}

bool _allRoundsUpcoming(List<GamesAppBarModel> rounds) {
  return rounds.isNotEmpty &&
      rounds.every((round) => round.roundStatus == RoundStatus.upcoming);
}

String? _pickUpcomingRoundId(
  List<GamesAppBarModel> rounds,
  String? selectedRoundId,
) {
  if (selectedRoundId != null &&
      rounds.any((round) => round.id == selectedRoundId)) {
    return selectedRoundId;
  }

  final upcomingRounds =
      rounds
          .where((round) => round.roundStatus == RoundStatus.upcoming)
          .toList();
  if (upcomingRounds.isEmpty) {
    return null;
  }

  upcomingRounds.sort((a, b) {
    final aStart = a.startsAt;
    final bStart = b.startsAt;
    if (aStart == null && bStart == null) {
      return a.name.compareTo(b.name);
    }
    if (aStart == null) return 1;
    if (bStart == null) return -1;
    final cmp = aStart.compareTo(bStart);
    return cmp != 0 ? cmp : a.name.compareTo(b.name);
  });

  return upcomingRounds.first.id;
}

void _attemptScrollToRound(
  ItemScrollController controller,
  dynamic scrollNotifier,
  int itemIndex,
  String roundId,
  int attempt,
) {
  const maxAttempts = 5;
  const retryDelay = Duration(milliseconds: 100);

  if (controller.isAttached) {
    try {
      controller.jumpTo(index: itemIndex, alignment: 0.0);
    } catch (e) {
      debugPrint('❌ Auto-scroll jumpTo failed for $roundId: $e');
    }
    scrollNotifier.endProgrammaticScroll();
  } else if (attempt < maxAttempts) {
    Future.delayed(retryDelay, () {
      _attemptScrollToRound(
        controller,
        scrollNotifier,
        itemIndex,
        roundId,
        attempt + 1,
      );
    });
  } else {
    debugPrint(
      '❌ Auto-scroll gave up for $roundId after $maxAttempts attempts',
    );
    scrollNotifier.endProgrammaticScroll();
  }
}

List<GamesAppBarModel> _sortRoundsByStartAsc(List<GamesAppBarModel> rounds) {
  rounds.sort((a, b) {
    final aStart = a.startsAt;
    final bStart = b.startsAt;
    if (aStart == null && bStart == null) {
      return a.name.compareTo(b.name);
    }
    if (aStart == null) return 1;
    if (bStart == null) return -1;
    final cmp = aStart.compareTo(bStart);
    return cmp == 0 ? a.name.compareTo(b.name) : cmp;
  });
  return rounds;
}
