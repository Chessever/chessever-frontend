import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The memorial player catalog lives under `repository/gamebase/` but is a
/// bundled asset (`assets/data/memorial-player-catalog.json`) read on the
/// device: it asks nothing of gamebase. These two files are the only part
/// of that folder the combined search may import.
const _bundledMemorialCatalog = [
  'lib/repository/gamebase/memorial_player.dart',
  'lib/repository/gamebase/memorial_player_local_search.dart',
];

void main() {
  test('homepage combined search does not depend on gamebase source data', () {
    final source = File(
      'lib/screens/group_event/providers/supabase_combined_search_provider.dart',
    ).readAsStringSync();
    final withoutCatalog = [
      for (final line in source.split('\n'))
        if (!_bundledMemorialCatalog.any(
          (path) => line.contains(
            "import 'package:chessever2/${path.substring('lib/'.length)}'",
          ),
        ))
          line,
    ].join('\n');

    expect(withoutCatalog, isNot(contains('repository/gamebase')));
    expect(withoutCatalog, isNot(contains('screens/gamebase')));
    expect(source, isNot(contains('gamebaseRepositoryProvider')));
    expect(source, isNot(contains('GamebaseRepository')));
  });

  test('the memorial catalog the search reads stays on the device', () {
    for (final path in _bundledMemorialCatalog) {
      final source = File(path).readAsStringSync();
      final imports = RegExp(
        r"^import '([^']+)';",
        multiLine: true,
      ).allMatches(source).map((match) => match.group(1)!).toList();
      expect(
        imports.where(
          (import) =>
              import.startsWith('package:') &&
              !import.startsWith('package:flutter/'),
        ),
        isEmpty,
        reason: '$path reads only Dart, Flutter and the bundled asset',
      );
      expect(
        imports.where((import) => !import.contains(':')),
        everyElement(
          isIn(const [
            'memorial_player.dart',
            'memorial_player_local_search.dart',
          ]),
        ),
        reason: '$path imports nothing else from repository/gamebase',
      );
      expect(source, isNot(contains('Supabase')));
      expect(source, isNot(contains('GamebaseRepository')));
      expect(source, isNot(contains('gamebaseConnection')));
    }
  });
}
