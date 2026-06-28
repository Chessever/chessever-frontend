import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('homepage combined search does not depend on gamebase source data', () {
    final source =
        File(
          'lib/screens/group_event/providers/supabase_combined_search_provider.dart',
        ).readAsStringSync();

    expect(source, isNot(contains('repository/gamebase')));
    expect(source, isNot(contains('screens/gamebase')));
    expect(source, isNot(contains('gamebaseRepositoryProvider')));
    expect(source, isNot(contains('GamebaseRepository')));
  });
}
