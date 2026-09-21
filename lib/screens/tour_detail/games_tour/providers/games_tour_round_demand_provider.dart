import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import '../models/games_app_bar_view_model.dart';
import 'games_app_bar_provider.dart';
import 'games_tour_provider.dart';
import 'games_tour_screen_provider.dart';
import 'knockout_stage_round_resolver.dart';
import 'round_expansion_provider.dart';

/// Only genuinely visible list items are reported here, excluding scroll cache.
final visibleTournamentRoundsProvider = StateProvider.autoDispose
    .family<Set<String>, String>((ref, tourId) => const {});

/// Translate visible or explicitly expanded sections into real round requests.
/// Scroll-cache items and unopened sibling categories do not request rosters.
Map<String, Set<String>> expandedTournamentRoundDemand({
  required String selectedTourId,
  required Iterable<String> knownTourIds,
  required List<GamesAppBarModel> rounds,
  required Map<String, bool> expansion,
  Set<String> visibleRoundIds = const {},
}) {
  final demand = <String, Set<String>>{selectedTourId: {}};
  for (final round in rounds) {
    if (expansion[round.id] != true && !visibleRoundIds.contains(round.id)) {
      continue;
    }
    final stage = resolveKnockoutStageRoundReference(
      round: round,
      selectedTourId: selectedTourId,
      knownTourIds: knownTourIds,
    );
    final owner = stage?.siblingTourId ?? selectedTourId;
    demand
        .putIfAbsent(owner, () => {})
        .addAll(
          round.sourceRoundIds.isNotEmpty
              ? round.sourceRoundIds
              : stage == null
              ? [round.id]
              : const <String>[],
        );
  }
  return demand;
}

final gamesTourRoundDemandProvider =
    Provider.autoDispose<Map<String, Set<String>>>((ref) {
      final detail = ref.watch(tourDetailScreenProvider).valueOrNull;
      final rounds = ref.watch(gamesAppBarProvider).valueOrNull;
      final expansion = ref.watch(roundExpansionProvider);
      if (detail == null || rounds == null) return const {};
      final isSearchMode = ref.watch(
        gamesTourScreenProvider.select(
          (value) => value.valueOrNull?.isSearchMode ?? false,
        ),
      );
      final demand = expandedTournamentRoundDemand(
        selectedTourId: detail.aboutTourModel.id,
        knownTourIds: detail.tours.map((tour) => tour.tour.id),
        rounds: rounds.gamesAppBarModels,
        expansion: expansion,
        visibleRoundIds:
            isSearchMode
                ? const {}
                : ref.watch(
                  visibleTournamentRoundsProvider(detail.aboutTourModel.id),
                ),
      );
      var disposed = false;
      ref.onDispose(() => disposed = true);
      for (final entry in demand.entries) {
        final loader = ref.watch(gamesTourProvider(entry.key).notifier);
        ref.onDispose(loader.deactivateRounds);
        unawaited(
          Future.microtask(() async {
            if (!disposed) await loader.setActiveRounds(entry.value);
          }),
        );
      }
      return demand;
    });
