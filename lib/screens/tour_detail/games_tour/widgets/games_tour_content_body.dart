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
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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

    // Detect 1v1 match format (e.g., "12-game Match") for score card
    MatchHeaderModel? matchFormatHeader;
    if (!isKnockoutTournament) {
      final tourDetail = ref.read(tourDetailScreenProvider).valueOrNull;
      final allTours = tourDetail?.tours ?? [];
      final currentTour =
          allTours.where((t) => t.tour.id == tourId).firstOrNull?.tour;
      final formatString = currentTour?.info.format;
      final allGamesForDetection = gamesScreenModel.gamesTourModels;

      if (KnockoutMatchDetector.isMatchFormat(
        formatString,
        allGamesForDetection,
      )) {
        final matches = KnockoutMatchDetector.groupByMatchesAcrossAllRounds(
          allGamesForDetection,
        );
        if (matches.isNotEmpty) {
          final entry = matches.entries.first;
          matchFormatHeader = KnockoutMatchDetector.createMatchHeader(
            entry.key,
            entry.value,
          );
        }
      }
    }

    final allGames = gamesScreenModel.gamesTourModels;
    final displayMode = gamesScreenModel.gameDisplayMode;
    final isSearchMode = gamesScreenModel.isSearchMode;

    // IMPORTANT: Watch gamesTourProvider to ensure we have the latest games data
    // This fixes a race condition where gamesScreenModel might have stale data
    // while rounds have already loaded, causing some rounds to appear empty
    final gamesAsync = ref.watch(gamesTourProvider(tourId ?? ''));

    // If games are still loading, show loading widget to prevent rounds from
    // appearing empty due to timing issues
    if (gamesAsync.isLoading && allGames.isEmpty) {
      return const TourLoadingWidget();
    }

    // Additional safeguard: If the provider has significantly more games than
    // gamesScreenModel, it means gamesScreenModel hasn't synced yet.
    // This can cause rounds to appear empty and get filtered out.
    final providerGameCount = gamesAsync.valueOrNull?.length ?? 0;
    final modelGameCount = allGames.length;
    if (!isSearchMode && providerGameCount > 0 && modelGameCount == 0) {
      // Provider has games but model doesn't - wait for sync
      return const TourLoadingWidget();
    }

    // Group games by round while preserving the original sorting within each round
    final gamesByRound = <String, List<GamesTourModel>>{};
    // Track seen game IDs per round to prevent duplicates
    final seenGameIdsPerRound = <String, Set<String>>{};
    final roundLookup = <String, GamesAppBarModel>{
      for (final round in rounds) round.id: round,
    };

    final Set<String>? searchGameIds =
        isSearchMode ? allGames.map((g) => g.gameId).toSet() : null;

    void ensureRoundEntry(String roundId) {
      gamesByRound.putIfAbsent(roundId, () => <GamesTourModel>[]);
      seenGameIdsPerRound.putIfAbsent(roundId, () => <String>{});
    }

    /// Adds a game to round only if not already present (prevents duplicates)
    bool addGameToRound(String roundId, GamesTourModel game) {
      ensureRoundEntry(roundId);
      if (seenGameIdsPerRound[roundId]!.add(game.gameId)) {
        gamesByRound[roundId]!.add(game);
        return true;
      }
      return false; // Duplicate, not added
    }

    // Initialize empty lists for each known round
    for (final round in rounds) {
      ensureRoundEntry(round.id);
    }

    // Check if this is a multi-stage knockout and ensure ALL stages have loaded before proceeding
    // IMPORTANT: Skip multi-stage loading when in search mode - use filtered games instead
    final isMultiStageKnockout = isKnockoutTournament &&
        rounds.any((r) => r.id.startsWith('$kKnockoutStagePrefix-'));

    // Distinguish between multi-tour knockouts (where stages are separate tours) and
    // round-slug-derived stages (where stages are extracted from round_slug within one tour).
    // Multi-tour stage IDs: "knockout-stage-{tourId}" (suffix is a valid tour ID)
    // Round-slug stage IDs: "knockout-stage-{tourId}-{stageName}" (suffix includes stage name)
    final isRoundSlugDerivedStages = isMultiStageKnockout && tourId != null &&
        rounds.any((r) {
          if (!r.id.startsWith('$kKnockoutStagePrefix-')) return false;
          final suffix = r.id.replaceFirst('$kKnockoutStagePrefix-', '');
          // If suffix contains the tourId plus more (e.g., "m2z9tePv-round-1"),
          // it's a round-slug-derived stage, not a multi-tour stage
          return suffix.startsWith('$tourId-') && suffix.length > tourId!.length + 1;
        });

    if (isMultiStageKnockout && !isRoundSlugDerivedStages) {
      // Multi-tour knockout: each stage is a separate tour
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
      // DO NOT filter by displayMode here - filtering happens at rendering level for knockout
      for (final round in rounds) {
        if (round.id.startsWith('$kKnockoutStagePrefix-')) {
          // Extract the tour ID from the stage ID: "knockout-stage-{tourId}"
          final stageTourId = round.id.replaceFirst('$kKnockoutStagePrefix-', '');

          // Watch the state to rebuild when games update
          final stageKnockoutState =
              ref.watch(knockoutTournamentStateProvider(stageTourId));
          final stageGames = stageKnockoutState.allGames.where((game) {
            final matchesSearch =
                searchGameIds == null || searchGameIds.contains(game.gameId);
            // Only apply search filter, NOT displayMode filter for knockout
            return matchesSearch;
          }).toList(growable: false);
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
    } else if (isRoundSlugDerivedStages) {
      // Round-slug-derived knockout: stages are extracted from round_slug within one tour
      // Group games by matching their roundSlug prefix to the stage name in round.id
      for (final game in allGames) {
        final gameSlug = game.roundSlug ?? '';
        // Extract stage name from game's round_slug (e.g., "round-1--game-1" -> "round-1")
        final stagePart = gameSlug.contains('--')
            ? gameSlug.split('--').first.toLowerCase().replaceAll(' ', '-')
            : gameSlug.toLowerCase().replaceAll(' ', '-');

        // Find the matching stage round
        for (final round in rounds) {
          if (!round.id.startsWith('$kKnockoutStagePrefix-')) continue;
          // Extract stage name from round ID (e.g., "knockout-stage-m2z9tePv-round-1" -> "round-1")
          final roundStagePart = round.id.split('-').skip(3).join('-'); // Skip "knockout-stage-{tourId}"
          if (roundStagePart == stagePart) {
            final matchesSearch =
                searchGameIds == null || searchGameIds.contains(game.gameId);
            if (matchesSearch) {
              addGameToRound(round.id, game);
            }
            break;
          }
        }
      }

      // Sort games in each round by pin status
      final pinnedGameIds = gamesScreenModel.pinnedGamedIs;
      if (pinnedGameIds.isNotEmpty) {
        for (final roundId in gamesByRound.keys) {
          final roundGames = gamesByRound[roundId]!;
          roundGames.sort((a, b) {
            final aPinned = pinnedGameIds.contains(a.gameId);
            final bPinned = pinnedGameIds.contains(b.gameId);
            if (aPinned != bPinned) {
              return aPinned ? -1 : 1;
            }
            return 0;
          });
        }
      }
    } else {
      // For regular tournaments OR single-stage knockouts, use games from gamesScreenModel
      // For knockout tournaments: DO NOT filter by displayMode here - filtering happens at rendering level
      // For regular tournaments: Apply displayMode filter here
      for (final game in allGames) {
        // Only apply displayMode filter for non-knockout tournaments
        if (!isKnockoutTournament && !_shouldIncludeGame(displayMode, game)) continue;
        addGameToRound(game.roundId, game);

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
        final upcomingRounds = _sortRoundsByStartAsc(
          sourceRounds
              .where(
                (r) =>
                    r.roundStatus == RoundStatus.upcoming &&
                    (gamesByRound[r.id]?.isNotEmpty ?? false),
              )
              .toList(),
        );
        return upcomingRounds.isNotEmpty && upcomingRounds.first.id == round.id;
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
            ref.read(gamesTourAutoScrollProvider(scopeId).notifier).state = true;
            final scrollNotifier =
                ref.read(gamesTourScrollProvider(scopeId).notifier);
            final controller = scrollNotifier.scrollController;
            scrollNotifier.startProgrammaticScroll(targetRoundId: targetRoundId);
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

    // Create a properly ordered flat list that matches the ListView display order
    final orderedGamesForChessBoard = <GamesTourModel>[];
    for (final round in visibleRounds) {
      final roundGames = gamesByRound[round.id] ?? [];
      orderedGamesForChessBoard.addAll(roundGames);
    }

    final orderedGamesData = gamesScreenModel.copyWith(
      gamesTourModels: orderedGamesForChessBoard,
    );

    print('📜 GamesTourContentBody - scopeId: $scopeId');
    final itemScrollController = ref.watch(gamesTourScrollProvider(scopeId));
    print('📜 GamesTourContentBody - controller attached: ${itemScrollController.isAttached}');
    final itemPositionsListener =
        ref.read(gamesTourScrollProvider(scopeId).notifier).itemPositionsListener;

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
      rounds.where((round) => round.roundStatus == RoundStatus.upcoming).toList();
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
    debugPrint('❌ Auto-scroll gave up for $roundId after $maxAttempts attempts');
    scrollNotifier.endProgrammaticScroll();
  }
}

bool _shouldIncludeGame(
  GameDisplayMode mode,
  GamesTourModel game,
) {
  switch (mode) {
    case GameDisplayMode.hideFinishedGames:
      return !game.gameStatus.isFinished;
    case GameDisplayMode.showfinishedGame:
      return game.gameStatus.isFinished;
    case GameDisplayMode.all:
      return true;
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
