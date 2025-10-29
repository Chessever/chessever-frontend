import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:flutter/animation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart'; // adjust import path if needed

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
      scrollProvider.startProgrammaticScroll();
      
      // Small delay to ensure layout is ready
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (controller.isAttached) {
        try {
          // Use alignment 0.0 to position round header at the very top
          controller.jumpTo(
            index: itemIndex,
            alignment: 0.0,
          );
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

    final hasLiveOrOngoing = allRounds.any((r) =>
      r.roundStatus == RoundStatus.live || r.roundStatus == RoundStatus.ongoing
    );

    final hasCompleted = allRounds.any((r) => r.roundStatus == RoundStatus.completed);

    final allAreUpcoming = allRounds.every((r) =>
      r.roundStatus == RoundStatus.upcoming || (gamesByRound[r.id] ?? 0) == 0
    );

    final rounds = allRounds.where((round) {
      final gamesInRound = gamesByRound[round.id] ?? 0;
      if (gamesInRound == 0) return false;

      if (userSelected && selectedId == round.id) return true;

      if (allAreUpcoming) return true;

      if (hasLiveOrOngoing) {
        return round.roundStatus != RoundStatus.upcoming;
      }

      if (hasCompleted && round.roundStatus == RoundStatus.upcoming) {
        final upcomingRounds = allRounds.where((r) =>
          r.roundStatus == RoundStatus.upcoming && (gamesByRound[r.id] ?? 0) > 0
        ).toList();
        return upcomingRounds.isNotEmpty && upcomingRounds.first.id == round.id;
      }

      return round.roundStatus != RoundStatus.upcoming;
    }).toList();

    // Check if we're in group event mode
    final screenMode = ref.read(gamesTourScreenModeProvider).valueOrNull;
    final isGroupEvent = screenMode == GamesTourScreenMode.groupEvent;
    final viewMode = ref.read(gamesListViewModeProvider);
    final bool isGrid = viewMode == GamesListViewMode.chessBoardGrid;

    print('📊 Index calculation - Target: $roundId, Mode: ${isGroupEvent ? "Group" : "Regular"}, Grid: $isGrid');

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
          final grouped = ref.read(gamesTourContentProvider).getGroupHeader(
                selectedRoundId: round.id,
                gamesScreenModel: gamesData,
              );
          final cardCount = grouped.keys.length;
          itemCount += cardCount; // number of team matchup cards
          print('   Round "${round.name}": 1 header + $cardCount cards = $itemCount items');
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
          print('   Round "${round.name}": 1 header + $rows rows ($gamesInRound games) = $itemCount items');
        } else {
          // list: one item per game
          itemCount += gamesInRound;
          print('   Round "${round.name}": 1 header + $gamesInRound games = $itemCount items');
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
            (round) => MapEntry(
              round.id,
              _RoundSortMeta.fromRound(round),
            ),
          ),
        );

      final models =
          rounds
              .map((r) => GamesAppBarModel.fromRound(r, _liveRounds))
              .toList();

      _sortRounds(models);

      await _applySelectionFrom(models, tourId!);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _sortRounds(List<GamesAppBarModel> models) {
    // Check if we should show next upcoming round at top
    final hasLiveOrOngoing = models.any((m) =>
      m.roundStatus == RoundStatus.live || m.roundStatus == RoundStatus.ongoing
    );
    final hasCompleted = models.any((m) => m.roundStatus == RoundStatus.completed);
    final showNextUpcomingFirst = !hasLiveOrOngoing && hasCompleted;

    models.sort((a, b) {
      // Special case: When showing next upcoming round with completed rounds,
      // put upcoming first (top-most)
      if (showNextUpcomingFirst) {
        if (a.roundStatus == RoundStatus.upcoming && b.roundStatus != RoundStatus.upcoming) {
          return -1; // Upcoming comes first
        }
        if (b.roundStatus == RoundStatus.upcoming && a.roundStatus != RoundStatus.upcoming) {
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

    final createdCompare =
        _compareDatesDesc(aMeta?.createdAt, bMeta?.createdAt);
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
    final hasStickyValid =
        sticky?.userSelected == true && updated.any((m) => m.id == sticky!.id);

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

    // Prefer a live round if selection wasn’t user-chosen
    final live = updated.firstWhere(
      (m) => m.roundStatus == RoundStatus.live,
      orElse:
          () => GamesAppBarModel(
            id: '',
            name: '',
            startsAt: null,
            roundStatus: RoundStatus.completed,
          ),
    );

    final nextSelected = (live.id.isNotEmpty ? live.id : current.selectedId);

    state = AsyncValue.data(
      GamesAppBarViewModel(
        gamesAppBarModels: updated,
        selectedId: nextSelected,
        userSelectedId: false,
      ),
    );
    _scrollToRound(nextSelected);
  }

  Future<void> _applySelectionFrom(
    List<GamesAppBarModel> models,
    String tourId,
  ) async {
    // 1) Respect sticky user selection if still present
    final sticky = ref.read(userSelectedRoundProvider);
    if (sticky?.userSelected == true && models.any((m) => m.id == sticky!.id)) {
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
    final live = models.firstWhere(
      (m) => m.roundStatus == RoundStatus.live,
      orElse:
          () =>
              models.isNotEmpty
                  ? models.last
                  : const GamesAppBarModel(
                    id: '',
                    name: '',
                    startsAt: null,
                    roundStatus: RoundStatus.upcoming,
                  ),
    );
    if (live.id.isNotEmpty && live.roundStatus == RoundStatus.live) {
      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: models,
          selectedId: live.id,
          userSelectedId: false,
        ),
      );
      _scrollToRound(live.id);
      return;
    }

    // 3) Try latest-by-last-move (single repo call, only if needed)
    try {
      final repo = ref.read(roundRepositoryProvider);
      final latest = await repo.getLatestRoundByLastMove(tourId);
      if (latest != null && models.any((m) => m.id == latest.id)) {
        state = AsyncValue.data(
          GamesAppBarViewModel(
            gamesAppBarModels: models,
            selectedId: latest.id,
            userSelectedId: false,
          ),
        );
        _scrollToRound(latest.id);
        return;
      }
    } catch (e) {}

    // Highest priority: live
    GamesAppBarModel? selectedModel;
    for (var a = 0; a < models.length; a++) {
      if (models[a].roundStatus == RoundStatus.live) {
        selectedModel = models[a];
        break;
      }
    }

    for (var b = 0; b < models.length; b++) {
      if (models[b].roundStatus == RoundStatus.ongoing) {
        selectedModel = models[b];
        break;
      }
    }

    // Third priority: completed (if no live or ongoing)

    for (var c = 0; c < models.length; c++) {
      if (models[c].roundStatus == RoundStatus.completed) {
        selectedModel ??= models[c];
        break;
      }
    }

    // Final fallback: last item
    final fallbackId =
        selectedModel?.id ?? (models.isNotEmpty ? models.last.id : '');
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
      gameNumber:
          _parseGameNumber(round.name) ?? _parseGameNumber(round.slug),
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
  final match =
      RegExp(
        r'(?:game|board|match)[\s_\-:]*?(\d+)',
        caseSensitive: false,
      ).firstMatch(value);
  return match != null ? int.tryParse(match.group(1)!) : null;
}
