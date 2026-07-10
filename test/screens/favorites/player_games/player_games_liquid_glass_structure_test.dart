import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/favorites/player_games/'
        'player_games_screen.dart',
      ).readAsStringSync();

  test('renders player games on one full-screen canvas', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('topOverlay:'));
    expect(source, contains('includeContentSafeArea: false'));
    expect(source, contains('top: topContentInset + 8.h'));
    expect(source, contains('edgeOffset: topContentInset'));

    expect(source, isNot(contains('return Scaffold(')));
    expect(source, isNot(contains('SliverAppBar(')));
  });

  test('title island supports text scaling and a 48 point back target', () {
    expect(source, contains('MediaQuery.textScalerOf(context).scale(16)'));
    expect(source, contains('height: controlExtent'));
    expect(source, contains('const GlassBackButton()'));
  });
}
