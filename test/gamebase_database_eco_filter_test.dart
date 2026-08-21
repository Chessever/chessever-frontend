import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic>? _ecoClause(Map<String, dynamic>? where) {
  if (where == null) return null;
  if (where['field'] == 'eco') return where;
  final and = where['and'];
  if (and is! List) return null;
  for (final clause in and) {
    if (clause is Map<String, dynamic> && clause['field'] == 'eco') {
      return clause;
    }
  }
  return null;
}

void main() {
  test('eco-only C45 uses POST startsWith without a trailing %', () {
    final filter = GamebaseFilter(eco: GameEcoFilter.forCode('C45'));

    expect(shouldUseExactLibraryGameQuery('', filter), isTrue);

    final where = buildLibraryExactWhere(filter);
    expect(where, {'field': 'eco', 'op': 'startsWith', 'value': 'C45'});
    expect(where.toString(), isNot(contains('%')));
  });

  test('Najdorf family uses the same safe startsWith contract for B9', () {
    final filter = GamebaseFilter(eco: GameEcoFilter.forFamily('B9'));

    expect(filter.eco.openingName, 'Sicilian: Najdorf');
    expect(buildLibraryExactWhere(filter), {
      'field': 'eco',
      'op': 'startsWith',
      'value': 'B9',
    });
    expect(composeGamebaseSearchQuery(query: '', filter: filter), 'eco:B9 *');
  });

  test('eco B90 plus year AND-combines startsWith with date between', () {
    final filter = GamebaseFilter(
      eco: GameEcoFilter.forCode('B90'),
      minYear: 2020,
      maxYear: 2020,
    );

    expect(shouldUseExactLibraryGameQuery('', filter), isTrue);

    final where = buildLibraryExactWhere(filter);
    expect(where, {
      'and': [
        {'field': 'eco', 'op': 'startsWith', 'value': 'B90'},
        {
          'field': 'date',
          'op': 'between',
          'values': ['2020-01-01T00:00:00.000Z', '2020-12-31T23:59:59.999Z'],
        },
      ],
    });

    final eco = _ecoClause(where);
    expect(eco?['op'], 'startsWith');
    expect(eco?['value'], 'B90');
    expect(eco?['value'], isNot(contains('%')));
    expect(where.toString(), isNot(contains('B90%')));
    expect(where.toString(), isNot(contains('ilike')));
  });

  test('unknown eco ? uses exact eq', () {
    final filter = GamebaseFilter(
      eco: GameEcoFilter.forCode(GameEcoFilter.unknownEcoCode),
    );

    expect(shouldUseExactLibraryGameQuery('', filter), isTrue);
    expect(buildLibraryExactWhere(filter), {
      'field': 'eco',
      'op': 'eq',
      'value': '?',
    });
  });

  test('eco plus free-text stays on GET compose eco:C45 something', () {
    final filter = GamebaseFilter(eco: GameEcoFilter.forCode('C45'));

    expect(shouldUseExactLibraryGameQuery('something', filter), isFalse);
    expect(
      composeGamebaseSearchQuery(query: 'something', filter: filter),
      'eco:C45 something',
    );
  });

  test('eco-only compose is eco:C45 *', () {
    final filter = GamebaseFilter(eco: GameEcoFilter.forCode('C45'));

    expect(composeGamebaseSearchQuery(query: '', filter: filter), 'eco:C45 *');
  });

  test('color still forces GET even when eco is set', () {
    final filter = GamebaseFilter(
      eco: GameEcoFilter.forCode('C45'),
      color: GameColorFilter.white,
    );

    expect(shouldUseExactLibraryGameQuery('', filter), isFalse);
    expect(composeGamebaseSearchQuery(query: '', filter: filter), 'eco:C45 *');
  });

  test('eco where values are prefix-matchable and never ilike B90%', () {
    final filter = GamebaseFilter(eco: GameEcoFilter.forCode('B90'));
    final where = buildLibraryExactWhere(filter);
    final eco = _ecoClause(where);

    expect(eco, isNotNull);
    expect(eco!['op'], isNot('ilike'));
    expect(eco['op'], 'startsWith');
    expect(eco['value'], 'B90');
    expect('${eco['value']}', isNot(endsWith('%')));
  });
}
