import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  String source(String path) => File('$root/$path').readAsStringSync();

  test('Gamebase database search floats search and pagination', () {
    final code = source(
      'lib/screens/library/gamebase_database_search_screen.dart',
    );

    expect(code, contains('GlassFullScreenPage('));
    expect(code, contains('topOverlay:'));
    expect(code, contains('bottomOverlay:'));
    expect(code, contains('GlassIslandStack('));
    expect(code, contains('GlassContainer('));
    expect(code, contains("label: 'Clear search'"));
    expect(code, contains("semanticLabel: 'Previous page'"));
    expect(code, contains('width: 48'));
    expect(code, isNot(contains('return Scaffold(')));
    expect(code, isNot(contains('appBar:')));
    expect(code, isNot(contains('SliverPersistentHeader')));
  });

  test('Gamebase player games is one full-screen content layer', () {
    final code = source(
      'lib/screens/library/gamebase_player_games_screen.dart',
    );

    expect(code, contains('GlassFullScreenPage('));
    expect(code, contains('topOverlay: GlassIslandTopBar('));
    expect(code, contains('minimumSize: const Size(48, 48)'));
    expect(code, isNot(contains('return Scaffold(')));
    expect(code, isNot(contains('appBar:')));
    expect(code, isNot(contains('SliverAppBar')));
  });
}
