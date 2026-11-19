import 'package:chessever2/screens/search/search_page_landing.dart'
    show searchOpeningSmartEvents;
import 'package:chessever2/screens/search/search_page_results.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which openings a search on the Search tab shows beside its players and
/// events, against the real opening catalog: a line that names the query,
/// never one that only resembles it.
void main() {
  List<OpeningSearchSuggestion> distinct(String query) =>
      searchOpeningSmartEvents(searchOpeningSuggestions(query));

  group('an opening that names the query', () {
    for (final query in ['carlsen', 'ding', 'anand', 'nepo', 'pragg']) {
      test('"$query" (a player) names none, though the catalog has '
          'lookalikes', () {
        final all = distinct(query);
        expect(all, isNotEmpty, reason: 'the lookalikes this pins');
        expect(all.where(searchOpeningIsStrong), isEmpty);
      });
    }

    for (final (query, line) in [
      ('najdorf', 'Najdorf'),
      ('larsen', 'Larsen'),
      ('india', 'Indian'),
      ('london', 'London'),
      ('french', 'French'),
      ('b90', 'Najdorf'),
    ]) {
      test('"$query" names its lines', () {
        final named = distinct(query).where(searchOpeningIsStrong).toList();
        expect(named, isNotEmpty);
        expect(named.first.fullTitle, contains(line));
      });
    }
  });

  group('the openings a search shows', () {
    test('beside players or events, only those that name the query', () {
      final all = distinct('sicilian');
      final named = searchResultOpenings(
        all,
        othersFound: true,
        othersPending: false,
      );
      expect(named, isNotEmpty);
      expect(named.length, lessThan(all.length));
      expect(named.every(searchOpeningIsStrong), isTrue);
    });

    test('while players and events are on their way, the same', () {
      expect(
        searchResultOpenings(
          distinct('carlsen'),
          othersFound: false,
          othersPending: true,
        ),
        isEmpty,
      );
    });

    test('alone, every match: a typo still finds its opening', () {
      final all = distinct('sicillian');
      expect(all.where(searchOpeningIsStrong), isEmpty);
      final shown = searchResultOpenings(
        all,
        othersFound: false,
        othersPending: false,
      );
      expect(shown, all);
      expect(shown.first.fullTitle, startsWith('Sicilian'));
    });

    test('one smart event per ECO code, all of them without a limit', () {
      final all = searchOpeningSuggestions('najdorf');
      final events = searchOpeningSmartEvents(all);
      final codes = {for (final o in all) o.filter.code ?? o.id};
      expect(events, hasLength(codes.length));
      expect(searchOpeningSmartEvents(all, limit: 2), hasLength(2));
    });
  });
}
