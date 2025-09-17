import 'package:flutter/foundation.dart';
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
    _liveRoundsSub = ref.listen<List<String>?>(
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

  String? _cachedForTour;
  List<GamesAppBarModel>? _cachedModels;

  late final ProviderSubscription<List<String>?> _liveRoundsSub;
  ProviderSubscription<String?>? _tourSub;

  Future<void> refresh() async {
    _invalidateCache();
    await _load();
  }

  void select(GamesAppBarModel model) {
    ref.read(userSelectedRoundProvider.notifier).state = (
      id: model.id,
      userSelected: true,
    );

    final current = state.valueOrNull;
    if (current == null) return;

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

  @override
  void dispose() {
    _invalidateCache();
    _liveRoundsSub.close();
    _tourSub?.close();
    super.dispose();
  }

  void _invalidateCache() {
    _cachedForTour = null;
    _cachedModels = null;
  }

  Future<void> _load() async {
    if (tourId == null) {
      state = const AsyncValue.loading();
      return;
    }

    // Serve from cache if valid
    if (_cachedModels != null && _cachedForTour == tourId) {
      await _applySelectionFrom(_cachedModels!, tourId!);
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

      _cachedModels = models;
      _cachedForTour = tourId;

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
      return;
    }

    // Prefer a live round if selection wasn’t user-chosen
    final live = updated.firstWhere(
      (m) => m.roundStatus == RoundStatus.live,
      orElse:
          () =>
              updated.isNotEmpty
                  ? updated.last
                  : const GamesAppBarModel(
                    id: '',
                    name: '',
                    startsAt: null,
                    roundStatus: RoundStatus.upcoming,
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
        return;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('getLatestRoundByLastMove failed: $e');
    }

    // 4) Fallback to newest (last item)
    final fallback = models.isNotEmpty ? models.last.id : '';
    state = AsyncValue.data(
      GamesAppBarViewModel(
        gamesAppBarModels: models,
        selectedId: fallback,
        userSelectedId: false,
      ),
    );
  }
}
