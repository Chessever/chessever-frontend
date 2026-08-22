import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _QueryRecorder {
  String? operation;
  String? column;
  Object? value;

  _QueryRecorder eq(String column, Object value) {
    operation = 'eq';
    this.column = column;
    this.value = value;
    return this;
  }

  _QueryRecorder inFilter(String column, List<Object> values) {
    operation = 'in';
    this.column = column;
    value = values;
    return this;
  }
}

void main() {
  test('an exact opening uses indexed ECO equality', () {
    final query = _QueryRecorder();

    applyEcoFilterToSupabaseQuery(query, GameEcoFilter.forCode('B97'));

    expect(query.operation, 'eq');
    expect(query.column, 'eco');
    expect(query.value, 'B97');
  });

  test('a named family uses one indexed IN predicate', () {
    final query = _QueryRecorder();

    applyEcoFilterToSupabaseQuery(query, GameEcoFilter.forFamily('B9'));

    expect(query.operation, 'in');
    expect(query.column, 'eco');
    expect(query.value, [
      'B90',
      'B91',
      'B92',
      'B93',
      'B94',
      'B95',
      'B96',
      'B97',
      'B98',
      'B99',
    ]);
  });

  test('an irregular inclusive range expands without over-selecting', () {
    final query = _QueryRecorder();

    applyEcoFilterToSupabaseQuery(query, GameEcoFilter.forFamily('D30-D42'));

    expect(query.operation, 'in');
    expect(query.value, hasLength(13));
    expect(query.value, containsAll(['D30', 'D39', 'D40', 'D42']));
    expect(query.value, isNot(contains('D43')));
  });
}
