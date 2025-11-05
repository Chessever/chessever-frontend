import 'package:collection/collection.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:flutter/animation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart'; // adjust import path if needed
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';

/// Sticky user selection
final userSelectedRoundProvider =
    StateProvider<({String id, bool userSelected})?>((ref) => null);

/// Auto-disposed optimized provider
final gamesAppBarProvider = StateNotifierProvider<
  _GamesAppBarNotifier,
  AsyncValue<GamesAppBarViewModel>
>((ref) {
  final tourAsync = ref.watch(tourDetailScreenProvider);
  final tourId = tourAsync.value?.aboutTourModel.id;

  return _GamesAppBarNotifier(ref: ref, tourId: tourId);
});

class _GamesAppBarNotifier
    extends StateNotifier<AsyncValue<GamesAppBarViewModel>> {
  _GamesAppBarNotifier({required this.ref, required this.tourId})
    : _liveRounds = [],
      _roundSortMeta = {},
      super(const AsyncValue.loading()) {
    ref.listen<List<String>?>(
      liveRoundsIdProvider.select((a) => a.valueOrNull),
      (_, next) {
        if (next != null) _onLiveRoundsChanged(next);
      },
    );

    if (tourId != null) {
      ref.listen<KnockoutTournamentState>(
        knockoutTournamentStateProvider(tourId!),
        (previous, next) {
          if (previous == null) return;
          if (previous.isKnockout != next.isKnockout ||
              previous.stageName != next.stageName) {
            _load();
          }
        },
      );
    }

    _load();
  }

  final Ref ref;

  final String? tourId;
  List<String> _liveRounds;
  final Map<String, _RoundSortMeta> _roundSortMeta;

  Future<void> refresh() async {
    await _load();
  }

  void select(GamesAppBarModel model) {
    // For multi-stage knockouts, dropdown selection should just scroll to that stage
    // NOT navigate to a different tour (all stages are already in the listview)
    // This matches the behavior of regular and group events

    ref.read(userSelectedRoundProvider.notifier).state = (
      id: model.id,
      userSelected: true,
    );

    final current = state.valueOrNull;
    if (current == null) return;

    _scrollToRound(model.id);

    state = AsyncValue.data(
      GamesAppBarViewModel(
        gamesAppBarModels: current.gamesAppBarModels,
        selectedId: model.id,
        userSelectedId: true,
      ),
    );
  }

  void selectSilently(GamesAppBarModel model) {
    final current = state.valueOrNull;
    if (current == null) return;

    state = AsyncValue.data(
      GamesAppBarViewModel(
        gamesAppBarModels: current.gamesAppBarModels,
        selectedId: model.id,
        userSelectedId: false,
      ),
    );
  }

  Future<void> _scrollToRound(String roundId) async {
    final scrollProvider = ref.read(gamesTourScrollProvider.notifier);
    final controller = scrollProvider.state;
    final itemIndex = _calculateRoundHeaderIndex(roundId);

    // Debug logging
    print('🎯 Scrolling to round: $roundId, calculated index: $itemIndex');

    if (itemIndex >= 0 && controller.isAttached) {
      // Prevent scroll listener from updating dropdown during programmatic scroll
      scrollProvider.startProgrammaticScroll(targetRoundId: roundId);

      // Small delay to ensure layout is ready
      await Future.delayed(const Duration(milliseconds: 100));

      if (controller.isAttached) {
        try {
          // Use alignment 0.0 to position round header at the very top
          controller.jumpTo(index: itemIndex, alignment: 0.0);
        } catch (e) {
          // Fallback if jumpTo fails
          try {
            controller.scrollTo(
              index: itemIndex,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: 0.0,
            );
          } catch (_) {}
        }

        // Re-enable scroll listener after scroll completes
        scrollProvider.endProgrammaticScroll();
      }
    }
  }

  /// Extract round number from round name (e.g., "Round 9" -> 9, "round7" -> 7)
  int? _extractRoundNumber(String roundName) {
    return _parseRoundNumber(roundName);
  }

  /// Extract game number from round name (e.g., "Round 6 - Game 2" -> 2)
  int? _extractGameNumber(String roundName) {
    return _parseGameNumber(roundName);
  }

  /// Helper to check if a round ID indicates a knockout format
  bool _isKnockoutRound(String roundId) {
    final id = roundId.toLowerCase();
    return id.startsWith('$kKnockoutStagePrefix-') || id.startsWith('knockout-round-');
  }

  int _calculateRoundHeaderIndex(String roundId) {
    final vm = state.valueOrNull;
    final allRounds = vm?.gamesAppBarModels ?? [];
    final selectedId = vm?.selectedId;
    final userSelected = vm?.userSelectedId ?? false;

    // Smart filtering: Match the EXACT logic in games_tour_content_body.dart
    final gamesByRound = _buildRoundGameCounts();

    // Check if this is a multi-stage knockout (same check as in games_tour_content_body.dart)
    final isMultiStageKnockout = allRounds.any(
      (r) => r.id.startsWith('$kKnockoutStagePrefix-'),
    );

    final rounds =
        allRounds.where((round) {
          final gamesInRound = gamesByRound[round.id] ?? 0;
          if (gamesInRound == 0) return false;

          // For multi-stage knockouts, show ALL stages with games (no status filtering)
          // This matches the logic in games_tour_content_body.dart line 115-117
          if (isMultiStageKnockout) {
            return true;
          }

          // Regular tournament filtering logic below
          final hasLiveOrOngoing = allRounds.any(
            (r) =>
                r.roundStatus == RoundStatus.live ||
                r.roundStatus == RoundStatus.ongoing,
          );

          final hasCompleted = allRounds.any(
            (r) => r.roundStatus == RoundStatus.completed,
          );

          final allAreUpcoming = allRounds.every(
            (r) =>
                r.roundStatus == RoundStatus.upcoming ||
                (gamesByRound[r.id] ?? 0) == 0,
          );

          if (userSelected && selectedId == round.id) return true;

          if (allAreUpcoming) return true;

          if (hasLiveOrOngoing) {
            return round.roundStatus != RoundStatus.upcoming;
          }

          if (hasCompleted && round.roundStatus == RoundStatus.upcoming) {
            final upcomingRounds =
                allRounds
                    .where(
                      (r) =>
                          r.roundStatus == RoundStatus.upcoming &&
                          (gamesByRound[r.id] ?? 0) > 0,
                    )
                    .toList();
            return upcomingRounds.isNotEmpty &&
                upcomingRounds.first.id == round.id;
          }

          return round.roundStatus != RoundStatus.upcoming;
        }).toList();

    // Check if we're in group event mode
    final screenMode = ref.read(gamesTourScreenModeProvider).valueOrNull;
    final isGroupEvent = screenMode == GamesTourScreenMode.groupEvent;
    final viewMode = ref.read(gamesListViewModeProvider);
    final bool isGrid = viewMode == GamesListViewMode.chessBoardGrid;

    print(
      '📊 Index calculation - Target: $roundId, Mode: ${isGroupEvent ? "Group" : "Regular"}, Grid: $isGrid',
    );

    int index = 0;

    for (final round in rounds) {
      // If this is the round we want to scroll to, return the index of its header.
      if (round.id == roundId) {
        print('✅ Found target round "${round.name}" at index: $index');
        return index;
      }

      // Count items in this round (header + content items)
      int itemCount = 1; // header

      if (isGroupEvent) {
        // For group events, count team matchup cards
        final gamesData = ref.read(gamesTourScreenProvider).valueOrNull;
        if (gamesData != null) {
          final grouped = ref
              .read(gamesTourContentProvider)
              .getGroupHeader(
                selectedRoundId: round.id,
                gamesScreenModel: gamesData,
              );
          final cardCount = grouped.keys.length;
          itemCount += cardCount; // number of team matchup cards
          print(
            '   Round "${round.name}": 1 header + $cardCount cards = $itemCount items',
          );
        }
      } else {
        // For regular events, need to check if it's a knockout round
        List<GamesTourModel> roundGames;

        // Special handling for knockout stage-based rounds
        if (round.id.startsWith('$kKnockoutStagePrefix-')) {
          // For stage-based rounds, get games from knockoutTournamentStateProvider
          final stageTourId = round.id.replaceFirst(
            '$kKnockoutStagePrefix-',
            '',
          );
          final stageKnockoutState = ref.read(
            knockoutTournamentStateProvider(stageTourId),
          );
          roundGames = stageKnockoutState.allGames;
        } else {
          // Regular rounds: match by round ID
          roundGames =
              ref
                  .read(gamesTourScreenProvider)
                  .valueOrNull
                  ?.gamesTourModels
                  .where((g) => g.roundId == round.id)
                  .toList() ??
              [];
        }

        // Check if this is a knockout round (needs match headers)
        final isKnockoutRound = _isKnockoutRound(round.id);

        if (isKnockoutRound && roundGames.isNotEmpty) {
          // Knockout format: count match headers + games within each match
          final matches = KnockoutMatchDetector.groupByMatches(roundGames);
          final expansionState = ref.read(matchExpansionProvider);

          for (final entry in matches.entries) {
            final matchKey = entry.key;
            final matchGames = entry.value;
            final isExpanded = expansionState[matchKey] ?? true;

            itemCount++; // match header

            // Only count games if match is expanded
            if (isExpanded) {
              if (isGrid) {
                itemCount += (matchGames.length / 2).ceil();
              } else {
                itemCount += matchGames.length;
              }
            }
          }

          print(
            '   Round "${round.name}": 1 header + ${matches.length} match headers + games = $itemCount items',
          );
        } else {
          // Regular format: just count games
          final gamesInRound = roundGames.length;

          if (isGrid) {
            // grid: ceil(games/2) rows (each row holds up to 2 games)
            final rows = (gamesInRound / 2).ceil();
            itemCount += rows;
            print(
              '   Round "${round.name}": 1 header + $rows rows ($gamesInRound games) = $itemCount items',
            );
          } else {
            // list: one item per game
            itemCount += gamesInRound;
            print(
              '   Round "${round.name}": 1 header + $gamesInRound games = $itemCount items',
            );
          }
        }
      }

      index += itemCount;
    }

    return -1; // not found
  }

  Future<void> _load() async {
    if (tourId == null) {
      state = const AsyncValue.loading();
      return;
    }

    state = const AsyncValue.loading();
    try {
      final repo = ref.read(roundRepositoryProvider);
      final rounds = await repo.getRoundsByTourId(tourId!);

      if (rounds.isEmpty) {
        state = const AsyncValue.data(
          GamesAppBarViewModel(
            gamesAppBarModels: [],
            selectedId: '',
            userSelectedId: false,
          ),
        );
        return;
      }

      _roundSortMeta
        ..clear()
        ..addEntries(
          rounds.map(
            (round) => MapEntry(round.id, _RoundSortMeta.fromRound(round)),
          ),
        );

      final models =
          rounds
              .map((r) => GamesAppBarModel.fromRound(r, _liveRounds))
              .toList();

      // Check if this is a knockout tournament and group sub-rounds
      final processedModels = await _processKnockoutRoundsIfNeeded(models);

      _sortRounds(processedModels);

      await _applySelectionFrom(processedModels, tourId!);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Process knockout tournament rounds: group sub-rounds into logical tournament rounds
  /// For knockout tournaments, check if we're in a group event with multiple stages.
  /// If so, create separate dropdown items for each stage (Round 1, Round 2, etc.).
  /// Otherwise, aggregate all sub-rounds (game-1, game-2, tiebreak-*) into a single item.
  Future<List<GamesAppBarModel>> _processKnockoutRoundsIfNeeded(
    List<GamesAppBarModel> models,
  ) async {
    if (models.isEmpty) return models;

    final knockoutState =
        tourId != null
            ? ref.read(knockoutTournamentStateProvider(tourId!))
            : const KnockoutTournamentState.empty();

    if (!knockoutState.isKnockout) return models;

    // Check if we're in a group event with multiple tours (stages)
    final tourDetail = ref.read(tourDetailScreenProvider).valueOrNull;
    final allTours = tourDetail?.tours ?? [];

    print('🔍 Total tours in tourDetail: ${allTours.length}');
    for (final t in allTours) {
      print(
        '    - ${t.tour.name} (ID: ${t.tour.id}, groupBroadcastId: ${t.tour.groupBroadcastId})',
      );
    }

    // If there are multiple tours with the same group_broadcast_id, treat each as a stage
    final currentTour =
        allTours.where((t) => t.tour.id == tourId).firstOrNull?.tour;
    final groupBroadcastId = currentTour?.groupBroadcastId;

    print('🔑 Current tour ID: $tourId, groupBroadcastId: $groupBroadcastId');

    if (groupBroadcastId != null && groupBroadcastId.isNotEmpty) {
      // Get all tours in this group that are knockout tournaments
      final groupTours =
          allTours
              .where((t) => t.tour.groupBroadcastId == groupBroadcastId)
              .toList();

      print(
        '📊 Found ${groupTours.length} tours with groupBroadcastId: $groupBroadcastId',
      );

      if (groupTours.length > 1) {
        // Multiple stages detected - create separate dropdown items for each
        final allStageModels = <GamesAppBarModel>[];

        // Sort group tours by start date (descending - most recent first) for proper dropdown order
        groupTours.sort((a, b) {
          final aDate =
              a.tour.dates.isNotEmpty ? a.tour.dates.first : DateTime(1970);
          final bDate =
              b.tour.dates.isNotEmpty ? b.tour.dates.first : DateTime(1970);
          return bDate.compareTo(aDate); // Descending order
        });

        print(
          '🏆 Processing ${groupTours.length} tours in group broadcast (sorted by date descending)',
        );

        for (final tourModel in groupTours) {
          final tour = tourModel.tour;
          print('  📋 Tour: ${tour.name} (ID: ${tour.id})');

          // Get rounds for this specific tour first
          final repo = ref.read(roundRepositoryProvider);
          final stageRounds = await repo.getRoundsByTourId(tour.id);
          final stageRoundModels =
              stageRounds
                  .map((r) => GamesAppBarModel.fromRound(r, _liveRounds))
                  .toList();

          if (stageRoundModels.isEmpty) {
            print('    ❌ No rounds found, skipping');
            continue;
          }

          // Check if this tour is knockout format
          final stageKnockoutState = ref.read(
            knockoutTournamentStateProvider(tour.id),
          );

          if (!stageKnockoutState.isKnockout) {
            print('    ❌ Not knockout format, skipping');
            continue;
          }

          // Show ALL stages in dropdown, regardless of games (like 'about' tab does)
          final tourStatus = tourModel.roundStatus;
          print(
            '    ✓ Has ${stageRoundModels.length} rounds, ${stageKnockoutState.allGames.length} games, status: $tourStatus',
          );

          // Determine aggregated status for this stage
          RoundStatus stageStatus = RoundStatus.ongoing;
          if (stageRoundModels.any((m) => m.roundStatus == RoundStatus.live)) {
            stageStatus = RoundStatus.live;
          } else if (stageRoundModels.any(
            (m) => m.roundStatus == RoundStatus.ongoing,
          )) {
            stageStatus = RoundStatus.ongoing;
          } else if (stageRoundModels.every(
            (m) => m.roundStatus == RoundStatus.completed,
          )) {
            stageStatus = RoundStatus.completed;
          } else if (stageRoundModels.every(
            (m) => m.roundStatus == RoundStatus.upcoming,
          )) {
            stageStatus = RoundStatus.upcoming;
          }

          // Use the freshest date available to describe this stage (round or tour level)
          final stageStartsAt = _resolveStageStartDate(
            tour: tour,
            stageRoundModels: stageRoundModels,
          );

          // Extract stage name directly from tour name (e.g., "FIDE World Cup 2025 | Round 1" -> "Round 1")
          final stageName =
              tour.name.contains('|')
                  ? tour.name.split('|').last.trim()
                  : tour.name;

          print(
            '    ✅ Created stage: "$stageName" (status: $stageStatus, games: ${stageKnockoutState.allGames.length})',
          );

          final stageId = '$kKnockoutStagePrefix-${tour.id}';

          // Add metadata for this synthetic stage ID to enable proper sorting
          _roundSortMeta[stageId] = _RoundSortMeta(
            slug: tour.slug,
            createdAt: tour.createdAt,
            startsAt: stageStartsAt,
            roundNumber: _parseRoundNumber(stageName),
            gameNumber: null,
          );

          allStageModels.add(
            GamesAppBarModel(
              id: stageId,
              name: stageName,
              startsAt: stageStartsAt,
              roundStatus: stageStatus,
            ),
          );
        }

        print('🎯 Total stages created: ${allStageModels.length}');
        for (final stage in allStageModels) {
          print('   - ${stage.name} (${stage.roundStatus})');
        }

        // Return all stages - dropdown shows all, listview shows current
        // When user selects different stage, navigation happens via select() method
        if (allStageModels.isNotEmpty) {
          return allStageModels;
        }
      }
    }

    // Fallback: Single-stage knockout - aggregate all rounds into one
    final roundName =
        knockoutState.stageName ??
        ref.read(tourDetailScreenProvider).value?.aboutTourModel.name ??
        'Round';

    // Determine the aggregated round status
    RoundStatus roundStatus = RoundStatus.ongoing;
    if (models.any((m) => m.roundStatus == RoundStatus.live)) {
      roundStatus = RoundStatus.live;
    } else if (models.any((m) => m.roundStatus == RoundStatus.ongoing)) {
      roundStatus = RoundStatus.ongoing;
    } else if (models.every((m) => m.roundStatus == RoundStatus.completed)) {
      roundStatus = RoundStatus.completed;
    } else if (models.every((m) => m.roundStatus == RoundStatus.upcoming)) {
      roundStatus = RoundStatus.upcoming;
    }

    // Use the earliest start time
    final startsAt = models
        .map((m) => m.startsAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (earliest, date) {
          if (earliest == null) return date;
          return date.isBefore(earliest) ? date : earliest;
        });

    // Get created date from earliest sub-round
    final createdAt =
        models
            .map((m) => _roundSortMeta[m.id]?.createdAt)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (earliest, date) {
              if (earliest == null) return date;
              return date.isBefore(earliest) ? date : earliest;
            }) ??
        DateTime.now();

    final logicalRoundId = '$kKnockoutStagePrefix-${tourId ?? 'stage'}';

    // Add metadata for this synthetic single-stage ID to enable proper sorting
    _roundSortMeta[logicalRoundId] = _RoundSortMeta(
      slug:
          models.firstOrNull != null
              ? _roundSortMeta[models.first.id]?.slug ?? ''
              : '',
      createdAt: createdAt,
      startsAt: startsAt,
      roundNumber: _parseRoundNumber(roundName),
      gameNumber: null,
    );

    // Create a single logical tournament round from all sub-rounds
    final logicalRound = GamesAppBarModel(
      id: logicalRoundId,
      name: roundName,
      startsAt: startsAt,
      roundStatus: roundStatus,
    );

    return [logicalRound];
  }

  Map<String, int> _buildRoundGameCounts() {
    final isKnockout =
        tourId != null
            ? ref.read(knockoutTournamentStateProvider(tourId!)).isKnockout
            : false;

    if (isKnockout) {
      // For knockout tournaments, check if we have multiple stages
      final tourDetail = ref.read(tourDetailScreenProvider).valueOrNull;
      final allTours = tourDetail?.tours ?? [];
      final currentTour =
          allTours.where((t) => t.tour.id == tourId).firstOrNull?.tour;
      final groupBroadcastId = currentTour?.groupBroadcastId;

      if (groupBroadcastId != null && groupBroadcastId.isNotEmpty) {
        final groupTours =
            allTours
                .where((t) => t.tour.groupBroadcastId == groupBroadcastId)
                .toList();

        if (groupTours.length > 1) {
          // Multiple stages - count games per stage (tour)
          final counts = <String, int>{};

          for (final tourModel in groupTours) {
            final tour = tourModel.tour;
            final stageKnockoutState = ref.read(
              knockoutTournamentStateProvider(tour.id),
            );

            if (!stageKnockoutState.isKnockout) continue;

            final stageId = '$kKnockoutStagePrefix-${tour.id}';
            counts[stageId] = stageKnockoutState.allGames.length;
          }

          return counts;
        }
      }

      // Single-stage knockout - all games belong to the aggregated stage
      final games =
          ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels ??
          const <GamesTourModel>[];
      return {'$kKnockoutStagePrefix-${tourId ?? 'stage'}': games.length};
    } else {
      // Regular tournaments - count by actual round ID
      final games =
          ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels ??
          const <GamesTourModel>[];

      final counts = <String, int>{};
      for (final game in games) {
        counts.update(game.roundId, (value) => value + 1, ifAbsent: () => 1);
      }
      return counts;
    }
  }

  bool _hasGames(String roundId, Map<String, int> counts) =>
      (counts[roundId] ?? 0) > 0;

  GamesAppBarModel? _pickRoundModelByStatus(
    List<GamesAppBarModel> models,
    Map<String, int> counts,
    RoundStatus status,
  ) {
    final candidates =
        models
            .where((m) => m.roundStatus == status && _hasGames(m.id, counts))
            .toList();
    if (candidates.isEmpty) return null;

    final bool ascending = status == RoundStatus.upcoming;
    candidates.sort((a, b) => _compareByStart(a, b, ascending));
    return candidates.first;
  }

  int _compareByStart(GamesAppBarModel a, GamesAppBarModel b, bool ascending) {
    final aStart = a.startsAt;
    final bStart = b.startsAt;

    int compare;
    if (aStart == null && bStart == null) {
      compare = a.name.compareTo(b.name);
    } else if (aStart == null) {
      compare = 1;
    } else if (bStart == null) {
      compare = -1;
    } else {
      compare = aStart.compareTo(bStart);
      if (compare == 0) {
        compare = a.name.compareTo(b.name);
      }
    }

    return ascending ? compare : -compare;
  }

  GamesAppBarModel? _selectAutoRound(
    List<GamesAppBarModel> models,
    Map<String, int> counts,
  ) {
    for (final status in const [
      RoundStatus.live,
      RoundStatus.ongoing,
      RoundStatus.upcoming,
      RoundStatus.completed,
    ]) {
      final pick = _pickRoundModelByStatus(models, counts, status);
      if (pick != null) {
        return pick;
      }
    }

    for (final model in models) {
      if (_hasGames(model.id, counts)) {
        return model;
      }
    }

    return models.isNotEmpty ? models.first : null;
  }

  void _sortRounds(List<GamesAppBarModel> models) {
    // Detect if this is a multi-stage knockout (stages have synthetic IDs)
    final isMultiStageKnockout = models.any(
      (m) => m.id.startsWith('$kKnockoutStagePrefix-'),
    );

    // For multi-stage knockouts, use pure date-based sorting (skip upcoming-first logic)
    if (isMultiStageKnockout) {
      models.sort(_compareRounds);
      return;
    }

    // For regular tournaments: check if we should show next upcoming round at top
    final hasLiveOrOngoing = models.any(
      (m) =>
          m.roundStatus == RoundStatus.live ||
          m.roundStatus == RoundStatus.ongoing,
    );
    final hasCompleted = models.any(
      (m) => m.roundStatus == RoundStatus.completed,
    );
    final showNextUpcomingFirst = !hasLiveOrOngoing && hasCompleted;

    models.sort((a, b) {
      // Special case: When showing next upcoming round with completed rounds,
      // put upcoming first (top-most)
      if (showNextUpcomingFirst) {
        if (a.roundStatus == RoundStatus.upcoming &&
            b.roundStatus != RoundStatus.upcoming) {
          return -1; // Upcoming comes first
        }
        if (b.roundStatus == RoundStatus.upcoming &&
            a.roundStatus != RoundStatus.upcoming) {
          return 1; // Upcoming comes first
        }
      }

      return _compareRounds(a, b);
    });
  }

  int _compareRounds(GamesAppBarModel a, GamesAppBarModel b) {
    final aIsStage = a.id.startsWith('$kKnockoutStagePrefix-');
    final bIsStage = b.id.startsWith('$kKnockoutStagePrefix-');
    final aMeta = _roundSortMeta[a.id];
    final bMeta = _roundSortMeta[b.id];
    final aStageRank = _stageHierarchyRank(a.name);
    final bStageRank = _stageHierarchyRank(b.name);

    // When both entries are knockout stages, favour chronological (latest first)
    if (aIsStage && bIsStage) {
      final aStarts = aMeta?.startsAt ?? a.startsAt;
      final bStarts = bMeta?.startsAt ?? b.startsAt;
      final startCompare = _compareDatesDesc(aStarts, bStarts);
      if (startCompare != 0) return startCompare;

      final aPriority = _statusPriorityMap[a.roundStatus] ?? _defaultStatusRank;
      final bPriority = _statusPriorityMap[b.roundStatus] ?? _defaultStatusRank;
      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }

      final aRoundNum = aMeta?.roundNumber ?? _extractRoundNumber(a.name);
      final bRoundNum = bMeta?.roundNumber ?? _extractRoundNumber(b.name);
      final roundCompare = _compareIntsDesc(aRoundNum, bRoundNum);
      if (roundCompare != 0) return roundCompare;

      final stageRankCompare = _compareStageRanks(aStageRank, bStageRank);
      if (stageRankCompare != 0) return stageRankCompare;
    }

    // If only one entry is a knockout stage, prioritise the one with the more recent start date.
    if (aIsStage != bIsStage) {
      final aStarts = aMeta?.startsAt ?? a.startsAt;
      final bStarts = bMeta?.startsAt ?? b.startsAt;
      final startCompare = _compareDatesDesc(aStarts, bStarts);
      if (startCompare != 0) {
        final stageRankCompare = _compareStageRanks(aStageRank, bStageRank);
        if (stageRankCompare != 0) return stageRankCompare;
        return startCompare;
      }
      return aIsStage ? -1 : 1;
    }

    // Regular rounds (or fallback tie-breakers for stages)
    final aPriority = _statusPriorityMap[a.roundStatus] ?? _defaultStatusRank;
    final bPriority = _statusPriorityMap[b.roundStatus] ?? _defaultStatusRank;

    if (aPriority != bPriority) {
      return aPriority.compareTo(bPriority);
    }

    final aRoundNum = aMeta?.roundNumber ?? _extractRoundNumber(a.name);
    final bRoundNum = bMeta?.roundNumber ?? _extractRoundNumber(b.name);
    final roundCompare = _compareIntsDesc(aRoundNum, bRoundNum);
    if (roundCompare != 0) return roundCompare;

    final aStarts = aMeta?.startsAt ?? a.startsAt;
    final bStarts = bMeta?.startsAt ?? b.startsAt;
    final startCompare = _compareDatesDesc(aStarts, bStarts);
    if (startCompare != 0) return startCompare;

    final stageRankCompare = _compareStageRanks(aStageRank, bStageRank);
    if (stageRankCompare != 0) return stageRankCompare;

    final aGameNum = aMeta?.gameNumber ?? _extractGameNumber(a.name);
    final bGameNum = bMeta?.gameNumber ?? _extractGameNumber(b.name);
    final gameCompare = _compareIntsDesc(aGameNum, bGameNum);
    if (gameCompare != 0) return gameCompare;

    final createdCompare = _compareDatesDesc(
      aMeta?.createdAt,
      bMeta?.createdAt,
    );
    if (createdCompare != 0) return createdCompare;

    final slugCompare = _compareStringsDesc(aMeta?.slug, bMeta?.slug);
    if (slugCompare != 0) return slugCompare;

    return a.name.compareTo(b.name);
  }

  int _compareIntsDesc(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  int _compareDatesDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  int _compareStringsDesc(String? a, String? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.toLowerCase().compareTo(a.toLowerCase());
  }

  /// Recompute statuses on live-rounds change, update selection only if the user
  /// hasn’t made a sticky pick.
  void _onLiveRoundsChanged(List<String> newLive) {
    _liveRounds = List.unmodifiable(newLive);

    final current = state.valueOrNull;
    if (current == null) return;

    final updated =
        current.gamesAppBarModels
            .map(
              (m) => GamesAppBarModel(
                id: m.id,
                name: m.name,
                startsAt: m.startsAt,
                roundStatus: GamesAppBarModel.status(
                  currentId: m.id,
                  startsAt: m.startsAt,
                  liveRound: _liveRounds,
                ),
              ),
            )
            .toList();

    _sortRounds(updated);

    final sticky = ref.read(userSelectedRoundProvider);
    final counts = _buildRoundGameCounts();
    final hasStickyValid =
        sticky?.userSelected == true &&
        updated.any((m) => m.id == sticky!.id) &&
        _hasGames(sticky!.id, counts);

    if (hasStickyValid) {
      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: updated,
          selectedId: sticky!.id,
          userSelectedId: true,
        ),
      );
      _scrollToRound(sticky.id);
      return;
    }
    final currentSelected = current.selectedId;
    final currentStillValid =
        currentSelected.isNotEmpty &&
        updated.any((m) => m.id == currentSelected) &&
        _hasGames(currentSelected, counts);

    if (currentStillValid) {
      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: updated,
          selectedId: currentSelected,
          userSelectedId: false,
        ),
      );
      _scrollToRound(currentSelected);
      return;
    }

    final autoModel = _selectAutoRound(updated, counts);
    final nextSelected =
        autoModel?.id ?? (updated.isNotEmpty ? updated.first.id : '');

    state = AsyncValue.data(
      GamesAppBarViewModel(
        gamesAppBarModels: updated,
        selectedId: nextSelected,
        userSelectedId: false,
      ),
    );
    if (nextSelected.isNotEmpty) {
      _scrollToRound(nextSelected);
    }
  }

  Future<void> _applySelectionFrom(
    List<GamesAppBarModel> models,
    String tourId,
  ) async {
    // 1) Respect sticky user selection if still present
    final sticky = ref.read(userSelectedRoundProvider);
    final counts = _buildRoundGameCounts();
    if (sticky?.userSelected == true &&
        models.any((m) => m.id == sticky!.id) &&
        _hasGames(sticky!.id, counts)) {
      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: models,
          selectedId: sticky!.id,
          userSelectedId: true,
        ),
      );
      _scrollToRound(sticky.id);
      return;
    }

    // 2) Prefer live round
    final liveModel = _pickRoundModelByStatus(models, counts, RoundStatus.live);
    if (liveModel != null) {
      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: models,
          selectedId: liveModel.id,
          userSelectedId: false,
        ),
      );
      _scrollToRound(liveModel.id);
      return;
    }

    GamesAppBarModel? repoModel;
    try {
      final repo = ref.read(roundRepositoryProvider);
      final latest = await repo.getLatestRoundByLastMove(tourId);
      if (latest != null &&
          models.any((m) => m.id == latest.id) &&
          _hasGames(latest.id, counts)) {
        repoModel = models.firstWhere((m) => m.id == latest.id);
      }
    } catch (e) {}

    final autoModel = _selectAutoRound(models, counts);
    GamesAppBarModel? selectedModel = autoModel;

    if ((selectedModel == null ||
            selectedModel.roundStatus == RoundStatus.completed) &&
        repoModel != null) {
      selectedModel = repoModel;
    }

    final fallbackId =
        selectedModel?.id ?? (models.isNotEmpty ? models.first.id : '');
    state = AsyncValue.data(
      GamesAppBarViewModel(
        gamesAppBarModels: models,
        selectedId: fallbackId,
        userSelectedId: false,
      ),
    );
    if (fallbackId.isNotEmpty) {
      _scrollToRound(fallbackId);
    }
  }
}

const _statusPriorityMap = {
  RoundStatus.live: 0,
  RoundStatus.ongoing: 1,
  RoundStatus.completed: 2,
  RoundStatus.upcoming: 3,
};
const _defaultStatusRank = 99;

DateTime? _resolveStageStartDate({
  required Tour tour,
  required List<GamesAppBarModel> stageRoundModels,
}) {
  final candidates = <DateTime>[];
  candidates.addAll(tour.dates);
  for (final model in stageRoundModels) {
    final start = model.startsAt;
    if (start != null) {
      candidates.add(start);
    }
  }
  candidates.add(tour.createdAt);

  if (candidates.isEmpty) {
    return null;
  }

  return candidates.reduce(
    (latest, date) => date.isAfter(latest) ? date : latest,
  );
}

int? _stageHierarchyRank(String name) {
  final lower = name.toLowerCase();

  if (lower.contains('quarter')) return 2;
  if (lower.contains('semi')) return 1;
  if (lower.contains('final')) return 0;

  final roundNumber = _parseRoundNumber(name);
  if (roundNumber != null) {
    return 100 - roundNumber;
  }

  return null;
}

int _compareStageRanks(int? a, int? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

class _RoundSortMeta {
  const _RoundSortMeta({
    required this.slug,
    required this.createdAt,
    required this.startsAt,
    required this.roundNumber,
    required this.gameNumber,
  });

  final String slug;
  final DateTime createdAt;
  final DateTime? startsAt;
  final int? roundNumber;
  final int? gameNumber;

  factory _RoundSortMeta.fromRound(Round round) {
    return _RoundSortMeta(
      slug: round.slug,
      createdAt: round.createdAt,
      startsAt: round.startsAt,
      roundNumber:
          _parseRoundNumber(round.name) ?? _parseRoundNumber(round.slug),
      gameNumber: _parseGameNumber(round.name) ?? _parseGameNumber(round.slug),
    );
  }
}

int? _parseRoundNumber(String? value) {
  if (value == null || value.isEmpty) return null;
  final match =
      RegExp(r'round[\s_\-:]*?(\d+)', caseSensitive: false).firstMatch(value) ??
      RegExp(r'\b(\d{1,3})\b').firstMatch(value);
  return match != null ? int.tryParse(match.group(1)!) : null;
}

int? _parseGameNumber(String? value) {
  if (value == null || value.isEmpty) return null;
  final match = RegExp(
    r'(?:game|board|match)[\s_\-:]*?(\d+)',
    caseSensitive: false,
  ).firstMatch(value);
  return match != null ? int.tryParse(match.group(1)!) : null;
}
