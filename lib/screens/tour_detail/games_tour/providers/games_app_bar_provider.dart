import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
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
    final controller = ref.read(gamesTourScrollProvider);
    final itemIndex = _calculateRoundHeaderIndex(roundId);
    if (itemIndex >= 0) {
      if (controller.isAttached) {
        controller.jumpTo(index: itemIndex, alignment: 0.02);
      }
    }
  }

  int _calculateRoundHeaderIndex(String roundId) {
    final allRounds = state.valueOrNull?.gamesAppBarModels ?? [];

    final rounds =
        allRounds.where((round) {
          final gamesInRound =
              ref
                  .read(gamesTourScreenProvider)
                  .valueOrNull
                  ?.gamesTourModels
                  .where((g) => g.roundId == round.id)
                  .length ??
              0;
          return gamesInRound > 0;
        }).toList();

    final viewMode = ref.read(gamesListViewModeProvider);
    final bool isGrid = viewMode == GamesListViewMode.chessBoardGrid;

    int index = 0;

    for (final round in rounds) {
      // If this is the round we want to scroll to, return the index of its header.
      if (round.id == roundId) {
        return index;
      }

      // count games in this round
      final gamesInRound =
          ref
              .read(gamesTourScreenProvider)
              .valueOrNull
              ?.gamesTourModels
              .where((g) => g.roundId == round.id)
              .length ??
          0;

      if (isGrid) {
        // grid: 1 header + ceil(games/2) rows (each row holds up to 2 games)
        final rows = (gamesInRound + 1) ~/ 2; // integer ceil
        index += 1 + rows;
      } else {
        // list: 1 header + gamesInRound items
        index += 1 + gamesInRound;
      }
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

      final models =
          rounds
              .map((r) => GamesAppBarModel.fromRound(r, _liveRounds))
              .toList();

      models.sort((a, b) {
        final aDate = a.startsAt;
        final bDate = b.startsAt;

        // --- Null handling ---
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1; // nulls go last
        if (bDate == null) return -1;

        // --- Sort by date descending (latest first) ---
        return bDate.compareTo(aDate);
      });

      await _applySelectionFrom(models, tourId!);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
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
