import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_sections.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_buckets.dart';

void main() {
  test('hall headers come from metadata even when no boards are loaded', () {
    final date = DateTime.utc(2026, 11, 10);
    final categories = [
      for (var i = 0; i < 2; i++)
        CombinedCategory(
          tourId: 't$i',
          label: 'Group $i',
          avgElo: 2700 - i,
          order: i,
        ),
    ];
    final rounds = {
      for (var i = 0; i < 2; i++)
        't$i': [
          Round(
            id: 'r$i',
            tourId: 't$i',
            tourSlug: 't$i',
            slug: 'round-1',
            name: 'Round 1',
            startsAt: date,
            createdAt: date,
            url: '',
          ),
        ],
    };
    final sections = buildCombinedRoundSections(
      categories: categories,
      gamesByTourId: const {},
      roundsByTourId: rounds,
      liveRoundIds: const [],
      includeEmptyRounds: true,
    );
    expect(sections.map((s) => s.round.id), ['r0', 'r1']);
    final buckets = buildCombinedRoundBuckets(
      sections,
      eventId: 'event',
      loadedRoundIds: {'r0'},
    );
    expect(buckets, hasLength(1));
    expect(buckets.single.round.sourceRoundIds, ['r0', 'r1']);
    expect(buckets.single.sources[0].label, contains('No games yet'));
    expect(buckets.single.sources[1].label, contains('Loading games'));
    expect(buckets.single.games, isEmpty);
    // Focused-game/full-catalog callers retain the existing game-only path.
    expect(
      buildCombinedRoundSections(
        categories: categories,
        gamesByTourId: const {},
        roundsByTourId: rounds,
        liveRoundIds: const [],
      ),
      isEmpty,
    );
  });
}
