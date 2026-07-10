import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/calendar/calendar_detail_screen.dart',
      ).readAsStringSync();

  test('month results use a full-screen canvas with floating controls', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains("'calendar-detail-floating-controls'"));
    expect(source, contains('GlassIslandTopBar('));
    expect(source, contains('GlassIslandSearch('));
    expect(source, contains('GlassTitleChip('));
    expect(source, contains('GlassMotion.resolveDuration('));
    expect(source, isNot(contains('return ScreenWrapper(')));
    expect(source, isNot(contains('return Scaffold(')));
    expect(source, isNot(contains('child: Column(')));
    expect(source, isNot(contains('SliverAppBar(')));
    expect(source, isNot(contains('SliverPersistentHeader(')));
  });

  test('month results keep adaptive and accessible controls', () {
    expect(source, contains('MediaQuery.textScalerOf(context)'));
    expect(source, contains('clamp(48.0, 96.0)'));
    expect(source, contains('Semantics('));
    expect(source, contains("label: 'Tournaments in \$title'"));
    expect(source, contains('backgroundColor: context.colors.background'));
  });
}
