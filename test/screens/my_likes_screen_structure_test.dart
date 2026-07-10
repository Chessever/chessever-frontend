import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/my_likes/my_likes_screen.dart',
      ).readAsStringSync();

  test('floats likes search and filters over full-screen content', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('GlassIslandStack('));
    expect(source, contains('GlassContainer('));
    expect(source, contains('GlassChip('));
    expect(source, contains('SizedBox(height: topContentInset)'));

    expect(source, isNot(contains('Scaffold(')));
    expect(source, isNot(contains('SliverAppBar(')));
    expect(source, isNot(contains('SliverPersistentHeader(')));
    expect(source, isNot(contains('pinned: true')));
  });

  test('keeps premium export and accessible motion behavior', () {
    expect(source, contains('MediaQuery.textScalerOf(context).scale(16)'));
    expect(source, contains("tooltip: 'Clear search'"));
    expect(source, contains("label: 'Export likes as PGN'"));
    expect(source, contains('size: controlExtent'));
    expect(source, contains('GlassMotion.resolveDuration('));

    expect(source, contains('requirePremiumGuard(context, ref)'));
    expect(source, contains('exportSavedAnalysesAsPgnFiles('));
    expect(source, contains('likedGamesProvider'));
  });
}
