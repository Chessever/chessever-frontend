import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('drawer exposes one Board destination first and removes old duplicates', () {
    final drawer = File(
      'lib/widgets/hamburger_menu/hamburger_menu.dart',
    ).readAsStringSync();
    final home = File('lib/screens/home/home_screen.dart').readAsStringSync();
    final e2e = File('lib/e2e/e2e_ids.dart').readAsStringSync();
    final smoke = File('patrol_test/signed_in_smoke_test.dart').readAsStringSync();

    expect(drawer, contains('required this.onBoardPressed'));
    expect(drawer, isNot(contains('onAnalysisBoardPressed')));
    expect(drawer, isNot(contains('onOpeningExplorerPressed')));
    expect(drawer, isNot(contains("title: 'Explorer'")));

    final boardIndex = drawer.indexOf("title: 'Board'");
    final rankingsIndex = drawer.indexOf("title: 'Rankings'");
    expect(boardIndex, greaterThanOrEqualTo(0));
    expect(boardIndex, lessThan(rankingsIndex));

    expect(home, contains('onBoardPressed: () async'));
    expect(home, contains('GamebaseExplorerScreen.scoped()'));
    expect(
      home.substring(
        home.indexOf('HamburgerMenuCallbacks get _menuCallbacks'),
        home.indexOf('onFavoritesPressed:'),
      ),
      isNot(contains('BoardEditorScreen')),
    );

    expect(e2e, contains("drawerBoard = 'e2e_drawer_board'"));
    expect(smoke, contains('drawerItemId: E2eIds.drawerBoard'));
    expect(smoke, isNot(contains('drawerOpeningExplorer')));
    expect(smoke, isNot(contains('drawerAnalysisBoard')));
  });
}
