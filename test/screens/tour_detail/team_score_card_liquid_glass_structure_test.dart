import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/tour_detail/team_tour/'
        'team_score_card_screen.dart',
      ).readAsStringSync();

  test('team scorecard has full-screen content and floating controls', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('GlassIslandTopBar('));
    expect(source, contains('GlassContainer('));
    expect(source, contains('SizedBox(height: topContentInset)'));
    expect(source, contains('includeContentSafeArea: false'));

    expect(source, isNot(contains('Scaffold(')));
    expect(source, isNot(contains('SliverAppBar(')));
    expect(source, isNot(contains('SliverPersistentHeader(')));
    expect(source, isNot(contains('pinned: true')));
  });

  test('keeps average Elo, sharing, and 48px dynamic controls', () {
    expect(source, contains('MediaQuery.textScalerOf(context).scale(16)'));
    expect(source, contains("label: 'Share team scorecard'"));
    expect(source, contains(r"label: 'Average Elo $label'"));
    expect(source, contains('size: controlExtent'));
    expect(source, contains('height: controlExtent'));

    expect(source, contains('_shareTeamScorecard('));
    expect(source, contains('TeamRoundGroup('));
    expect(source, contains('teamAvgEloProvider('));
  });
}
