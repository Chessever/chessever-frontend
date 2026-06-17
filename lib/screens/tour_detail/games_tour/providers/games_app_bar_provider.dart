// ignore_for_file: avoid_print, empty_catches, unused_element

import 'package:collection/collection.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_ordering.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
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
final gamesAppBarProvider = StateNotifierProvider.autoDispose<
  _GamesAppBarNotifier,
  AsyncValue<GamesAppBarViewModel>
>((ref) {
  final tourId = ref.watch(
    tourDetailScreenProvider.select(
      (tourAsync) => tourAsync.valueOrNull?.aboutTourModel.id,
    ),
  );

  return _GamesAppBarNotifier(ref: ref, tourId: tourId);
});

class _GamesAppBarNotifier
    extends StateNotifier<AsyncValue<GamesAppBarViewModel>> {
  _GamesAppBarNotifier({required this.ref, required this.tourId})
    : _liveRounds = [],
      _roundSortMeta = {},
      super(const AsyncValue.loading()) {
    // Seed from the current value before subscribing — `ref.listen` does not
    // fire for the existing emission, so a freshly recreated notifier (e.g.
    // after a tourDetailScreenProvider republish) would otherwise compute
    // round statuses with `_liveRounds == []` and mark a currently-live
    // round as `upcoming`, hiding it from `visibleRounds`.
    final initialLiveRounds = ref.read(liveRoundsIdProvider).valueOrNull;
    if (initialLiveRounds != null && initialLiveRounds.isNotEmpty) {
      _liveRounds = List.unmodifiable(initialLiveRounds);
    }

    ref.listen<List<String>?>(
      liveRoundsIdProvider.select((a) => a.valueOrNull),
      (_, next) {
        if (next != null) _onLiveRoundsChanged(next);
      },
    );

    if (tourId != null) {
      ref.listen<AsyncValue<List<Games>>>(gamesTourProvider(tourId!), (
        previous,
        next,
      ) {
        final games = next.valueOrNull;
        if (games == null) return;

        final signature = _roundCountSignature(games);
        if (signature == _lastRoundCountSignature) return;

        _lastRoundCountSignature = signature;
        _refreshSelectionAfterGamesChange(games);
      });

      ref.listen<KnockoutTournamentState>(
        knockoutTournamentStateProvider(tourId!),
        (previous, next) {
          if (previous == null) return;
          // Reload when knockout state changes OR when games transition from
          // empty to non-empty. This fixes a race condition where stage
          // extraction runs before games are loaded, causing all games to be
          // aggregated into a single round instead of proper stages.
          final gamesWereEmpty = previous.allGames.isEmpty;
          final gamesNowAvailable = next.allGames.isNotEmpty;
          if (previous.isKnockout != next.isKnockout ||
              previous.stageName != next.stageName ||
              (gamesWereEmpty && gamesNowAvailable)) {
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
  String? _lastRoundCountSignature;
  bool _selectionRefreshScheduled = false;

  Future<void> refresh() async {
    await _load();
  }

  void select(GamesAppBarModel model) {
    // For multi-stage knockouts, dropdown selection should just scroll to that stage
    // NOT navigate to a different tour (all stages are already in the listview)
    // This matches the behavior of regular and group events

    print('🔵 select() called with round: ${model.name} (${model.id})');

    final current = state.valueOrNull;
    if (current == null) {
      print('❌ select() - current state is null, returning early');
      return;
    }

    final counts = _buildRoundGameCounts();
    var targetModel = model;

    // Never allow selecting a round with zero games.
    if (!_hasGames(targetModel.id, counts)) {
      final fallback = _selectAutoRound(current.gamesAppBarModels, counts);
      if (fallback == null) {
        print(
          '⚠️ select() - no selectable non-empty rounds, ignoring selection',
        );
        return;
      }
      print(
        '⚠️ select() - requested empty round (${targetModel.id}), redirecting to ${fallback.id}',
      );
      targetModel = fallback;
    }

    ref.read(userSelectedRoundProvider.notifier).state = (
      id: targetModel.id,
      userSelected: true,
    );

    print('🔵 select() - calling _scrollToRound');
    _scrollToRound(targetModel.id);

    state = AsyncValue.data(
      GamesAppBarViewModel(
        gamesAppBarModels: current.gamesAppBarModels,
        selectedId: targetModel.id,
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

  /// Public method to calculate round index (for use from widget context)
  int calculateRoundIndex(String roundId) {
    return _calculateRoundHeaderIndex(roundId);
  }

  /// Get list of visible round IDs using the same filtering logic as games_tour_content_body.dart
  /// This is used by collapse/expand all buttons to only affect visible rounds
  List<String> getVisibleRoundIds() {
    final vm = state.valueOrNull;
    final allRounds = vm?.gamesAppBarModels ?? [];
    if (allRounds.isEmpty) return [];

    final selectedId = vm?.selectedId;
    final userSelected = vm?.userSelectedId ?? false;
    final screenMode = ref.read(gamesTourScreenModeProvider).valueOrNull;
    final isGroupEvent = screenMode == GamesTourScreenMode.groupEvent;

    final gamesByRound = _buildRoundGameCounts();

    if (isGroupEvent) {
      return allRounds
          .where((round) {
            final gamesInRound = gamesByRound[round.id] ?? 0;
            if (gamesInRound == 0) return false;

            if (userSelected && selectedId == round.id) {
              return true;
            }

            return round.roundStatus != RoundStatus.upcoming;
          })
          .map((round) => round.id)
          .toList();
    }

    // Smart filtering: Match the EXACT logic in games_tour_content_body.dart

    // Check if this is a multi-stage knockout
    final isMultiStageKnockout = allRounds.any(
      (r) => r.id.startsWith('$kKnockoutStagePrefix-'),
    );
    final isPreConfigured = allRounds.every(_hasConfiguredStartTime);
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

    final visibleRounds =
        allRounds.where((round) {
          final gamesInRound = gamesByRound[round.id] ?? 0;
          if (gamesInRound == 0) return false;

          // For multi-stage knockouts, show ALL stages with games (no status filtering)
          if (isMultiStageKnockout) {
            return true;
          }

          if (isPreConfigured) return true;

          // Always include explicitly user-selected round
          if (userSelected && selectedId == round.id) return true;

          // If all rounds are upcoming, show them all
          if (allAreUpcoming) return true;

          // If there are live/ongoing rounds, hide upcoming
          if (hasLiveOrOngoing) {
            return round.roundStatus != RoundStatus.upcoming;
          }

          // If only completed rounds exist, show completed + first upcoming
          if (hasCompleted && round.roundStatus == RoundStatus.upcoming) {
            final upcomingRounds =
                allRounds
                    .where(
                      (r) =>
                          r.roundStatus == RoundStatus.upcoming &&
                          (gamesByRound[r.id] ?? 0) > 0,
                    )
                    .toList()
                  ..sort((a, b) => _compareByStart(a, b, true));
            return upcomingRounds.isNotEmpty &&
                upcomingRounds.first.id == round.id;
          }

          // Show completed/ongoing/live rounds
          return round.roundStatus != RoundStatus.upcoming;
        }).toList();

    return visibleRounds.map((r) => r.id).toList();
  }

  /// Get match keys for knockout sections that are currently visible in the list.
  /// Collapse/expand actions should follow the sections the user can currently see.
  List<String> getVisibleMatchKeys([Iterable<String>? visibleRoundIds]) {
    final knockoutState =
        tourId != null
            ? ref.read(knockoutTournamentStateProvider(tourId!))
            : const KnockoutTournamentState.empty();

    // We only care about match keys if it's a knockout tournament
    if (!knockoutState.isKnockout) {
      return [];
    }

    final targetRoundIds = (visibleRoundIds ?? getVisibleRoundIds()).toSet();
    if (targetRoundIds.isEmpty) return [];

    final matchKeys = <String>[];
    final gamesData = ref.read(gamesTourScreenProvider).valueOrNull;
    final allGames = gamesData?.gamesTourModels ?? [];

    for (final roundId in targetRoundIds) {
      if (!_isKnockoutRound(roundId)) {
        continue;
      }

      List<GamesTourModel> roundGames;
      if (roundId.startsWith('$kKnockoutStagePrefix-')) {
        final stageTourId = roundId.replaceFirst('$kKnockoutStagePrefix-', '');
        final stageKnockoutState = ref.read(
          knockoutTournamentStateProvider(stageTourId),
        );
        roundGames = stageKnockoutState.allGames;
      } else {
        roundGames = allGames.where((g) => g.roundId == roundId).toList();
      }

      if (roundGames.isEmpty) continue;

      final matches = KnockoutMatchDetector.groupByMatches(roundGames);
      matchKeys.addAll(matches.keys);
    }

    return matchKeys;
  }

  /// Get all rounds that currently have games in the Games tab dataset.
  /// This is used by the menu actions so "Expand all" / "Collapse all"
  /// always affect the full list dataset, not only the currently visible slice.
  List<String> getAllRoundIdsWithGames() {
    final vm = state.valueOrNull;
    final allRounds = vm?.gamesAppBarModels ?? [];
    if (allRounds.isEmpty) return [];

    final gamesByRound = _buildRoundGameCounts();

    return allRounds
        .where((round) => (gamesByRound[round.id] ?? 0) > 0)
        .map((round) => round.id)
        .toList(growable: false);
  }

  Future<void> _scrollToRound(String roundId) async {
    final scopeId = resolveGamesTourScrollScope(ref);
    print('🔵 _scrollToRound - scopeId: $scopeId');

    // Retry with increasing delays to handle category switches where games
    // haven't loaded yet. Re-compute the index each attempt since game data
    // may arrive between retries.
    const maxAttempts = 10;
    const retryDelays = [50, 100, 150, 200, 300, 400, 500, 600, 800, 1000];

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: retryDelays[attempt]));
      }

      final scrollProvider = ref.read(
        gamesTourScrollProvider(scopeId).notifier,
      );
      final controller = scrollProvider.state;
      final itemIndex = _calculateRoundHeaderIndex(roundId);

      print(
        '🎯 Scroll attempt ${attempt + 1}: roundId=$roundId, index=$itemIndex, attached=${controller.isAttached}',
      );

      if (itemIndex < 0) {
        // Games not loaded yet or round not found — retry
        print('⏳ _scrollToRound - index < 0, retrying...');
        continue;
      }

      if (!controller.isAttached) {
        // Controller not ready — retry
        print('⏳ _scrollToRound - controller not attached, retrying...');
        continue;
      }

      // Ready to scroll
      scrollProvider.startProgrammaticScroll(targetRoundId: roundId);

      // Small delay to ensure layout is stable
      await Future.delayed(const Duration(milliseconds: 50));

      if (controller.isAttached) {
        try {
          print('🎯 Executing jumpTo(index: $itemIndex)');
          controller.jumpTo(index: itemIndex, alignment: 0.0);
          print('✅ jumpTo completed successfully');
        } catch (e) {
          print('⚠️ jumpTo failed: $e, trying scrollTo...');
          try {
            controller.scrollTo(
              index: itemIndex,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: 0.0,
            );
          } catch (e2) {
            print('❌ scrollTo also failed: $e2');
          }
        }
      }

      scrollProvider.endProgrammaticScroll();
      return; // Success — exit retry loop
    }

    print(
      '❌ _scrollToRound - gave up after $maxAttempts attempts for roundId=$roundId',
    );
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
    return id.startsWith('$kKnockoutStagePrefix-') ||
        id.startsWith('knockout-round-');
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
    final isPreConfigured = allRounds.every(_hasConfiguredStartTime);
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

    final rounds =
        allRounds.where((round) {
          final gamesInRound = gamesByRound[round.id] ?? 0;
          if (gamesInRound == 0) return false;

          // For multi-stage knockouts, show ALL stages with games (no status filtering)
          // This matches the logic in games_tour_content_body.dart line 115-117
          if (isMultiStageKnockout) {
            return true;
          }

          if (isPreConfigured) return true;

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
                    .toList()
                  ..sort((a, b) => _compareByStart(a, b, true));
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

    // Read round expansion state to match games_list_view.dart behavior
    final roundExpansionState = ref.read(roundExpansionProvider);

    // Check for 1v1 match format score card (adds 1 item at top)
    final knockoutState =
        tourId != null
            ? ref.read(knockoutTournamentStateProvider(tourId!))
            : const KnockoutTournamentState.empty();
    final isKnockoutTournament = knockoutState.isKnockout;
    int matchFormatOffset = 0;
    if (!isKnockoutTournament && tourId != null) {
      final tourDetail = ref.read(tourDetailScreenProvider).valueOrNull;
      final allTours = tourDetail?.tours ?? [];
      final currentTour =
          allTours.where((t) => t.tour.id == tourId).firstOrNull?.tour;
      final formatString = currentTour?.info.format;
      final allGameModels =
          ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels ??
          const <GamesTourModel>[];
      if (KnockoutMatchDetector.isMatchFormat(formatString, allGameModels)) {
        matchFormatOffset = 1;
      }
    }

    print(
      '📊 Index calculation - Target: $roundId, Mode: ${isGroupEvent ? "Group" : "Regular"}, Grid: $isGrid',
    );

    int index = matchFormatOffset;

    for (final round in rounds) {
      // If this is the round we want to scroll to, return the index of its header.
      if (round.id == roundId) {
        print('✅ Found target round "${round.name}" at index: $index');
        return index;
      }

      // Count items in this round (header + content items)
      int itemCount = 1; // header

      // Check if round is expanded (default is true, matching games_list_view.dart)
      final isRoundExpanded = roundExpansionState[round.id] ?? true;

      // If round is collapsed, only count the header (skip games)
      if (!isRoundExpanded) {
        print('   Round "${round.name}": collapsed, only header = 1 item');
        index += itemCount;
        continue;
      }

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
            final isExpanded = resolveMatchExpansionState(
              expansionState,
              matchKey,
            );

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

  Future<void> _load({
    bool showLoading = true,
    bool scrollSelection = true,
  }) async {
    if (tourId == null) {
      if (showLoading) {
        state = const AsyncValue.loading();
      }
      return;
    }

    if (showLoading) {
      state = const AsyncValue.loading();
    }
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

      await _applySelectionFrom(
        processedModels,
        tourId!,
        scrollSelection: scrollSelection,
      );
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

    // Fallback: Single-stage knockout - try to extract stages from round_slug
    // Round slugs follow pattern: "{stage}--{subround}" e.g., "quarterfinals--game-1", "round-1--game-2"
    final allGames = knockoutState.allGames;

    if (allGames.isNotEmpty) {
      // Extract unique stages from round_slug values
      final stageGamesMap = <String, List<GamesAppBarModel>>{};

      for (final game in allGames) {
        final slug = game.roundSlug ?? '';
        String stageName;

        if (slug.contains('--')) {
          // Extract stage name from before '--'
          final stagePart = slug.split('--').first;
          stageName = _formatStageName(stagePart);
        } else if (slug.isNotEmpty) {
          // Use the slug itself if no '--' separator
          stageName = _formatStageName(slug);
        } else {
          stageName = 'Round';
        }

        // Find or create the corresponding GamesAppBarModel from models list
        // Match by the game's roundId
        final matchingModel =
            models.where((m) => m.id == game.roundId).firstOrNull;
        if (matchingModel != null) {
          stageGamesMap.putIfAbsent(stageName, () => []).add(matchingModel);
        }
      }

      print(
        '📋 Extracted ${stageGamesMap.length} stages from round_slug: ${stageGamesMap.keys.toList()}',
      );

      if (stageGamesMap.length > 1) {
        // Multiple stages found - create separate dropdown items for each
        final stageModels = <GamesAppBarModel>[];

        for (final entry in stageGamesMap.entries) {
          final stageName = entry.key;
          final stageRounds = entry.value.toSet().toList(); // Remove duplicates

          // Determine aggregated status for this stage
          RoundStatus stageStatus = RoundStatus.ongoing;
          if (stageRounds.any((m) => m.roundStatus == RoundStatus.live)) {
            stageStatus = RoundStatus.live;
          } else if (stageRounds.any(
            (m) => m.roundStatus == RoundStatus.ongoing,
          )) {
            stageStatus = RoundStatus.ongoing;
          } else if (stageRounds.every(
            (m) => m.roundStatus == RoundStatus.completed,
          )) {
            stageStatus = RoundStatus.completed;
          } else if (stageRounds.every(
            (m) => m.roundStatus == RoundStatus.upcoming,
          )) {
            stageStatus = RoundStatus.upcoming;
          }

          // Use the latest event datetime from this stage's rounds
          final stageStartsAt = stageRounds
              .map((m) => m.startsAt)
              .whereType<DateTime>()
              .fold<DateTime?>(null, (latest, date) {
                if (latest == null) return date;
                return date.isAfter(latest) ? date : latest;
              });

          final stageCreatedAt =
              stageRounds
                  .map((m) => _roundSortMeta[m.id]?.createdAt)
                  .whereType<DateTime>()
                  .fold<DateTime?>(null, (latest, date) {
                    if (latest == null) return date;
                    return date.isAfter(latest) ? date : latest;
                  }) ??
              DateTime.now();

          final stageId =
              '$kKnockoutStagePrefix-${tourId ?? 'stage'}-${stageName.toLowerCase().replaceAll(' ', '-')}';

          // Add metadata for this stage
          _roundSortMeta[stageId] = _RoundSortMeta(
            slug: stageName.toLowerCase().replaceAll(' ', '-'),
            createdAt: stageCreatedAt,
            startsAt: stageStartsAt,
            roundNumber: _parseRoundNumber(stageName),
            gameNumber: null,
          );

          print(
            '    ✅ Stage "$stageName": ${stageRounds.length} rounds, status: $stageStatus, roundNumber: ${_parseRoundNumber(stageName)}',
          );

          stageModels.add(
            GamesAppBarModel(
              id: stageId,
              name: stageName,
              startsAt: stageStartsAt,
              roundStatus: stageStatus,
            ),
          );
        }

        return stageModels;
      }
    }

    // Ultimate fallback: aggregate all rounds into one
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

    // Use the latest event datetime across all sub-rounds.
    final startsAt = models
        .map((m) => m.startsAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (latest, date) {
          if (latest == null) return date;
          return date.isAfter(latest) ? date : latest;
        });

    // Get created date from latest sub-round
    final createdAt =
        models
            .map((m) => _roundSortMeta[m.id]?.createdAt)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (latest, date) {
              if (latest == null) return date;
              return date.isAfter(latest) ? date : latest;
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

  /// Format stage name from slug part (e.g., "round-1" -> "Round 1", "quarterfinals" -> "Quarterfinals")
  String _formatStageName(String stagePart) {
    final lower = stagePart.toLowerCase().trim();

    // Handle common stage patterns
    if (lower.startsWith('round-')) {
      final num = lower.replaceAll('round-', '');
      return 'Round $num';
    }
    if (lower == 'quarterfinals' || lower == 'quarterfinal') {
      return 'Quarterfinals';
    }
    if (lower == 'semifinals' || lower == 'semifinal') {
      return 'Semifinals';
    }
    if (lower == 'finals' || lower == 'final') {
      return 'Finals';
    }

    // Default: capitalize each word
    return stagePart
        .split(RegExp(r'[-_\s]'))
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join(' ');
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

      // Round-slug derived multi-stage knockout:
      // stage IDs look like "knockout-stage-{tourId}-{stageName}".
      final models =
          state.valueOrNull?.gamesAppBarModels ?? const <GamesAppBarModel>[];
      final roundSlugStageIds =
          tourId == null
              ? const <String>{}
              : models
                  .where(
                    (m) => m.id.startsWith('$kKnockoutStagePrefix-${tourId!}-'),
                  )
                  .map((m) => m.id)
                  .toSet();

      if (roundSlugStageIds.isNotEmpty && tourId != null) {
        final counts = <String, int>{for (final id in roundSlugStageIds) id: 0};
        final games =
            ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels ??
            const <GamesTourModel>[];

        for (final game in games) {
          final gameSlug = (game.roundSlug ?? '').trim().toLowerCase();
          if (gameSlug.isEmpty) continue;
          final stagePart = (gameSlug.contains('--')
                  ? gameSlug.split('--').first
                  : gameSlug)
              .replaceAll(' ', '-');
          final stageId = '$kKnockoutStagePrefix-$tourId-$stagePart';
          if (counts.containsKey(stageId)) {
            counts.update(stageId, (value) => value + 1);
          }
        }

        return counts;
      }

      // Single-stage knockout - all games belong to the aggregated stage
      final games =
          ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels ??
          const <GamesTourModel>[];
      return {'$kKnockoutStagePrefix-${tourId ?? 'stage'}': games.length};
    } else {
      // Regular tournaments - count by actual round ID
      final rawGames =
          tourId == null ? null : ref.read(gamesTourProvider(tourId!)).value;
      if (rawGames != null) {
        final counts = <String, int>{};
        for (final game in rawGames) {
          counts.update(game.roundId, (value) => value + 1, ifAbsent: () => 1);
        }
        return counts;
      }

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
    final aStart = _roundEventDateTime(a);
    final bStart = _roundEventDateTime(b);

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

  DateTime? _roundEventDateTime(GamesAppBarModel model) {
    final meta = _roundSortMeta[model.id];
    return meta?.startsAt ?? model.startsAt ?? meta?.createdAt;
  }

  bool _hasConfiguredStartTime(GamesAppBarModel model) {
    final meta = _roundSortMeta[model.id];
    return meta?.startsAt != null || model.startsAt != null;
  }

  GamesAppBarModel? _selectAutoRound(
    List<GamesAppBarModel> models,
    Map<String, int> counts,
  ) {
    return pickPreferredRoundForSelection(
      models,
      resolveDate: _roundEventDateTime,
      hasGames: (model) => _hasGames(model.id, counts),
    );
  }

  void _sortRounds(List<GamesAppBarModel> models) {
    final sorted = sortRoundsForDisplay(
      models,
      resolveDate: _roundEventDateTime,
    );
    models
      ..clear()
      ..addAll(sorted);
  }

  void _refreshSelectionAfterGamesChange(List<Games> games) {
    if (_selectionRefreshScheduled) return;
    _selectionRefreshScheduled = true;

    Future.microtask(() async {
      _selectionRefreshScheduled = false;
      if (!mounted || tourId == null) return;

      final current = state.valueOrNull;
      if (current == null || current.gamesAppBarModels.isEmpty) return;

      final knownRoundIds =
          current.gamesAppBarModels.map((model) => model.id).toSet();
      final hasNewGameBackedRound = games.any(
        (game) => !knownRoundIds.contains(game.roundId),
      );
      if (hasNewGameBackedRound) {
        await _load(showLoading: false, scrollSelection: false);
      }
    });
  }

  /// Recompute statuses on live-rounds change, update selection only if the user
  /// hasn’t made a sticky pick.
  ///
  /// **Transient-empty guard:** `settings` is in the realtime publication, so
  /// reconnect snapshots and momentary empty re-emits can arrive. Treating
  /// empty-after-non-empty as "no rounds are live" would flip every live
  /// round out and back. Drop empty-after-non-empty unless backend
  /// corroborates emptiness on a subsequent emission.
  /// See docs/superpowers/specs/2026-05-29-realtime-live-games-implementation-plan.md
  /// change #3.
  void _onLiveRoundsChanged(List<String> newLive) {
    if (newLive.isEmpty && _liveRounds.isNotEmpty) {
      return;
    }
    if (setEquals(_liveRounds.toSet(), newLive.toSet())) {
      return;
    }
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
    final nextSelected = selectRoundIdAfterLiveRoundsChanged(
      models: updated,
      currentSelectedId: current.selectedId,
      stickySelection: sticky,
      hasGames: (roundId) => _hasGames(roundId, counts),
      resolveDate: _roundEventDateTime,
    );
    final selectedIsSticky =
        sticky?.userSelected == true &&
        sticky?.id == nextSelected &&
        nextSelected.isNotEmpty;

    state = AsyncValue.data(
      GamesAppBarViewModel(
        gamesAppBarModels: updated,
        selectedId: nextSelected,
        userSelectedId: selectedIsSticky,
      ),
    );
  }

  Future<void> _applySelectionFrom(
    List<GamesAppBarModel> models,
    String tourId, {
    bool scrollSelection = true,
  }) async {
    // 1) Respect sticky user selection if still present
    final sticky = ref.read(userSelectedRoundProvider);
    final stickyId = sticky?.id;
    final counts = _buildRoundGameCounts();
    if (sticky?.userSelected == true &&
        stickyId != null &&
        models.any((m) => m.id == stickyId) &&
        _hasGames(stickyId, counts)) {
      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: models,
          selectedId: stickyId,
          userSelectedId: true,
        ),
      );
      if (scrollSelection) {
        _scrollToRound(stickyId);
      }
      return;
    }

    // 2) Prefer live round first (highest priority for real-time viewing)
    final liveModel = _pickRoundModelByStatus(models, counts, RoundStatus.live);
    if (liveModel != null) {
      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: models,
          selectedId: liveModel.id,
          userSelectedId: false,
        ),
      );
      if (scrollSelection) {
        _scrollToRound(liveModel.id);
      }
      return;
    }

    final allHaveStartTimes = models.every(
      (m) => _roundEventDateTime(m) != null,
    );
    if (allHaveStartTimes) {
      final preconfiguredFocus = pickPreferredRoundForSelection(
        models,
        resolveDate: _roundEventDateTime,
        hasGames: (model) => _hasGames(model.id, counts),
      );
      if (preconfiguredFocus != null) {
        state = AsyncValue.data(
          GamesAppBarViewModel(
            gamesAppBarModels: models,
            selectedId: preconfiguredFocus.id,
            userSelectedId: false,
          ),
        );
        if (scrollSelection) {
          _scrollToRound(preconfiguredFocus.id);
        }
        return;
      }
    }

    // 3) Try to get the latest round by last move activity
    // This ensures consistency with For You tab which also uses latest round
    GamesAppBarModel? latestByActivityModel;
    try {
      final repo = ref.read(roundRepositoryProvider);
      final latest = await repo.getLatestRoundByLastMove(tourId);
      if (latest != null &&
          models.any((m) => m.id == latest.id) &&
          _hasGames(latest.id, counts)) {
        latestByActivityModel = models.firstWhere((m) => m.id == latest.id);
      }
    } catch (e) {}

    // 4) If we have a recent round by activity, prefer it.
    // But don't jump to upcoming rounds while there are started rounds with games.
    final hasStartedRoundsWithGames = models.any(
      (m) => m.roundStatus != RoundStatus.upcoming && _hasGames(m.id, counts),
    );
    if (latestByActivityModel != null) {
      final activityIsUpcoming =
          latestByActivityModel.roundStatus == RoundStatus.upcoming;
      if (activityIsUpcoming && hasStartedRoundsWithGames) {
        latestByActivityModel = null;
      }
    }

    if (latestByActivityModel != null) {
      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: models,
          selectedId: latestByActivityModel.id,
          userSelectedId: false,
        ),
      );
      if (scrollSelection) {
        _scrollToRound(latestByActivityModel.id);
      }
      return;
    }

    // 5) Fall back to auto-select (ongoing → completed → upcoming)
    final autoModel = _selectAutoRound(models, counts);
    final fallbackId = autoModel?.id ?? '';
    state = AsyncValue.data(
      GamesAppBarViewModel(
        gamesAppBarModels: models,
        selectedId: fallbackId,
        userSelectedId: false,
      ),
    );
    if (fallbackId.isNotEmpty) {
      if (scrollSelection) {
        _scrollToRound(fallbackId);
      }
    }
  }
}

@visibleForTesting
String selectRoundIdAfterLiveRoundsChanged({
  required List<GamesAppBarModel> models,
  required String currentSelectedId,
  required ({String id, bool userSelected})? stickySelection,
  required bool Function(String roundId) hasGames,
  required RoundDateResolver resolveDate,
}) {
  final stickyId = stickySelection?.id;
  if (stickySelection?.userSelected == true &&
      stickyId != null &&
      models.any((m) => m.id == stickyId) &&
      hasGames(stickyId)) {
    return stickyId;
  }

  final liveRounds =
      models
          .where((m) => m.roundStatus == RoundStatus.live && hasGames(m.id))
          .toList()
        ..sort((a, b) => _compareResolvedDate(a, b, false, resolveDate));
  if (liveRounds.isNotEmpty) {
    return liveRounds.first.id;
  }

  final currentStillValid =
      currentSelectedId.isNotEmpty &&
      models.any((m) => m.id == currentSelectedId) &&
      hasGames(currentSelectedId);
  if (currentStillValid) {
    return currentSelectedId;
  }

  final autoModel = pickPreferredRoundForSelection(
    models,
    resolveDate: resolveDate,
    hasGames: (model) => hasGames(model.id),
  );
  return autoModel?.id ?? '';
}

int _compareResolvedDate(
  GamesAppBarModel a,
  GamesAppBarModel b,
  bool ascending,
  RoundDateResolver resolveDate,
) {
  final aStart = resolveDate(a);
  final bStart = resolveDate(b);

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

  final lower = value.toLowerCase();

  // Handle special knockout stage names with high numbers for correct sorting
  // Finals should appear first (highest), then Semifinals, then Quarterfinals
  if (lower.contains('final') &&
      !lower.contains('semifinal') &&
      !lower.contains('quarterfinal')) {
    return 300; // Finals - highest priority
  }
  if (lower.contains('semifinal')) {
    return 200; // Semifinals
  }
  if (lower.contains('quarterfinal')) {
    return 100; // Quarterfinals
  }

  // Handle numbered rounds (Round 1, Round 2, etc.)
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

String _roundCountSignature(List<Games> games) {
  if (games.isEmpty) return '';

  final counts = <String, int>{};
  for (final game in games) {
    counts.update(game.roundId, (value) => value + 1, ifAbsent: () => 1);
  }

  final entries =
      counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) => '${entry.key}:${entry.value}').join('|');
}
