import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_stage_round_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveKnockoutStageRoundReference', () {
    test('keeps a round-derived stage inside the selected tour', () {
      final reference = resolveKnockoutStageRoundReference(
        round: _round('knockout-stage-tour-with-hyphens-round-3', const [
          'round-31',
          'round-32',
        ]),
        selectedTourId: 'tour-with-hyphens',
        knownTourIds: const ['tour-with-hyphens', 'sibling-final'],
      );

      expect(reference?.siblingTourId, isNull);
      expect(reference?.sourceRoundIds, ['round-31', 'round-32']);
    });

    test('resolves a complete known sibling tour id', () {
      final reference = resolveKnockoutStageRoundReference(
        round: _round('knockout-stage-sibling-final', const ['final-game-1']),
        selectedTourId: 'selected-round-3',
        knownTourIds: const ['selected-round-3', 'sibling-final'],
      );

      expect(reference?.siblingTourId, 'sibling-final');
    });

    test('known tour ids win over prefix-shaped sibling ids', () {
      final reference = resolveKnockoutStageRoundReference(
        round: _round('knockout-stage-selected-round-3-final', const [
          'final-game',
        ]),
        selectedTourId: 'selected-round-3',
        knownTourIds: const ['selected-round-3', 'selected-round-3-final'],
      );

      expect(reference?.siblingTourId, 'selected-round-3-final');
    });

    test('live-round reload scope includes represented sibling tours', () {
      final represented = representedTournamentIdsForDisplayRounds(
        rounds: [
          _round('knockout-stage-selected-tour', const ['selected-game-1']),
          _round('knockout-stage-sibling-final', const ['final-game-1']),
          _round('knockout-stage-sibling-final', const ['final-game-2']),
          _round('knockout-stage-selected-tour-round-3', const ['round-31']),
        ],
        selectedTourId: 'selected-tour',
        knownTourIds: const ['selected-tour', 'sibling-final'],
      );

      expect(represented, {'selected-tour', 'sibling-final'});
      expect(represented.contains('selected-tour-round-3'), isFalse);
    });
  });

  group('itemsForTournamentDisplayRound', () {
    test('filters a round-derived stage by source round ids', () {
      final items = itemsForTournamentDisplayRound<_Item>(
        round: _round('knockout-stage-tour-round-3', const [
          'round-31',
          'round-32',
        ]),
        selectedTourId: 'tour',
        knownTourIds: const ['tour'],
        selectedTourItems: const [
          _Item('g31', 'round-31'),
          _Item('g32', 'round-32'),
          _Item('g41', 'round-41'),
        ],
        sourceRoundIdOf: (item) => item.roundId,
        siblingTourItems: (_) => const [],
      );

      expect(items.map((item) => item.id), ['g31', 'g32']);
    });

    test('loads sibling items only for a sibling stage', () {
      final requestedTourIds = <String>[];
      final items = itemsForTournamentDisplayRound<_Item>(
        round: _round('knockout-stage-final-tour', const ['final-round']),
        selectedTourId: 'selected-tour',
        knownTourIds: const ['selected-tour', 'final-tour'],
        selectedTourItems: const [_Item('selected', 'selected-round')],
        sourceRoundIdOf: (item) => item.roundId,
        siblingTourItems: (tourId) {
          requestedTourIds.add(tourId);
          return const [_Item('final', 'final-round')];
        },
      );

      expect(requestedTourIds, ['final-tour']);
      expect(items.single.id, 'final');
    });
  });
}

GamesAppBarModel _round(String id, List<String> sourceRoundIds) =>
    GamesAppBarModel(
      id: id,
      name: id,
      startsAt: null,
      roundStatus: RoundStatus.completed,
      sourceRoundIds: sourceRoundIds,
    );

class _Item {
  const _Item(this.id, this.roundId);

  final String id;
  final String roundId;
}
