import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// One non-default value on a real Library → TWIC filter axis.
class _AxisValue {
  const _AxisValue({
    required this.axis,
    required this.label,
    this.eco,
    this.result,
    this.color,
    this.timeControl,
    this.isOnline,
    this.minYear,
    this.maxYear,
    this.minRating,
    this.maxRating,
    this.query,
    this.event,
  });

  final String axis;
  final String label;
  final GameEcoFilter? eco;
  final GameResultFilter? result;
  final GameColorFilter? color;
  final GameTimeControlFilter? timeControl;
  final GameOnlineFilter? isOnline;
  final int? minYear;
  final int? maxYear;
  final int? minRating;
  final int? maxRating;
  final String? query;
  final String? event;

  GamebaseFilter applyFilter(GamebaseFilter filter) {
    return filter.copyWith(
      eco: eco ?? filter.eco,
      result: result ?? filter.result,
      color: color ?? filter.color,
      timeControl: timeControl ?? filter.timeControl,
      isOnline: isOnline ?? filter.isOnline,
      minYear: minYear ?? filter.minYear,
      maxYear: maxYear ?? filter.maxYear,
      minRating: minRating ?? filter.minRating,
      maxRating: maxRating ?? filter.maxRating,
    );
  }
}

class _Case {
  _Case({
    required this.kind,
    required this.parts,
    required this.filter,
    required this.query,
    required this.selectedEvent,
  });

  final String kind;
  final List<String> parts;
  final GamebaseFilter filter;
  final String query;
  final String? selectedEvent;

  String get name => '$kind ${parts.join(' + ')}';
}

const _ecoValues = <_AxisValue>[
  _AxisValue(axis: 'eco', label: 'eco=A', eco: GameEcoFilter(code: 'A')),
  _AxisValue(axis: 'eco', label: 'eco=B', eco: GameEcoFilter(code: 'B')),
  _AxisValue(axis: 'eco', label: 'eco=C45', eco: GameEcoFilter(code: 'C45')),
  _AxisValue(axis: 'eco', label: 'eco=B90', eco: GameEcoFilter(code: 'B90')),
  _AxisValue(
    axis: 'eco',
    label: 'eco=?',
    eco: GameEcoFilter(code: GameEcoFilter.unknownEcoCode),
  ),
];

const _resultValues = <_AxisValue>[
  _AxisValue(
    axis: 'result',
    label: 'result=whiteWins',
    result: GameResultFilter.whiteWins,
  ),
  _AxisValue(
    axis: 'result',
    label: 'result=blackWins',
    result: GameResultFilter.blackWins,
  ),
  _AxisValue(axis: 'result', label: 'result=draw', result: GameResultFilter.draw),
];

const _colorValues = <_AxisValue>[
  _AxisValue(axis: 'color', label: 'color=white', color: GameColorFilter.white),
  _AxisValue(axis: 'color', label: 'color=black', color: GameColorFilter.black),
];

const _timeControlValues = <_AxisValue>[
  _AxisValue(
    axis: 'timeControl',
    label: 'timeControl=classical',
    timeControl: GameTimeControlFilter.classical,
  ),
  _AxisValue(
    axis: 'timeControl',
    label: 'timeControl=rapid',
    timeControl: GameTimeControlFilter.rapid,
  ),
  _AxisValue(
    axis: 'timeControl',
    label: 'timeControl=blitz',
    timeControl: GameTimeControlFilter.blitz,
  ),
];

const _isOnlineValues = <_AxisValue>[
  _AxisValue(
    axis: 'isOnline',
    label: 'isOnline=online',
    isOnline: GameOnlineFilter.online,
  ),
  _AxisValue(
    axis: 'isOnline',
    label: 'isOnline=otb',
    isOnline: GameOnlineFilter.otb,
  ),
];

const _yearValues = <_AxisValue>[
  _AxisValue(axis: 'year', label: 'year=2018-2024', minYear: 2018, maxYear: 2024),
];

const _ratingValues = <_AxisValue>[
  _AxisValue(
    axis: 'rating',
    label: 'rating=2400-2800',
    minRating: 2400,
    maxRating: 2800,
  ),
];

const _eventValues = <_AxisValue>[
  _AxisValue(axis: 'selectedEvent', label: 'event=Tata', event: 'Tata'),
];

const _queryValues = <_AxisValue>[
  _AxisValue(axis: 'q', label: 'q=Carlsen', query: 'Carlsen'),
];

const _allAxes = <List<_AxisValue>>[
  _ecoValues,
  _resultValues,
  _colorValues,
  _timeControlValues,
  _isOnlineValues,
  _yearValues,
  _ratingValues,
  _eventValues,
  _queryValues,
];

_Case _caseFrom(String kind, List<_AxisValue> values) {
  var filter = GamebaseFilter();
  var query = '';
  String? selectedEvent;
  final parts = <String>[];
  for (final value in values) {
    filter = value.applyFilter(filter);
    if (value.query != null) query = value.query!;
    if (value.event != null) selectedEvent = value.event;
    parts.add(value.label);
  }
  return _Case(
    kind: kind,
    parts: parts,
    filter: filter,
    query: query,
    selectedEvent: selectedEvent,
  );
}

List<_Case> generateFilterMatrix() {
  final cases = <_Case>[];

  for (final axis in _allAxes) {
    for (final value in axis) {
      cases.add(_caseFrom('single', [value]));
    }
  }

  for (var i = 0; i < _allAxes.length; i++) {
    for (var j = i + 1; j < _allAxes.length; j++) {
      for (final left in _allAxes[i]) {
        for (final right in _allAxes[j]) {
          cases.add(_caseFrom('pair', [left, right]));
        }
      }
    }
  }

  final otherAxes = _allAxes.where((axis) => axis.first.axis != 'eco').toList();
  for (final eco in _ecoValues) {
    for (var i = 0; i < otherAxes.length; i++) {
      for (var j = i + 1; j < otherAxes.length; j++) {
        cases.add(
          _caseFrom('eco-triple', [eco, otherAxes[i].first, otherAxes[j].first]),
        );
      }
    }
  }

  cases.addAll([
    _caseFrom('4-way', [
      const _AxisValue(axis: 'eco', label: 'eco=C45', eco: GameEcoFilter(code: 'C45')),
      const _AxisValue(
        axis: 'result',
        label: 'result=whiteWins',
        result: GameResultFilter.whiteWins,
      ),
      const _AxisValue(
        axis: 'timeControl',
        label: 'timeControl=classical',
        timeControl: GameTimeControlFilter.classical,
      ),
      const _AxisValue(
        axis: 'year',
        label: 'year=2018-2024',
        minYear: 2018,
        maxYear: 2024,
      ),
    ]),
    _caseFrom('4-way', [
      const _AxisValue(
        axis: 'eco',
        label: 'eco=?',
        eco: GameEcoFilter(code: GameEcoFilter.unknownEcoCode),
      ),
      const _AxisValue(
        axis: 'result',
        label: 'result=draw',
        result: GameResultFilter.draw,
      ),
      const _AxisValue(
        axis: 'year',
        label: 'year=2018-2024',
        minYear: 2018,
        maxYear: 2024,
      ),
      const _AxisValue(axis: 'selectedEvent', label: 'event=Tata', event: 'Tata'),
    ]),
    _caseFrom('4-way', [
      const _AxisValue(axis: 'eco', label: 'eco=B90', eco: GameEcoFilter(code: 'B90')),
      const _AxisValue(
        axis: 'result',
        label: 'result=blackWins',
        result: GameResultFilter.blackWins,
      ),
      const _AxisValue(
        axis: 'isOnline',
        label: 'isOnline=otb',
        isOnline: GameOnlineFilter.otb,
      ),
      const _AxisValue(
        axis: 'rating',
        label: 'rating=2400-2800',
        minRating: 2400,
        maxRating: 2800,
      ),
    ]),
    _caseFrom('4-way', [
      const _AxisValue(axis: 'eco', label: 'eco=A', eco: GameEcoFilter(code: 'A')),
      const _AxisValue(
        axis: 'color',
        label: 'color=white',
        color: GameColorFilter.white,
      ),
      const _AxisValue(
        axis: 'timeControl',
        label: 'timeControl=rapid',
        timeControl: GameTimeControlFilter.rapid,
      ),
      const _AxisValue(axis: 'q', label: 'q=Carlsen', query: 'Carlsen'),
    ]),
    _caseFrom('4-way', [
      const _AxisValue(axis: 'eco', label: 'eco=B', eco: GameEcoFilter(code: 'B')),
      const _AxisValue(
        axis: 'timeControl',
        label: 'timeControl=blitz',
        timeControl: GameTimeControlFilter.blitz,
      ),
      const _AxisValue(
        axis: 'isOnline',
        label: 'isOnline=online',
        isOnline: GameOnlineFilter.online,
      ),
      const _AxisValue(axis: 'selectedEvent', label: 'event=Tata', event: 'Tata'),
    ]),
    _caseFrom('4-way', [
      const _AxisValue(axis: 'eco', label: 'eco=C45', eco: GameEcoFilter(code: 'C45')),
      const _AxisValue(
        axis: 'result',
        label: 'result=whiteWins',
        result: GameResultFilter.whiteWins,
      ),
      const _AxisValue(
        axis: 'rating',
        label: 'rating=2400-2800',
        minRating: 2400,
        maxRating: 2800,
      ),
      const _AxisValue(axis: 'q', label: 'q=Carlsen', query: 'Carlsen'),
    ]),
    _caseFrom('4-way', [
      const _AxisValue(
        axis: 'eco',
        label: 'eco=?',
        eco: GameEcoFilter(code: GameEcoFilter.unknownEcoCode),
      ),
      const _AxisValue(
        axis: 'color',
        label: 'color=black',
        color: GameColorFilter.black,
      ),
      const _AxisValue(
        axis: 'year',
        label: 'year=2018-2024',
        minYear: 2018,
        maxYear: 2024,
      ),
      const _AxisValue(axis: 'selectedEvent', label: 'event=Tata', event: 'Tata'),
    ]),
  ]);

  return cases;
}

bool _hasYearFilter(GamebaseFilter filter) =>
    filter.minYear != GameFilter.absoluteMinYear ||
    filter.maxYear != DateTime.now().year;

bool _hasRatingFilter(GamebaseFilter filter) =>
    filter.minRating > GameFilter.absoluteMinRating ||
    filter.maxRating < GameFilter.absoluteMaxRating;

List<Map<String, dynamic>> _clauses(Map<String, dynamic>? where) {
  if (where == null) return const [];
  final and = where['and'];
  if (and is List) {
    return [
      for (final clause in and)
        if (clause is Map<String, dynamic>) clause,
    ];
  }
  return [where];
}

Map<String, dynamic>? _clauseFor(
  List<Map<String, dynamic>> clauses,
  String field,
) {
  for (final clause in clauses) {
    if (clause['field'] == field) return clause;
  }
  return null;
}

void _collectIlikePercent(dynamic node, List<String> out, {String path = ''}) {
  if (node is Map) {
    final op = node['op'];
    final value = node['value'];
    if (op == 'ilike' && value is String && value.endsWith('%')) {
      out.add('$path field=${node['field']} op=ilike value=$value');
    }
    node.forEach((key, child) {
      _collectIlikePercent(child, out, path: '$path/$key');
    });
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      _collectIlikePercent(node[i], out, path: '$path[$i]');
    }
  }
}

void _assertExactWhere(_Case c, Map<String, dynamic>? where) {
  final reason = c.name;
  final clauses = _clauses(where);
  final ilikePercent = <String>[];
  _collectIlikePercent(where, ilikePercent);
  expect(ilikePercent, isEmpty, reason: reason);
  expect(where.toString().toLowerCase(), isNot(contains('ilike')), reason: reason);

  if (!c.filter.eco.isAll) {
    final eco = _clauseFor(clauses, 'eco');
    expect(eco, isNotNull, reason: reason);
    expect(eco!['op'], isNot('ilike'), reason: reason);
    if (c.filter.eco.isUnknownEco) {
      expect(eco['op'], 'eq', reason: reason);
      expect(eco['value'], GameEcoFilter.unknownEcoCode, reason: reason);
    } else {
      expect(eco['op'], 'startsWith', reason: reason);
      expect(eco['value'], c.filter.eco.code, reason: reason);
      expect(eco['value'], isNot(contains('%')), reason: reason);
    }
    expect('${eco['value']}', isNot(endsWith('%')), reason: reason);
  }

  if (c.filter.resultApiValue != null) {
    final result = _clauseFor(clauses, 'result');
    expect(result, isNotNull, reason: reason);
    expect(result!['op'], 'eq', reason: reason);
    expect(result['value'], c.filter.resultApiValue, reason: reason);
  }

  if (c.filter.timeControlApiValue != null) {
    final timeControl = _clauseFor(clauses, 'timeControl');
    expect(timeControl, isNotNull, reason: reason);
    expect(timeControl!['op'], 'eq', reason: reason);
    expect(timeControl['value'], c.filter.timeControlApiValue, reason: reason);
  }

  if (c.filter.isOnlineApiValue != null) {
    final isOnline = _clauseFor(clauses, 'isOnline');
    expect(isOnline, isNotNull, reason: reason);
    expect(isOnline!['op'], 'eq', reason: reason);
    expect(isOnline['value'], c.filter.isOnlineApiValue, reason: reason);
  }

  if (_hasYearFilter(c.filter)) {
    final date = _clauseFor(clauses, 'date');
    expect(date, isNotNull, reason: reason);
    expect(date!['op'], 'between', reason: reason);
    expect(date['values'], [
      '${c.filter.minYear.toString().padLeft(4, '0')}-01-01T00:00:00.000Z',
      '${c.filter.maxYear.toString().padLeft(4, '0')}-12-31T23:59:59.999Z',
    ], reason: reason);
  }

  if (_hasRatingFilter(c.filter)) {
    final rating = _clauseFor(clauses, 'averageRating');
    expect(rating, isNotNull, reason: reason);
    expect(rating!['op'], 'between', reason: reason);
    expect(rating['values'], [c.filter.minRating, c.filter.maxRating], reason: reason);
  }

  if (c.selectedEvent != null && c.selectedEvent!.isNotEmpty) {
    final event = _clauseFor(clauses, 'event');
    expect(event, isNotNull, reason: reason);
    expect(event!['op'], 'eq', reason: reason);
    expect(event['value'], c.selectedEvent, reason: reason);
  }
}

void _assertCompose(_Case c) {
  final reason = c.name;
  final composed = composeGamebaseSearchQuery(
    query: c.query,
    filter: c.filter,
    selectedEvent: c.selectedEvent,
  );

  if (c.query.trim().isEmpty) {
    expect(composed.contains('*'), isTrue, reason: reason);
  } else {
    expect(composed.contains(c.query.trim()), isTrue, reason: reason);
  }

  if (!c.filter.eco.isAll) {
    expect(composed.startsWith('eco:${c.filter.eco.code} '), isTrue, reason: reason);
  }

  if (c.selectedEvent != null && c.selectedEvent!.trim().isNotEmpty) {
    expect(composed.contains('event:"${c.selectedEvent!.trim()}"'), isTrue, reason: reason);
  }

  expect(composed.toLowerCase(), isNot(contains('ilike')), reason: reason);
}

void main() {
  final cases = generateFilterMatrix();
  final ilikePercentCombos = <String>[];

  test('filter matrix enumerates more than 80 real UI combinations', () {
    expect(cases.length, greaterThan(80));
    expect(cases.where((c) => c.kind == 'single').length, 19);
    expect(cases.where((c) => c.kind == 'pair').length, 153);
    expect(cases.where((c) => c.kind == 'eco-triple').length, 140);
    expect(cases.where((c) => c.kind == '4-way').length, greaterThanOrEqualTo(5));
    expect(
      cases.any(
        (c) =>
            c.kind == '4-way' &&
            c.parts.contains('eco=C45') &&
            c.parts.contains('result=whiteWins') &&
            c.parts.contains('timeControl=classical') &&
            c.parts.contains('year=2018-2024'),
      ),
      isTrue,
    );
    expect(
      cases.any(
        (c) =>
            c.kind == '4-way' &&
            c.parts.contains('eco=?') &&
            c.parts.contains('event=Tata'),
      ),
      isTrue,
    );
  });

  test('color-only still uses GET compose, never exact where', () {
    for (final color in _colorValues) {
      final c = _caseFrom('single', [color]);
      expect(shouldUseExactLibraryGameQuery(c.query, c.filter), isFalse);
      expect(
        composeGamebaseSearchQuery(
          query: c.query,
          filter: c.filter,
          selectedEvent: c.selectedEvent,
        ),
        '*',
      );
    }
  });

  for (final c in cases) {
    test(c.name, () {
      final useExact = shouldUseExactLibraryGameQuery(c.query, c.filter);

      if (c.filter.colorApiValue != null) {
        expect(useExact, isFalse, reason: c.name);
      }
      if (c.query.trim().isNotEmpty) {
        expect(useExact, isFalse, reason: c.name);
      }

      if (useExact) {
        final where = buildLibraryExactWhere(
          c.filter,
          selectedEvent: c.selectedEvent,
        );
        final found = <String>[];
        _collectIlikePercent(where, found);
        if (found.isNotEmpty) {
          ilikePercentCombos.add('${c.name}: ${found.join('; ')}');
        }
        _assertExactWhere(c, where);
      } else {
        _assertCompose(c);
      }
    });
  }

  test('no generated combination emits ilike with a trailing %', () {
    expect(ilikePercentCombos, isEmpty, reason: ilikePercentCombos.join('\n'));
  });
}
