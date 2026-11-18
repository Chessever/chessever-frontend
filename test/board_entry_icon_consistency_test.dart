import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Library and database use the single shared Board entry icon', () {
    final icon = File(
      'lib/widgets/board_navigation_icon.dart',
    ).readAsStringSync();
    // The sidebar drawer is gone; its Board entry lives on the Profile tab.
    final profileHub = File(
      'lib/screens/my_profile/profile_hub_screen.dart',
    ).readAsStringSync();
    final library = File(
      'lib/screens/library/library_screen.dart',
    ).readAsStringSync();
    final database = File(
      'lib/screens/library/folder_contents_screen.dart',
    ).readAsStringSync();
    final e2e = File('lib/e2e/e2e_ids.dart').readAsStringSync();
    final smoke = File('patrol_test/signed_in_smoke_test.dart').readAsStringSync();

    expect(icon, contains('class BoardNavigationIcon'));
    expect(icon, contains('SvgAsset.analysisBoard'));
    expect(icon, contains('preserveOriginalColors: true'));

    expect(profileHub, contains('BoardNavigationIcon'));
    expect(profileHub, contains('E2eIds.drawerBoard'));
    expect(profileHub, contains("title: 'Board'"));
    expect(profileHub, contains('requireFullAuthGuard(context)'));
    expect(profileHub, contains('GamebaseExplorerScreen.scoped()'));
    expect(library, contains('BoardNavigationIcon'));
    expect(database, contains('BoardNavigationIcon'));

    expect(library, isNot(contains('Icons.explore_outlined')));
    expect(library, isNot(contains('SvgAsset.boardSettings')));
    expect(library, isNot(contains('_OpeningExplorerButton')));
    expect(library, isNot(contains('_BoardSettingsButton')));
    expect(library, contains('E2eIds.libraryBoardButton'));
    expect(library, contains('GamebaseExplorerScreen.scoped()'));

    expect(database, contains('if (_isDatabase)'));
    expect(database, contains('E2eIds.databaseBoardButton'));
    expect(database, contains("tooltip: 'Open Board'"));
    expect(database, contains('GamebaseExplorerScreen.scoped()'));

    expect(e2e, contains('libraryBoardButton'));
    expect(e2e, contains('databaseBoardButton'));
    expect(e2e, isNot(contains('libraryOpeningExplorerButton')));
    expect(e2e, isNot(contains('libraryBoardEditorButton')));
    expect(smoke, contains('E2eIds.libraryBoardButton'));
  });
}
