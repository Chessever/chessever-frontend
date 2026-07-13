// ignore_for_file: avoid_print, empty_catches, unused_element

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_ordering.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/knockout_stage_parser.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_stage_round_resolver.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart'; // adjust import path if needed
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';

const int kUnknownGameRoundMaxRetries = 5;

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
        if (isVirtualGamebaseId(tourId!)) {
          _load(showLoading: false, scrollSelection: false);
          return;
        }
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
  final Set<String> _checkedUnknownLiveRoundIds = <String>{};
  Timer? _unknownGameRoundsRetryTimer;
  Set<String> _pendingUnknownGameRoundIds = const <String>{};
  int _unknownGameRoundsRetryGeneration = 0;

  Future<void> _maybeReloadForUnknownLiveRounds(
    List<String> liveRoundIds,
  ) async {
    final currentTourId = tourId;
    if (currentTourId == null || isVirtualGamebaseId(currentTourId)) return;

    // _roundSortMeta holds every real round id fetched by _load; ids outside
    // it are either other tours' rounds or rounds added after our last load.
    // Check each id only once — getRoundsByIds resolves which case it is.
    final unknownIds = <String>[];
    for (final id in liveRoundIds) {
      if (_roundSortMeta.containsKey(id)) continue;
      if (_checkedUnknownLiveRoundIds.add(id)) {
        unknownIds.add(id);
      }
    }
    if (unknownIds.isEmpty) return;

    try {
      final rounds = await ref
          .read(roundRepositoryProvider)
          .getRoundsByIds(unknownIds);
      if (!mounted) return;
      final tourDetail = ref.read(tourDetailScreenProvider).valueOrNull;
      final knownTourIds =
          tourDetail?.tours.map((tour) => tour.tour.id) ?? const <String>[];
      final representedTourIds = representedTournamentIdsForDisplayRounds(
        rounds:
            state.valueOrNull?.gamesAppBarModels ?? const <GamesAppBarModel>[],
        selectedTourId: currentTourId,
        knownTourIds: knownTourIds,
      );
      final currentTour =
          tourDetail?.tours
              .where((tour) => tour.tour.id == currentTourId)
              .firstOrNull
              ?.tour;
      if (currentTour != null) {
        representedTourIds.addAll(
          filterKnockoutSiblingTours(
            selectedTour: currentTour,
            siblingTours: tourDetail!.tours.map((tour) => tour.tour),
          ).map((tour) => tour.id),
        );
      }
      if (rounds.any((round) => representedTourIds.contains(round.tourId))) {
        await _load(showLoading: false, scrollSelection: false);
        _invalidateRoundMetadataEvidence();
      }
    } catch (_) {
      // The games safety-net poll (unknown roundId on incoming games) remains
      // the fallback path for surfacing new rounds.
    }
  }

  Future<void> refresh() async {
    await _load();
    _invalidateRoundMetadataEvidence();
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
    final scopeId = resolveGamesTourScrollScope(ref);
    return ref.read(gamesTourScrollProvider(scopeId).notifier).visibleRoundIds;
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
    final roundModels = state.valueOrNull?.gamesAppBarModels ?? const [];
    final knownTourIds =
        ref
            .read(tourDetailScreenProvider)
            .valueOrNull
            ?.tours
            .map((tour) => tour.tour.id) ??
        const <String>[];

    for (final roundId in targetRoundIds) {
      if (!_isKnockoutRound(roundId)) {
        continue;
      }

      List<GamesTourModel> roundGames;
      if (roundId.startsWith('$kKnockoutStagePrefix-')) {
        final round =
            roundModels.where((model) => model.id == roundId).firstOrNull;
        if (round == null || tourId == null) continue;
        roundGames = itemsForTournamentDisplayRound<GamesTourModel>(
          round: round,
          selectedTourId: tourId!,
          knownTourIds: knownTourIds,
          selectedTourItems: allGames,
          sourceRoundIdOf: (game) => game.roundId,
          siblingTourItems:
              (stageTourId) =>
                  ref
                      .read(knockoutTournamentStateProvider(stageTourId))
                      .allGames,
        );
      } else if (roundId.toLowerCase().startsWith('knockout-round-')) {
        roundGames = allGames;
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
    final scopeId = resolveGamesTourScrollScope(ref);
    return ref
        .read(gamesTourScrollProvider(scopeId).notifier)
        .roundHeaderIndex(roundId);
  }

  Future<void> _load({
    bool showLoading = true,
    bool scrollSelection = false,
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
      if (isVirtualGamebaseId(tourId!)) {
        final gamesAsync = ref.read(gamesTourProvider(tourId!));
        final games = gamesAsync.valueOrNull;
        if (gamesAsync.isLoading || games == null) {
          if (showLoading) state = const AsyncValue.loading();
          return;
        }

        _roundSortMeta.clear();
        final models = buildVirtualGamebaseRoundModels(games);
        if (models.isEmpty) {
          state = const AsyncValue.data(
            GamesAppBarViewModel(
              gamesAppBarModels: [],
              selectedId: '',
              userSelectedId: false,
            ),
          );
          return;
        }

        _sortRounds(models);
        await _applySelectionFrom(
          models,
          tourId!,
          scrollSelection: scrollSelection,
        );
        return;
      }

      final repo = ref.read(roundRepositoryProvider);
      final rounds = await repo.getRoundsByTourId(tourId!);

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
      final processedModels = await _processKnockoutRoundsIfNeeded(
        models,
        sourceRounds: rounds,
      );

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
    List<GamesAppBarModel> models, {
    required List<Round> sourceRounds,
  }) async {
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
      var groupTours =
          allTours
              .where((t) => t.tour.groupBroadcastId == groupBroadcastId)
              .toList();

      // One broadcast can contain parallel knockout lanes (for example Men
      // and Women). Reuse the same stage descriptor as the Bracket builder so
      // the Games tab never combines those independent graphs.
      if (currentTour != null) {
        final sameLaneIds =
            filterKnockoutSiblingTours(
              selectedTour: currentTour,
              siblingTours: groupTours.map((model) => model.tour),
            ).map((tour) => tour.id).toSet();
        groupTours =
            groupTours
                .where((model) => sameLaneIds.contains(model.tour.id))
                .toList();
      }

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

          // Check if this tour is knockout format
          final stageKnockoutState = ref.read(
            knockoutTournamentStateProvider(tour.id),
          );

          if (!shouldIncludeNamedKnockoutStageTour(
            tour,
            detectedTeamEvent: stageKnockoutState.isTeamEvent,
          )) {
            print('    ❌ Explicit team/non-knockout stage, skipping');
            continue;
          }

          // Show ALL stages in dropdown, regardless of games (like 'about' tab does)
          final tourStatus = tourModel.roundStatus;
          print(
            '    ✓ Has ${stageRoundModels.length} rounds, ${stageKnockoutState.allGames.length} games, status: $tourStatus',
          );

          // Determine aggregated status for this stage
          RoundStatus stageStatus = tourStatus;
          if (stageRoundModels.any((m) => m.roundStatus == RoundStatus.live)) {
            stageStatus = RoundStatus.live;
          } else if (stageRoundModels.any(
            (m) => m.roundStatus == RoundStatus.ongoing,
          )) {
            stageStatus = RoundStatus.ongoing;
          } else if (stageRoundModels.isNotEmpty &&
              stageRoundModels.every(
                (m) => m.roundStatus == RoundStatus.completed,
              )) {
            stageStatus = RoundStatus.completed;
          } else if (stageRoundModels.isNotEmpty &&
              stageRoundModels.every(
                (m) => m.roundStatus == RoundStatus.upcoming,
              )) {
            stageStatus = RoundStatus.upcoming;
          }

          // Use the freshest date available to describe this stage (round or tour level)
          final stageStartsAt = _resolveStageStartDate(
            tour: tour,
            stageRoundModels: stageRoundModels,
          );

          // Show only the logical stage name. Parallel lane labels (Men,
          // Women, Open) belong to the category selector, not every round row.
          final stageName =
              parseKnockoutTourStageDescriptor(tour.name).stage?.label ??
              (tour.name.contains('|')
                  ? tour.name.split('|').last.trim()
                  : tour.name);

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
              sourceRoundIds:
                  stageRoundModels.map((round) => round.id).toList(),
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

    // No sibling stage was discoverable and this tour has no published
    // rounds. A genuinely empty single-tour knockout has no Games-tab row yet.
    if (models.isEmpty && sourceRounds.isEmpty) {
      return const <GamesAppBarModel>[];
    }

    // Single-tour knockout: derive logical stages from every published source
    // round, not only rounds that already have games. This keeps scheduled
    // future stages visible and lets one resolved stage retain its precise
    // label (for example Round 3.1 + Round 3.2 -> Round 3).
    final allGames = knockoutState.allGames;
    final logicalStageGroups = groupSingleTourKnockoutSourceRounds(
      sourceRounds: sourceRounds,
      roundModels: models,
      gameRoundIds: allGames.map((game) => game.roundId),
      tourName: currentTour?.name,
    );

    if (logicalStageGroups.isNotEmpty) {
      print(
        '📋 Extracted ${logicalStageGroups.length} logical knockout stages: '
        '${logicalStageGroups.map((group) => group.stage.label).toList()}',
      );
      final stageModels = <GamesAppBarModel>[];

      for (final group in logicalStageGroups) {
        final stage = group.stage;
        final stageName = stage.label;
        final stageRounds = group.roundModels;
        final stageStatus = _aggregateRoundStatus(stageRounds);
        final stageStartsAt = _latestDate(
          stageRounds.map((round) => round.startsAt),
        );
        final stageCreatedAt =
            _latestDate(group.sourceRounds.map((round) => round.createdAt)) ??
            DateTime.now();
        final stageId =
            '$kKnockoutStagePrefix-${tourId ?? 'stage'}-${stage.key}';

        _roundSortMeta[stageId] = _RoundSortMeta(
          slug: stage.key,
          createdAt: stageCreatedAt,
          startsAt: stageStartsAt,
          roundNumber: _parseRoundNumber(stageName),
          gameNumber: null,
        );

        print(
          '    ✅ Stage "$stageName": ${stageRounds.length} rounds, '
          '${group.gameRoundIds.length} published game rounds, '
          'status: $stageStatus',
        );

        stageModels.add(
          GamesAppBarModel(
            id: stageId,
            name: stageName,
            startsAt: stageStartsAt,
            roundStatus: stageStatus,
            sourceRoundIds: group.sourceRounds
                .map((round) => round.id)
                .toList(growable: false),
          ),
        );
      }

      return stageModels;
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
      sourceRoundIds:
          models.expand((round) => round.sourceRoundIds).toSet().toList(),
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

  Map<String, int> _buildRoundGameCounts([
    List<GamesAppBarModel>? loadedModels,
  ]) {
    final isKnockout =
        tourId != null
            ? ref.read(knockoutTournamentStateProvider(tourId!)).isKnockout
            : false;

    if (isKnockout) {
      final models =
          loadedModels ??
          state.valueOrNull?.gamesAppBarModels ??
          const <GamesAppBarModel>[];
      final games =
          ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels ??
          const <GamesTourModel>[];
      final knownTourIds =
          ref
              .read(tourDetailScreenProvider)
              .valueOrNull
              ?.tours
              .map((tour) => tour.tour.id) ??
          const <String>[];
      return <String, int>{
        for (final model in models)
          model.id:
              itemsForTournamentDisplayRound<GamesTourModel>(
                round: model,
                selectedTourId: tourId!,
                knownTourIds: knownTourIds,
                selectedTourItems: games,
                sourceRoundIdOf: (game) => game.roundId,
                siblingTourItems:
                    (stageTourId) =>
                        ref
                            .read(knockoutTournamentStateProvider(stageTourId))
                            .allGames,
              ).length,
      };
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

  Map<String, bool> _buildRoundCompletion(List<GamesAppBarModel> loadedModels) {
    final isKnockout =
        tourId != null
            ? ref.read(knockoutTournamentStateProvider(tourId!)).isKnockout
            : false;

    if (isKnockout && tourId != null) {
      final games =
          ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels ??
          const <GamesTourModel>[];
      final knownTourIds =
          ref
              .read(tourDetailScreenProvider)
              .valueOrNull
              ?.tours
              .map((tour) => tour.tour.id) ??
          const <String>[];
      return <String, bool>{
        for (final model in loadedModels)
          model.id: () {
            final roundGames = itemsForTournamentDisplayRound<GamesTourModel>(
              round: model,
              selectedTourId: tourId!,
              knownTourIds: knownTourIds,
              selectedTourItems: games,
              sourceRoundIdOf: (game) => game.roundId,
              siblingTourItems:
                  (stageTourId) =>
                      ref
                          .read(knockoutTournamentStateProvider(stageTourId))
                          .allGames,
            );
            return roundGames.isNotEmpty &&
                roundGames.every((game) => game.gameStatus.isFinished);
          }(),
      };
    }

    final rawGames =
        tourId == null
            ? null
            : ref.read(gamesTourProvider(tourId!)).valueOrNull;
    if (rawGames != null) {
      return <String, bool>{
        for (final model in loadedModels)
          model.id: () {
            final roundGames = rawGames.where(
              (game) => model.sourceRoundIds.contains(game.roundId),
            );
            return roundGames.isNotEmpty &&
                roundGames.every(
                  (game) => GameStatus.fromString(game.status).isFinished,
                );
          }(),
      };
    }

    final games =
        ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels ??
        const <GamesTourModel>[];
    return <String, bool>{
      for (final model in loadedModels)
        model.id: () {
          final roundGames = games.where(
            (game) => model.sourceRoundIds.contains(game.roundId),
          );
          return roundGames.isNotEmpty &&
              roundGames.every((game) => game.gameStatus.isFinished);
        }(),
    };
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
    final completion = _buildRoundCompletion(models);
    return pickPreferredRoundForSelection(
      models,
      resolveDate: _roundEventDateTime,
      hasGames: (model) => _hasGames(model.id, counts),
      isRoundFullyPlayed: (model) => completion[model.id] ?? false,
    );
  }

  void _sortRounds(List<GamesAppBarModel> models) {
    final counts = _buildRoundGameCounts(models);
    final completion = _buildRoundCompletion(models);
    final sorted = sortRoundsForDisplay(
      models,
      resolveDate: _roundEventDateTime,
      hasGames: (model) => _hasGames(model.id, counts),
      isRoundFullyPlayed: (model) => completion[model.id] ?? false,
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
      final unknownRoundIds = unknownGameRoundIds(
        gameRoundIds: games.map((game) => game.roundId),
        displayRounds: current?.gamesAppBarModels ?? const <GamesAppBarModel>[],
      );
      if (unknownRoundIds.isNotEmpty) {
        _startUnknownGameRoundReloads(unknownRoundIds);
      }

      if (current == null) return;
      final reordered = List<GamesAppBarModel>.from(current.gamesAppBarModels);
      _sortRounds(reordered);
      final sticky = ref.read(userSelectedRoundProvider);
      final stickyId = sticky?.id;
      final counts = _buildRoundGameCounts(reordered);
      final autoSelected = _selectAutoRound(reordered, counts);
      final stickyIsValid =
          sticky?.userSelected == true &&
          stickyId != null &&
          reordered.any((round) => round.id == stickyId) &&
          _hasGames(stickyId, counts);
      final nextSelectedId =
          stickyIsValid ? stickyId : autoSelected?.id ?? current.selectedId;
      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: reordered,
          selectedId: nextSelectedId,
          userSelectedId: stickyIsValid,
        ),
      );
    });
  }

  void _startUnknownGameRoundReloads(Set<String> unknownRoundIds) {
    if (setEquals(_pendingUnknownGameRoundIds, unknownRoundIds) &&
        _unknownGameRoundsRetryTimer?.isActive == true) {
      return;
    }
    _pendingUnknownGameRoundIds = Set<String>.unmodifiable(unknownRoundIds);
    _unknownGameRoundsRetryTimer?.cancel();
    final generation = ++_unknownGameRoundsRetryGeneration;
    unawaited(_reloadUnknownGameRounds(generation, 0));
  }

  Future<void> _reloadUnknownGameRounds(int generation, int attempt) async {
    if (!mounted || generation != _unknownGameRoundsRetryGeneration) return;
    await _load(showLoading: false, scrollSelection: false);
    if (!mounted || generation != _unknownGameRoundsRetryGeneration) return;

    final remaining = unknownGameRoundIds(
      gameRoundIds: _pendingUnknownGameRoundIds,
      displayRounds:
          state.valueOrNull?.gamesAppBarModels ?? const <GamesAppBarModel>[],
    );
    if (remaining.isEmpty || attempt >= kUnknownGameRoundMaxRetries) {
      if (remaining.isEmpty) {
        _invalidateRoundMetadataEvidence();
      }
      _pendingUnknownGameRoundIds = const <String>{};
      _unknownGameRoundsRetryTimer = null;
      return;
    }

    _pendingUnknownGameRoundIds = Set<String>.unmodifiable(remaining);
    _unknownGameRoundsRetryTimer = Timer(
      unknownGameRoundRetryDelay(attempt),
      () => unawaited(_reloadUnknownGameRounds(generation, attempt + 1)),
    );
  }

  void _invalidateRoundMetadataEvidence() {
    final currentTourId = tourId;
    if (currentTourId == null || currentTourId.isEmpty) return;
    final request = resolveKnockoutRoundMetadataRequest(
      tourDetail: ref.read(tourDetailScreenProvider).valueOrNull,
      tourId: currentTourId,
    );
    ref.invalidate(knockoutRoundMetadataEvidenceProvider(request));
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

    // A live round we've never fetched may be a round that was created after
    // this notifier loaded (its games may not exist yet, so the games-change
    // listener can't catch it either). Check whether it belongs to this tour
    // and reload the round list if so.
    unawaited(_maybeReloadForUnknownLiveRounds(newLive));

    final current = state.valueOrNull;
    if (current == null) return;

    final updated =
        current.gamesAppBarModels
            .map(
              (m) => GamesAppBarModel(
                id: m.id,
                name: m.name,
                startsAt: m.startsAt,
                roundStatus: roundStatusForLiveSourceRounds(
                  model: m,
                  liveRoundIds: _liveRounds,
                ),
                sourceRoundIds: m.sourceRoundIds,
              ),
            )
            .toList();

    _sortRounds(updated);

    final sticky = ref.read(userSelectedRoundProvider);
    final counts = _buildRoundGameCounts(updated);
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
    final counts = _buildRoundGameCounts(models);
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
      final completion = _buildRoundCompletion(models);
      final preconfiguredFocus = pickPreferredRoundForSelection(
        models,
        resolveDate: _roundEventDateTime,
        hasGames: (model) => _hasGames(model.id, counts),
        isRoundFullyPlayed: (model) => completion[model.id] ?? false,
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

  @override
  void dispose() {
    _unknownGameRoundsRetryTimer?.cancel();
    _unknownGameRoundsRetryGeneration++;
    super.dispose();
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

@visibleForTesting
class SingleTourKnockoutStageGroup {
  const SingleTourKnockoutStageGroup({
    required this.stage,
    required this.sourceRounds,
    required this.roundModels,
    required this.gameRoundIds,
  });

  final LogicalKnockoutStage stage;
  final List<Round> sourceRounds;
  final List<GamesAppBarModel> roundModels;

  /// Source round IDs that currently contain at least one published game.
  final Set<String> gameRoundIds;

  bool get hasGames => gameRoundIds.isNotEmpty;
}

@visibleForTesting
bool shouldIncludeNamedKnockoutStageTour(
  Tour tour, {
  required bool detectedTeamEvent,
}) {
  final format = tour.info.format;
  final lowerFormat = (format ?? '').toLowerCase();
  if (detectedTeamEvent ||
      lowerFormat.contains('team') ||
      formatRulesOutKnockout(format)) {
    return false;
  }
  return parseKnockoutTourStageDescriptor(tour.name).stage != null;
}

@visibleForTesting
RoundStatus roundStatusForLiveSourceRounds({
  required GamesAppBarModel model,
  required Iterable<String> liveRoundIds,
}) {
  final liveIds = liveRoundIds.toSet();
  if (model.sourceRoundIds.any(liveIds.contains)) {
    return RoundStatus.live;
  }
  return GamesAppBarModel.status(
    currentId: model.id,
    startsAt: model.startsAt,
    liveRound: liveIds.toList(growable: false),
  );
}

/// Groups every published source round into a logical knockout stage.
///
/// Games are deliberately metadata only: they report which stages have
/// content but never decide whether a published stage exists. This prevents a
/// scheduled empty stage from disappearing and preserves a sole trustworthy
/// stage descriptor instead of falling back to the detector's coarse label.
@visibleForTesting
List<SingleTourKnockoutStageGroup> groupSingleTourKnockoutSourceRounds({
  required List<Round> sourceRounds,
  required List<GamesAppBarModel> roundModels,
  required Iterable<String> gameRoundIds,
  String? tourName,
}) {
  final modelByRoundId = <String, GamesAppBarModel>{
    for (final model in roundModels) model.id: model,
  };
  final publishedGameRoundIds = gameRoundIds.toSet();
  final stages = <String, LogicalKnockoutStage>{};
  final roundsByStage = <String, List<Round>>{};
  final modelsByStage = <String, List<GamesAppBarModel>>{};
  final unresolvedRounds = <Round>[];
  final unresolvedModels = <GamesAppBarModel>[];

  for (final round in sourceRounds) {
    final model = modelByRoundId[round.id];
    if (model == null) continue;
    final stage = resolveLogicalKnockoutStage(
      round.name,
      round.slug,
      tourName: tourName,
    );
    if (stage == null) {
      unresolvedRounds.add(round);
      unresolvedModels.add(model);
      continue;
    }

    stages[stage.key] = stage;
    final stageRounds = roundsByStage.putIfAbsent(stage.key, () => <Round>[]);
    if (!stageRounds.any((existing) => existing.id == round.id)) {
      stageRounds.add(round);
      modelsByStage
          .putIfAbsent(stage.key, () => <GamesAppBarModel>[])
          .add(model);
    }
  }

  if (stages.length == 1 && unresolvedRounds.isNotEmpty) {
    final soleKey = stages.keys.single;
    roundsByStage[soleKey]!.addAll(unresolvedRounds);
    modelsByStage[soleKey]!.addAll(unresolvedModels);
  } else if (stages.length > 1 && unresolvedRounds.isNotEmpty) {
    const fallback = LogicalKnockoutStage(
      key: 'other-pairings',
      label: 'Other pairings',
      sortOrder: 6500,
    );
    stages[fallback.key] = fallback;
    roundsByStage[fallback.key] = unresolvedRounds;
    modelsByStage[fallback.key] = unresolvedModels;
  }

  final keys =
      stages.keys.toList()..sort((left, right) {
        final semantic = stages[left]!.sortOrder.compareTo(
          stages[right]!.sortOrder,
        );
        if (semantic != 0) return semantic;
        final leftDate = roundsByStage[left]!.first.createdAt;
        final rightDate = roundsByStage[right]!.first.createdAt;
        return leftDate.compareTo(rightDate);
      });

  return List<SingleTourKnockoutStageGroup>.unmodifiable(
    keys.map((key) {
      final stageRounds = List<Round>.unmodifiable(roundsByStage[key]!);
      return SingleTourKnockoutStageGroup(
        stage: stages[key]!,
        sourceRounds: stageRounds,
        roundModels: List<GamesAppBarModel>.unmodifiable(modelsByStage[key]!),
        gameRoundIds: Set<String>.unmodifiable(
          stageRounds
              .map((round) => round.id)
              .where(publishedGameRoundIds.contains),
        ),
      );
    }),
  );
}

@visibleForTesting
Set<String> unknownGameRoundIds({
  required Iterable<String> gameRoundIds,
  required Iterable<GamesAppBarModel> displayRounds,
}) {
  final knownRoundIds =
      displayRounds
          .expand((model) => <String>[model.id, ...model.sourceRoundIds])
          .toSet();
  return gameRoundIds.where((id) => !knownRoundIds.contains(id)).toSet();
}

@visibleForTesting
Duration unknownGameRoundRetryDelay(int attempt) {
  final boundedAttempt = attempt.clamp(0, kUnknownGameRoundMaxRetries - 1);
  return Duration(milliseconds: 250 * (1 << boundedAttempt));
}

RoundStatus _aggregateRoundStatus(List<GamesAppBarModel> rounds) {
  if (rounds.any((round) => round.roundStatus == RoundStatus.live)) {
    return RoundStatus.live;
  }
  if (rounds.any((round) => round.roundStatus == RoundStatus.ongoing)) {
    return RoundStatus.ongoing;
  }
  if (rounds.every((round) => round.roundStatus == RoundStatus.completed)) {
    return RoundStatus.completed;
  }
  if (rounds.every((round) => round.roundStatus == RoundStatus.upcoming)) {
    return RoundStatus.upcoming;
  }
  return RoundStatus.ongoing;
}

DateTime? _latestDate(Iterable<DateTime?> dates) {
  DateTime? latest;
  for (final date in dates) {
    if (date != null && (latest == null || date.isAfter(latest))) {
      latest = date;
    }
  }
  return latest;
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

  final statuses = <String, List<String>>{};
  for (final game in games) {
    statuses
        .putIfAbsent(game.roundId, () => <String>[])
        .add((game.status ?? '').trim());
  }

  final entries =
      statuses.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  return entries
      .map((entry) {
        entry.value.sort();
        return '${entry.key}:${entry.value.join(',')}';
      })
      .join('|');
}

List<GamesAppBarModel> buildVirtualGamebaseRoundModels(List<Games> games) {
  if (games.isEmpty) return const <GamesAppBarModel>[];

  final roundsById = <String, List<Games>>{};
  for (final game in games) {
    roundsById.putIfAbsent(game.roundId, () => <Games>[]).add(game);
  }

  var fallbackRoundNumber = 0;
  return roundsById.entries.map((entry) {
    fallbackRoundNumber++;
    final roundGames = entry.value;
    final firstGame = roundGames.first;
    final startsAt = _earliestGameDate(roundGames);
    final hasOngoingGame = roundGames.any(
      (game) => (game.status ?? '').trim() == '*',
    );
    return GamesAppBarModel(
      id: entry.key,
      name:
          firstGame.roundSlug.trim().isNotEmpty
              ? firstGame.roundSlug.trim()
              : 'Round $fallbackRoundNumber',
      startsAt: startsAt,
      roundStatus: hasOngoingGame ? RoundStatus.ongoing : RoundStatus.completed,
      sourceRoundIds: <String>[entry.key],
    );
  }).toList();
}

DateTime? _earliestGameDate(List<Games> games) {
  DateTime? earliest;
  for (final game in games) {
    final date = game.gameDay ?? game.dateStart ?? game.lastMoveTime;
    if (date == null) continue;
    if (earliest == null || date.isBefore(earliest)) {
      earliest = date;
    }
  }
  return earliest;
}
