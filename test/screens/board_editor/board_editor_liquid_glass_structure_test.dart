import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/board_editor/'
        'board_editor_screen.dart',
      ).readAsStringSync();

  test('uses a full-screen canvas with floating accessible actions', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('topOverlay:'));
    expect(source, contains('includeContentSafeArea: false'));
    expect(source, contains('GlassButton.custom('));
    expect(source, contains("label: 'Analyze position'"));
    expect(source, contains('minWidth: 48'));
    expect(source, contains('dimension: 48'));
    expect(source, contains('E2eIds.boardEditorRoot'));
    expect(source, contains('E2eIds.boardEditorDoneButton'));

    expect(source, isNot(contains('return Scaffold(')));
    expect(source, isNot(contains('SliverAppBar(')));
  });

  test('respects dynamic text, themes, and reduced motion', () {
    expect(source, contains('MediaQuery.textScalerOf(context).scale(16)'));
    expect(source, contains('GlassMotion.reduceMotion(context)'));
    expect(source, contains('context.colors.background'));
    expect(source, contains('context.colors.textPrimary'));
  });
}
