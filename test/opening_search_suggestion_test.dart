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

  test('unrelated text returns no opening destinations', () {
    expect(searchOpeningSuggestions('zzzz-no-opening'), isEmpty);
  });
}
