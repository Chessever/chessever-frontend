import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opening name search prioritizes a bulk-selectable parent family', () {
    final results = searchOpeningSuggestions('Najdorf');

    expect(results, isNotEmpty);
    expect(results.first.filter.code, 'B9');
    expect(results.first.filter.isFamily, isTrue);
    expect(results.first.title, contains('Najdorf'));
  });

  test('exact ECO code search prioritizes the individual code', () {
    final results = searchOpeningSuggestions('b90');

    expect(results, isNotEmpty);
    expect(results.first.filter.code, 'B90');
    expect(results.first.filter.isFamily, isFalse);
  });

  test("King's Indian search returns the complete E60-E99 family first", () {
    final results = searchOpeningSuggestions("king's indian");

    expect(results, isNotEmpty);
    expect(results.first.title, "King's Indian");
    expect(results.first.filter.isFamily, isTrue);
    expect(results.first.filter.ecoPrefixes, ['E6', 'E7', 'E8', 'E9']);
    expect(results.first.subtitle, contains('E60-E99'));
    expect(results.first.filter.matches('E60'), isTrue);
    expect(results.first.filter.matches('E99'), isTrue);
    expect(results.first.filter.matches('E59'), isFalse);
  });

  test('opening search normalizes typographic apostrophes', () {
    final straight = searchOpeningSuggestions("king's indian");
    final curly = searchOpeningSuggestions('king’s indian');

    expect(
      curly.map((result) => result.filter),
      straight.map((result) => result.filter),
    );
  });

  test('opening search accepts a missing apostrophe and small typo', () {
    final noApostrophe = searchOpeningSuggestions('kings indian');
    final typo = searchOpeningSuggestions('kings indain');

    expect(noApostrophe.first.title, "King's Indian");
    expect(typo.first.title, "King's Indian");
  });

  test('unrelated text returns no opening destinations', () {
    expect(searchOpeningSuggestions('zzzz-no-opening'), isEmpty);
  });
}
