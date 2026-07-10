import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/premium_games/'
        'premium_games_screen.dart',
      ).readAsStringSync();

  test('uses an overlay island instead of a fixed app bar', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('topOverlay: Align('));
    expect(source, contains('edgeOffset: topContentInset'));
    expect(source, contains('topContentInset'));

    expect(source, isNot(contains('Scaffold(')));
    expect(source, isNot(contains('SliverAppBar(')));
    expect(source, isNot(contains('appBar:')));
    expect(source, isNot(contains('pinned: true')));
  });

  test('retains paging, filters, e2e ids, and motion policy', () {
    expect(source, contains('MediaQuery.textScalerOf(context).scale(16)'));
    expect(source, contains('size: controlExtent'));
    expect(source, contains('GlassMotion.resolveDuration('));
    expect(source, contains('E2eIds.premiumGamesRoot'));
    expect(source, contains('E2eIds.premiumGamesFilterButton'));

    expect(source, contains('.loadMore()'));
    expect(source, contains('showPremiumGamesFilterDialog('));
    expect(source, contains('TwicGameCard('));
  });
}
