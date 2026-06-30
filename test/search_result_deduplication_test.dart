import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:flutter_test/flutter_test.dart';

SearchResult _eventResult({
  required String id,
  required String title,
  DateTime? start,
  DateTime? end,
  required int maxAvgElo,
  double score = 100,
}) {
  return SearchResult(
    tournament: GroupEventCardModel(
      id: id,
      title: title,
      dates: 'Jun 15 - Jun 24, 2026',
      maxAvgElo: maxAvgElo,
      timeUntilStart: '',
      tourEventCategory: TourEventCategory.completed,
      timeControl: 'Standard',
      endDate: end,
      startDate: start,
      searchTerms: [title],
    ),
    score: score,
    matchedText: title,
    type: SearchResultType.tournament,
  );
}

void main() {
  group('dedupeTournamentSearchResultsByLogicalEvent', () {
    test(
      'collapses Capablanca parent/stage duplicates into canonical event',
      () {
        final results = [
          _eventResult(
            id: 'lix_internacional_capablanca_in_memoriam',
            title: 'LIX Internacional Capablanca in Memoriam',
            start: DateTime.utc(2026, 6, 15, 20, 15),
            end: DateTime.utc(2026, 6, 24, 13, 15),
            maxAvgElo: 0,
          ),
          _eventResult(
            id: 'lix_internacional_capablanca_in_memoriam_2026',
            title: 'LIX Internacional Capablanca in Memoriam 2026',
            start: DateTime.utc(2026, 6, 15, 20, 15),
            end: DateTime.utc(2026, 6, 24, 14, 15),
            maxAvgElo: 2414,
          ),
          _eventResult(
            id: 'lix_internacional_capablanca_in_memoriam_2026_open',
            title: 'LIX Internacional Capablanca in Memoriam 2026 | OPEN',
            start: DateTime.utc(2026, 6, 15, 20, 15),
            end: DateTime.utc(2026, 6, 24, 14, 15),
            maxAvgElo: 2414,
          ),
          _eventResult(
            id: 'lviii_internacional_capablanca_in_memoriam',
            title: 'LVIII Internacional Capablanca in Memoriam',
            start: DateTime.utc(2025, 5, 10, 19, 15),
            end: DateTime.utc(2025, 5, 19, 14, 15),
            maxAvgElo: 0,
          ),
        ];

        final deduped = dedupeTournamentSearchResultsByLogicalEvent(results);

        expect(deduped.map((result) => result.tournament.id), [
          'lix_internacional_capablanca_in_memoriam_2026',
          'lviii_internacional_capablanca_in_memoriam',
        ]);
        expect(
          deduped.first.tournament.title,
          'LIX Internacional Capablanca in Memoriam 2026',
        );
      },
    );

    test('prefers a stageless parent over a year-bearing stage row', () {
      final results = [
        _eventResult(
          id: 'parent',
          title: 'LIX Internacional Capablanca in Memoriam',
          start: DateTime.utc(2026, 6, 15),
          end: DateTime.utc(2026, 6, 24),
          maxAvgElo: 0,
        ),
        _eventResult(
          id: 'open-stage',
          title: 'LIX Internacional Capablanca in Memoriam 2026 | OPEN',
          start: DateTime.utc(2026, 6, 15),
          end: DateTime.utc(2026, 6, 24),
          maxAvgElo: 2600,
        ),
      ];

      final deduped = dedupeTournamentSearchResultsByLogicalEvent(results);

      expect(deduped.map((result) => result.tournament.id), ['parent']);
      expect(deduped.single.tournament.title.contains('|'), isFalse);
    });

    test('collapses DC International parent and Open suffix rows', () {
      final results = [
        _eventResult(
          id: '4th_annual_dc_international',
          title: '4th annual DC International',
          start: DateTime.utc(2026, 6, 25, 23, 15),
          end: DateTime.utc(2026, 6, 29, 20, 15),
          maxAvgElo: 2430,
        ),
        _eventResult(
          id: '4th_annual_dc_international_open',
          title: '4th annual DC International Open',
          start: DateTime.utc(2026, 6, 25, 23, 15),
          end: DateTime.utc(2026, 6, 29, 20, 15),
          maxAvgElo: 0,
        ),
      ];

      final deduped = dedupeTournamentSearchResultsByLogicalEvent(results);

      expect(deduped.map((result) => result.tournament.id), [
        '4th_annual_dc_international',
      ]);
    });

    test('does not collapse short Open event names by suffix alone', () {
      final results = [
        _eventResult(
          id: 'world_open',
          title: 'World Open',
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 7, 5),
          maxAvgElo: 2600,
        ),
        _eventResult(
          id: 'world',
          title: 'World',
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 7, 5),
          maxAvgElo: 0,
        ),
      ];

      final deduped = dedupeTournamentSearchResultsByLogicalEvent(results);

      expect(deduped.map((result) => result.tournament.id), [
        'world_open',
        'world',
      ]);
    });

    test('keeps same-title undated events separate', () {
      final results = [
        _eventResult(id: 'undated-1', title: 'Mystery Open', maxAvgElo: 2500),
        _eventResult(id: 'undated-2', title: 'Mystery Open', maxAvgElo: 2600),
      ];

      final deduped = dedupeTournamentSearchResultsByLogicalEvent(results);

      expect(deduped.map((result) => result.tournament.id), [
        'undated-1',
        'undated-2',
      ]);
    });

    test('keeps same-name events on different dates separate', () {
      final results = [
        _eventResult(
          id: 'weekly_event_1',
          title: 'Weekly Arena 2026',
          start: DateTime.utc(2026, 6, 1),
          end: DateTime.utc(2026, 6, 1, 2),
          maxAvgElo: 2600,
        ),
        _eventResult(
          id: 'weekly_event_2',
          title: 'Weekly Arena 2026',
          start: DateTime.utc(2026, 6, 8),
          end: DateTime.utc(2026, 6, 8, 2),
          maxAvgElo: 2600,
        ),
      ];

      final deduped = dedupeTournamentSearchResultsByLogicalEvent(results);

      expect(deduped.map((result) => result.tournament.id), [
        'weekly_event_1',
        'weekly_event_2',
      ]);
    });
  });
}
