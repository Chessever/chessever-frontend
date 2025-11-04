import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:flutter/animation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart'; // adjust import path if needed
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

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

  int _calculateRoundHeaderIndex(String roundId) {
    final vm = state.valueOrNull;
    final allRounds = vm?.gamesAppBarModels ?? [];
    final selectedId = vm?.selectedId;
    final userSelected = vm?.userSelectedId ?? false;

    // NOTE: For knockout tournaments, the dropdown and scroll behavior needs special handling
    // Knockout tournaments render ALL games grouped by matches (player pairs) in one section,
    // not split by database rounds. This makes round-based scrolling less meaningful.
    // TODO: Consider hiding/adapting the dropdown for knockout tournaments

    // Smart filtering: Match the logic in games_tour_content_body.dart
    final gamesByRound = <String, int>{};
    for (final round in allRounds) {
      final gamesInRound =
          ref
              .read(gamesTourScreenProvider)
              .valueOrNull
              ?.gamesTourModels
              .where((g) => g.roundId == round.id)
              .length ??
          0;
      gamesByRound[round.id] = gamesInRound;
    }

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
        // For regular events, count games
        final gamesInRound =
            ref
                .read(gamesTourScreenProvider)
                .valueOrNull
                ?.gamesTourModels
                .where((g) => g.roundId == round.id)
                .length ??
            0;

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
  Future<List<GamesAppBarModel>> _processKnockoutRoundsIfNeeded(
    List<GamesAppBarModel> models,
  ) async {
    if (models.isEmpty) return models;

    // Get all games to check if this is a knockout tournament
    final allGames =
        ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels ?? [];

    if (allGames.isEmpty) return models;

    // Check if this is a knockout tournament
    final isKnockoutTournament = KnockoutMatchDetector.isKnockoutMatchFormat(allGames);

    if (!isKnockoutTournament) return models;

    // For knockout tournaments, group all sub-rounds into one logical "Round 1"
    // All current games are part of Round 1 (game-1, game-2, tiebreaks, etc.)

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

    // Create a single logical round
    final logicalRound = GamesAppBarModel(
      id: 'knockout-round-1',
      name: 'Round 1',
      startsAt: startsAt,
      roundStatus: roundStatus,
    );

    return [logicalRound];
  }

  Map<String, int> _buildRoundGameCounts() {
    final games =
        ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels ??
        const <GamesTourModel>[];

    if (games.isEmpty) return {};

    // Check if this is a knockout tournament
    final isKnockoutTournament = KnockoutMatchDetector.isKnockoutMatchFormat(games);

    final counts = <String, int>{};

    if (isKnockoutTournament) {
      // For knockout tournaments, all games belong to the logical 'knockout-round-1'
      counts['knockout-round-1'] = games.length;
    } else {
      // For regular tournaments, count by actual round ID
      for (final game in games) {
        counts.update(game.roundId, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    return counts;
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
    // Check if we should show next upcoming round at top
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
    final aPriority = _statusPriorityMap[a.roundStatus] ?? _defaultStatusRank;
    final bPriority = _statusPriorityMap[b.roundStatus] ?? _defaultStatusRank;

    if (aPriority != bPriority) {
      return aPriority.compareTo(bPriority);
    }

    final aMeta = _roundSortMeta[a.id];
    final bMeta = _roundSortMeta[b.id];

    final aRoundNum = aMeta?.roundNumber ?? _extractRoundNumber(a.name);
    final bRoundNum = bMeta?.roundNumber ?? _extractRoundNumber(b.name);
    final roundCompare = _compareIntsDesc(aRoundNum, bRoundNum);
    if (roundCompare != 0) return roundCompare;

    final aGameNum = aMeta?.gameNumber ?? _extractGameNumber(a.name);
    final bGameNum = bMeta?.gameNumber ?? _extractGameNumber(b.name);
    final gameCompare = _compareIntsDesc(aGameNum, bGameNum);
    if (gameCompare != 0) return gameCompare;

    final aStarts = aMeta?.startsAt ?? a.startsAt;
    final bStarts = bMeta?.startsAt ?? b.startsAt;
    final startCompare = _compareDatesDesc(aStarts, bStarts);
    if (startCompare != 0) return startCompare;

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
