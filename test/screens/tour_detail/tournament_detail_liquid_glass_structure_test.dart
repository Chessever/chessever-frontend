import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tournament detail uses full-screen content with floating controls', () {
    final source =
        File(
          'lib/screens/tour_detail/tournament_detail_screen.dart',
        ).readAsStringSync();

    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('topOverlay: Center('));
    expect(source, contains('content: Center('));
    expect(source, contains('GlassIslandStack('));
    expect(source, isNot(contains('appBar:')));
    expect(source, isNot(contains('SliverAppBar(')));
    expect(source, isNot(contains('SliverPersistentHeader(')));
  });
}
