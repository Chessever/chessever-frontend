import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/favorites/player_games/'
        'favorites_combined_games_screen.dart',
      ).readAsStringSync();

  test('uses full-screen content with floating Liquid Glass controls', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('GlassIslandStack('));
    expect(source, contains('GlassContainer('));
    expect(source, contains('includeContentSafeArea: false'));
    expect(source, contains('SizedBox(height: topContentInset)'));
    expect(source, contains('_buildFilterChips(favorites, controlExtent)'));
    expect(source, contains('GlassChip('));

    expect(source, isNot(contains('SliverAppBar(')));
    expect(source, isNot(contains('SliverPersistentHeader(')));
    expect(source, isNot(contains('_SliverSearchBarDelegate')));
    expect(source, isNot(contains('return Scaffold(')));
  });

  test('keeps filter controls accessible and motion-aware', () {
    expect(source, contains('MediaQuery.textScalerOf(context).scale(16)'));
    expect(source, contains("label: 'Clear search'"));
    expect(source, contains("label: 'Clear player filters'"));
    expect(source, contains('selected: isSelected'));
    expect(source, contains('dimension: 48'));
    expect(source, contains('size: 48'));
    expect(source, contains('GlassMotion.reduceMotion(context)'));
  });
}
