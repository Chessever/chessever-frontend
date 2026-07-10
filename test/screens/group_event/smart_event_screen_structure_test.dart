import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/group_event/smart_event/'
        'smart_event_screen.dart',
      ).readAsStringSync();

  test('uses floating full-screen Liquid Glass chrome', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('GlassIslandStack('));
    expect(source, contains('_FloatingSearchFilterBar('));
    expect(source, contains('_SmartEventSegments('));
    expect(source, contains('tabScope.topContentInset'));
    expect(source, contains('scope.topContentInset'));

    expect(source, isNot(contains('Scaffold(')));
    expect(source, isNot(contains('SliverAppBar(')));
    expect(source, isNot(contains('SliverPersistentHeader(')));
    expect(source, isNot(contains('pinned: true')));
  });

  test('preserves controls, accessibility, and motion policy', () {
    expect(source, contains('MediaQuery.textScalerOf(context).scale(16)'));
    expect(source, contains("tooltip: 'Clear search'"));
    expect(source, contains("label: 'Change game view'"));
    expect(source, contains('size: controlExtent'));
    expect(source, contains('height: controlExtent'));
    expect(source, contains('GlassMotion.reduceMotion(context)'));

    expect(source, contains('showGameFilterDialog('));
    expect(source, contains('requireFullAuthGuard(context)'));
    expect(source, contains('_AppBarTitle('));
    expect(source, contains('_TitleSelector('));
  });
}
