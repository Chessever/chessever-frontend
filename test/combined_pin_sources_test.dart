import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_hall_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_pin_sources.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Combined pin reads never open full-tour or knockout loaders', () async {
    final categories = CombinedCategories([
      const CombinedCategory(tourId: 'a', label: 'A', avgElo: 2700, order: 0),
      const CombinedCategory(tourId: 'b', label: 'B', avgElo: 2600, order: 1),
    ]);
    final c = ProviderContainer(
      overrides: [
        combinedLiveTourIdsProvider.overrideWithValue({'a', 'b'}),
        combinedCategoriesProvider.overrideWithValue(categories),
        gamesTourProvider.overrideWith(
          (ref, id) => throw StateError('Full-tour download requested: $id'),
        ),
        relatedKnockoutStageIdsProvider.overrideWith(
          (ref, id) => throw StateError('Knockout download requested: $id'),
        ),
        combinedHallProvider.overrideWith(
          (ref, ids) => CombinedHall(
            ref,
            ids,
            backgroundDelay: Duration.zero,
            publishDelay: Duration.zero,
            readSource: (id) async => [
              Round(
                id: '$id-r',
                tourId: id,
                tourSlug: id,
                slug: 'round-1',
                name: 'Round 1',
                createdAt: DateTime.utc(2026),
                url: '',
              ),
            ],
            readPage: (r, _, __) async => [
              Games(
                id: '${r.tourId}-g',
                tourId: r.tourId,
                tourSlug: r.tourId,
                roundId: r.id,
                roundSlug: r.slug,
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    final a = c.listen(pinSourceGamesProvider('a'), (_, __) {});
    final b = c.listen(pinSourceGamesProvider('b'), (_, __) {});
    addTearDown(a.close);
    addTearDown(b.close);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(c.read(pinSourceGamesProvider('a')).requireValue.single.id, 'a-g');
    expect(c.read(pinSourceGamesProvider('b')).requireValue.single.id, 'b-g');
    expect(c.read(pinRelatedStageIdsProvider('a')), isEmpty);
    expect(c.read(pinRelatedStageIdsProvider('b')), isEmpty);
  });
  test('single-category pin sharing retains its normal stage lookup', () {
    final c = ProviderContainer(
      overrides: [
        combinedLiveTourIdsProvider.overrideWithValue({}),
        relatedKnockoutStageIdsProvider.overrideWith((ref, id) => ['stage-2']),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(pinRelatedStageIdsProvider('a')), ['stage-2']);
  });
}
