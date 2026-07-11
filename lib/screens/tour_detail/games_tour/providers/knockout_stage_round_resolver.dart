import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';

class KnockoutStageRoundReference {
  const KnockoutStageRoundReference.selectedTour({required this.sourceRoundIds})
    : siblingTourId = null;

  const KnockoutStageRoundReference.siblingTour({
    required String tourId,
    required this.sourceRoundIds,
  }) : siblingTourId = tourId;

  final String? siblingTourId;
  final List<String> sourceRoundIds;

  bool get isSiblingTour => siblingTourId != null;
}

/// Resolves the two meanings of a synthetic `knockout-stage-*` display row.
///
/// Sibling-tour stages are identified by a complete known tour ID. Rows for a
/// logical stage inside the selected tour use [GamesAppBarModel.sourceRoundIds]
/// and must never have their `<selectedTourId>-<stageKey>` suffix treated as a
/// database tour ID.
KnockoutStageRoundReference? resolveKnockoutStageRoundReference({
  required GamesAppBarModel round,
  required String selectedTourId,
  required Iterable<String> knownTourIds,
}) {
  final prefix = '$kKnockoutStagePrefix-';
  if (!round.id.startsWith(prefix)) return null;

  final suffix = round.id.substring(prefix.length);
  final knownIds = knownTourIds.toSet();
  if (suffix != selectedTourId && knownIds.contains(suffix)) {
    return KnockoutStageRoundReference.siblingTour(
      tourId: suffix,
      sourceRoundIds: round.sourceRoundIds,
    );
  }

  if (suffix == selectedTourId || suffix.startsWith('$selectedTourId-')) {
    return KnockoutStageRoundReference.selectedTour(
      sourceRoundIds: round.sourceRoundIds,
    );
  }

  // Compatibility for legacy sibling rows created before sourceRoundIds were
  // attached. Unknown suffixes historically represented a stage tour ID.
  return KnockoutStageRoundReference.siblingTour(
    tourId: suffix,
    sourceRoundIds: round.sourceRoundIds,
  );
}

/// Returns the items represented by a tournament-detail display round.
List<T> itemsForTournamentDisplayRound<T>({
  required GamesAppBarModel round,
  required String selectedTourId,
  required Iterable<String> knownTourIds,
  required Iterable<T> selectedTourItems,
  required String Function(T item) sourceRoundIdOf,
  required Iterable<T> Function(String tourId) siblingTourItems,
}) {
  final reference = resolveKnockoutStageRoundReference(
    round: round,
    selectedTourId: selectedTourId,
    knownTourIds: knownTourIds,
  );
  if (reference == null) {
    return selectedTourItems
        .where((item) => sourceRoundIdOf(item) == round.id)
        .toList(growable: false);
  }

  final siblingTourId = reference.siblingTourId;
  if (siblingTourId != null) {
    return siblingTourItems(siblingTourId).toList(growable: false);
  }

  if (reference.sourceRoundIds.isEmpty) {
    return selectedTourItems.toList(growable: false);
  }
  final sourceRoundIds = reference.sourceRoundIds.toSet();
  return selectedTourItems
      .where((item) => sourceRoundIds.contains(sourceRoundIdOf(item)))
      .toList(growable: false);
}

Iterable<String> siblingKnockoutStageTourIds({
  required Iterable<GamesAppBarModel> rounds,
  required String selectedTourId,
  required Iterable<String> knownTourIds,
}) sync* {
  final seen = <String>{};
  for (final round in rounds) {
    final tourId =
        resolveKnockoutStageRoundReference(
          round: round,
          selectedTourId: selectedTourId,
          knownTourIds: knownTourIds,
        )?.siblingTourId;
    if (tourId != null && seen.add(tourId)) yield tourId;
  }
}

Set<String> representedTournamentIdsForDisplayRounds({
  required Iterable<GamesAppBarModel> rounds,
  required String selectedTourId,
  required Iterable<String> knownTourIds,
}) => <String>{
  selectedTourId,
  ...siblingKnockoutStageTourIds(
    rounds: rounds,
    selectedTourId: selectedTourId,
    knownTourIds: knownTourIds,
  ),
};
