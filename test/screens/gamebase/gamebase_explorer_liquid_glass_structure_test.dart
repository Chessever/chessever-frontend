import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/gamebase/'
        'gamebase_explorer_screen.dart',
      ).readAsStringSync();

  test('uses floating top, view, and bottom islands without scaffold bars', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('GlassIslandStack('));
    expect(source, contains('topOverlay:'));
    expect(source, contains('bottomOverlay:'));
    expect(source, contains('_buildViewSwitcher(context, controlExtent)'));
    expect(source, contains('_buildBottomControls('));
    expect(source, contains('E2eIds.openingExplorerRoot'));
    expect(source, contains('E2eIds.openingExplorerDoneButton'));

    expect(source, isNot(contains('return Scaffold(')));
    expect(source, isNot(contains('appBar:')));
    expect(source, isNot(contains('bottomNavigationBar:')));
    expect(source, isNot(contains('SliverAppBar(')));
  });

  test('retains interaction contracts and accessible reduced motion', () {
    expect(source, contains("message: 'Filters'"));
    expect(source, contains("label: 'Previous move'"));
    expect(source, contains("label: 'Next move'"));
    expect(source, contains('_ensureExplorerForwardAllowed()'));
    expect(source, contains('_startLongPressBackward'));
    expect(source, contains('_startLongPressForward'));
    expect(source, contains('MediaQuery.textScalerOf(context).scale(16)'));
    expect(source, contains('GlassMotion.reduceMotion(context)'));
    expect(source, contains('GlassMotion.resolveDuration('));
  });
}
