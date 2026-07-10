import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/players/player_screen.dart',
      ).readAsStringSync();

  test(
    'Players directory is one full-screen canvas with floating controls',
    () {
      expect(source, contains('GlassFullScreenPage('));
      expect(source, contains("'players-floating-controls'"));
      expect(source, contains("'players-floating-control-rail'"));
      expect(source, contains('GlassIslandSearch('));
      expect(source, isNot(contains('return ScreenWrapper(')));
      expect(source, isNot(contains('SliverPersistentHeader')));
      expect(source, isNot(contains('SliverAppBar')));
    },
  );

  test('floating controls expose filter, sort, and column meaning', () {
    expect(source, contains("'All players'"));
    expect(source, contains("'Favorites'"));
    expect(source, contains("'Sort · \$sortLabel'"));
    expect(source, contains("'Player · Elo · Age'"));
    expect(source, contains("'Columns: Player, Elo, Age'"));
    expect(source, contains('_PlayerDirectoryFilter'));
    expect(source, contains('_PlayerDirectorySort'));
  });

  test('layout protects narrow screens, Dynamic Type, and semantics', () {
    expect(source, contains('MediaQuery.textScalerOf(context).scale(14)'));
    expect(source, contains('.clamp(48.0, 72.0)'));
    expect(source, contains('SingleChildScrollView('));
    expect(source, contains('scrollDirection: Axis.horizontal'));
    expect(source, contains('Semantics('));
    expect(source, contains('minHeight: controlHeight'));
    expect(source, contains('GlassMotion.reduceMotion(context)'));
    expect(source, contains('interactionScale: reduceMotion ? 1 : 1.03'));
  });

  test('paging, refresh, favorite guards, and E2E IDs remain wired', () {
    expect(source, contains('fetchNextPage()'));
    expect(source, contains('RefreshIndicator('));
    expect(source, contains('canAddMoreFavorites(context, ref)'));
    expect(source, contains('E2eIds.playersRoot'));
    expect(source, contains('E2eIds.playersSearchField'));
  });
}
