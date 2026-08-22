import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog contains every supplied line, code, and explicit range', () {
    expect(EcoOpenings.catalog, hasLength(1813));
    expect(EcoOpenings.recordsByCode, hasLength(500));
    expect(EcoOpenings.rangeCatalog, hasLength(41));
    expect(EcoOpenings.variantCountForCode('B90'), greaterThan(1));
  });

  test('opening search keeps ancestry in-card and is not capped at four', () {
    final results = searchOpeningSuggestions('Najdorf');

    expect(results.length, greaterThan(4));
    expect(results.first.filter.code, 'B9');
    final najdorfFamily = results.indexWhere(
      (result) => result.filter.code == 'B9',
    );
    final najdorfCode = results.indexWhere(
      (result) => result.filter.code == 'B90',
    );
    expect(najdorfFamily, 0);
    expect(najdorfCode, greaterThan(najdorfFamily));
    expect(results[najdorfFamily].filter.isFamily, isTrue);
    expect(results[najdorfFamily].fullTitle, contains('Najdorf'));
    expect(results[najdorfFamily].title, 'Sicilian defence');
    expect(results[najdorfFamily].subtitle, contains('Najdorf'));
    expect(
      results.any((result) => result.filter.code == 'B20-B99'),
      isFalse,
      reason: 'A non-matching ancestor must not crowd out the matched branch.',
    );
  });

  test('a directly matched family still precedes its matched children', () {
    final results = searchOpeningSuggestions('Sicilian');
    final root = results.indexWhere(
      (result) => result.filter.code == 'B20-B99',
    );
    final child = results.indexWhere(
      (result) => result.filter.code == 'B20' && !result.isAggregate,
    );

    expect(root, isNonNegative);
    expect(child, greaterThan(root));
    expect(results[root].subtitle, '80 ECO codes');
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
    expect(results.first.filter.exactEcoCodes, hasLength(40));
    expect(results.first.filter.exactEcoCodes.first, 'E60');
    expect(results.first.filter.exactEcoCodes.last, 'E99');
    expect(results.first.codeLabel, 'E60-E99');
    expect(results.first.subtitle, contains('40 ECO codes'));
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

  test('a deep named variant carries its full ancestry inside the result', () {
    final results = searchOpeningSuggestions('Poisoned pawn');
    final poisonedPawn = results.indexWhere(
      (result) =>
          result.filter.code == 'B97' &&
          result.subtitle.toLowerCase().contains('poisoned pawn'),
    );

    expect(poisonedPawn, isNonNegative);
    expect(results[poisonedPawn].hierarchyLabel, contains('Sicilian'));
    expect(results[poisonedPawn].hierarchyLabel, contains('Najdorf'));
    expect(results[poisonedPawn].hierarchyLabel, contains('Poisoned pawn'));
    expect(results[poisonedPawn].subtitle, isNot(contains('All')));
    expect(
      results.any(
        (result) =>
            result.filter.code == 'B20-B99' || result.filter.code == 'B9',
      ),
      isFalse,
    );
  });

  test(
    'a partial variation name returns the matching CSV leaves themselves',
    () {
      final results = searchOpeningSuggestions('Gurgen');

      expect(results, hasLength(5));
      expect(
        results.map((result) => result.subtitle),
        containsAll(<String>[
          'Gurgenidze variation',
          'Gurgenidze counter-attack',
          'Gurgenidze system',
        ]),
      );
      expect(
        results.where((result) => result.filter.code == 'B15'),
        hasLength(2),
        reason:
            'Distinct CSV leaves sharing an ECO code must stay discoverable.',
      );
      expect(
        results.every((result) => !result.filter.isFamily),
        isTrue,
        reason:
            'Ancestor names belong inside each matched leaf, not before it.',
      );
    },
  );

  test(
    'a variation uses grey supporting text for its non-repeated leaf name',
    () {
      final results = searchOpeningSuggestions('Sicilian Wing');

      expect(results.map((result) => result.subtitle), contains('Wing gambit'));
      final result = results.firstWhere(
        (result) => result.subtitle == 'Wing gambit',
      );

      expect(result.filter.code, 'B20');
      expect(result.title, 'Sicilian defence');
      expect(result.hierarchyLabel, 'Sicilian defence › Wing gambit');
      expect(result.subtitle, isNot(result.title));
    },
  );

  test('same-code move ancestors remain visible in a deep child path', () {
    final results = searchOpeningSuggestions('Sicilian Wing');
    final parent = results.firstWhere(
      (result) => result.subtitle == 'Wing gambit',
    );
    final result = results.firstWhere(
      (result) => result.subtitle.contains('Carlsbad variation'),
    );

    expect(
      result.subtitle,
      'Wing gambit › Marshall variation › Carlsbad variation',
    );
    expect(parent.isParentOf(result), isTrue);
    expect(result.isParentOf(parent), isFalse);
  });

  test('the longer Gurgenidze prefix remains searchable', () {
    final results = searchOpeningSuggestions('Gurgenidz');

    expect(results, hasLength(5));
    expect(
      results.any((result) => result.subtitle == 'Gurgenidze variation'),
      isTrue,
    );
  });

  test('opening suggestions begin on the third character', () {
    expect(searchOpeningSuggestions('si'), isEmpty);
    expect(searchOpeningSuggestions('sic').length, greaterThan(4));
  });

  test('an exact two-character family code remains searchable', () {
    final results = searchOpeningSuggestions('b9');

    expect(results.first.filter.code, 'B9');
  });

  test('fuzzy matching handles an adjacent transposition', () {
    final results = searchOpeningSuggestions('najdrof');

    expect(results.any((result) => result.filter.code == 'B9'), isTrue);
  });

  test('arbitrary CSV ranges compile to exact safe prefixes', () {
    final filter = GameEcoFilter.forFamily('D30-D42');

    expect(filter.ecoPrefixes, ['D3', 'D40', 'D41', 'D42']);
    expect(filter.exactEcoCodes, hasLength(13));
    expect(filter.exactEcoCodes.first, 'D30');
    expect(filter.exactEcoCodes.last, 'D42');
    expect(filter.matches('D30'), isTrue);
    expect(filter.matches('D42'), isTrue);
    expect(filter.matches('D43'), isFalse);
  });

  test('unrelated text returns no opening destinations', () {
    expect(searchOpeningSuggestions('zzzz-no-opening'), isEmpty);
  });
}
