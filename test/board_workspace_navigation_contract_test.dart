import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Profile exposes one Board destination before Rankings and no old '
      'duplicates', () {
    // The sidebar's rows moved to the Profile tab (2026-11-18).
    final profile = File(
      'lib/screens/my_profile/profile_hub_screen.dart',
    ).readAsStringSync();
    final e2e = File('lib/e2e/e2e_ids.dart').readAsStringSync();
    final smoke = File(
      'patrol_test/signed_in_smoke_test.dart',
    ).readAsStringSync();

    expect(profile, isNot(contains('onAnalysisBoardPressed')));
    expect(profile, isNot(contains('onOpeningExplorerPressed')));
    expect(profile, isNot(contains("title: 'Explorer'")));

    final boardIndex = profile.indexOf("title: 'Board'");
    final rankingsIndex = profile.indexOf("title: 'Rankings'");
    expect(boardIndex, greaterThanOrEqualTo(0));
    expect(boardIndex, lessThan(rankingsIndex));

    expect(profile, contains('GamebaseExplorerScreen.scoped()'));
    expect(profile, isNot(contains('BoardEditorScreen')));

    expect(e2e, contains("drawerBoard = 'e2e_drawer_board'"));
    expect(smoke, contains('itemId: E2eIds.drawerBoard'));
    expect(smoke, isNot(contains('drawerOpeningExplorer')));
    expect(smoke, isNot(contains('drawerAnalysisBoard')));
  });
}
