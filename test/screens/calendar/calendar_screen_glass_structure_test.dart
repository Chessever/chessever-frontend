import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/calendar/calendar_screen.dart',
      ).readAsStringSync();

  test('Calendar uses the full-screen floating glass contract', () {
    expect(source, contains('return GlassFullScreenPage('));
    expect(source, contains('topOverlay: GlassIslandStack('));
    expect(source, contains("'calendar-floating-controls'"));
    expect(source, contains('GlassIslandSearch('));
    expect(source, contains('GlassContainer('));
    expect(source, contains('GlassChip('));
    expect(source, contains('GlassMotion.resolveDuration('));

    expect(source, isNot(contains('return ScreenWrapper(')));
    expect(source, isNot(contains('return Scaffold(')));
    expect(source, isNot(contains('appBar:')));
    expect(source, isNot(contains('body: Column(')));
  });

  test('Calendar content is one adaptive sliver canvas', () {
    expect(source, contains('CustomScrollView('));
    expect(source, contains('SliverLayoutBuilder('));
    expect(source, contains('SliverGrid('));
    expect(source, contains('SliverList('));
    expect(source, contains('SliverFillRemaining('));

    expect(source, isNot(contains('GridView.builder(')));
    expect(source, isNot(contains('ListView.builder(')));
    expect(source, isNot(contains('childAspectRatio: 2.2,\n')));
  });

  test('Calendar encodes accessibility and motion safeguards', () {
    expect(source, contains('clamp(48.0, 96.0)'));
    expect(source, contains('MediaQuery.textScalerOf(context)'));
    expect(source, contains('GlassMotion.reduceMotion(context)'));
    expect(source, contains('Semantics('));
    expect(source, contains('AlwaysScrollableScrollPhysics('));
  });
}
