import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/standings/score_card_screen.dart',
      ).readAsStringSync();

  test('scorecard scrolls behind a floating player control row', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('_ScoreboardTopBar('));
    expect(source, contains('SizedBox(height: topContentInset)'));
    expect(source, contains('includeContentSafeArea: false'));

    expect(source, isNot(contains('Scaffold(')));
    expect(source, isNot(contains('SliverAppBar(')));
    expect(source, isNot(contains('SliverPersistentHeader(')));
    expect(source, isNot(contains('pinned: true')));
  });

  test('preserves swipe, share, favorite, and accessibility behavior', () {
    expect(source, contains('MediaQuery.textScalerOf(context).scale(16)'));
    expect(source, contains("label: 'Choose player'"));
    expect(source, contains("label: 'Share player profile'"));
    expect(source, contains('size: widget.controlExtent'));
    expect(source, contains('GlassMotion.reduceMotion(context)'));

    expect(source, contains('onHorizontalDragEnd:'));
    expect(source, contains('requireFullAuthGuard(context)'));
    expect(source, contains('canAddMoreFavorites(context, ref)'));
    expect(source, contains('E2eIds.scorecardRoot'));
  });
}
