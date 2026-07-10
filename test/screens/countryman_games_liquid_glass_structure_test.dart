import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/countryman_games_screen.dart',
      ).readAsStringSync();

  test('keeps the games list full-screen under floating glass chrome', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('topOverlay:'));
    expect(source, contains('includeContentSafeArea: false'));
    expect(source, contains('widget.topContentInset + 12.sp'));
    expect(source, contains('E2eIds.countrymenRoot'));
    expect(source, contains('E2eIds.countrymenSearchField'));
    expect(source, contains('E2eIds.countrymenSearchToggle'));

    expect(source, isNot(contains('return Scaffold(')));
    expect(source, isNot(contains('SliverAppBar(')));
  });

  test('floating search and actions meet accessibility contracts', () {
    expect(source, contains('MediaQuery.textScalerOf(context).scale(16)'));
    expect(source, contains("label: 'Search countrymen games'"));
    expect(source, contains("label: 'Change games view'"));
    expect(source, contains("label: 'More countrymen game options'"));
    expect(source, contains('size: 48'));
    expect(source, contains('GlassMotion.reduceMotion(context)'));
  });
}
