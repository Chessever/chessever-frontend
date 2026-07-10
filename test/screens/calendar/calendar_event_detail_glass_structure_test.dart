import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/calendar/'
        'calendar_event_detail_screen.dart',
      ).readAsStringSync();

  test('event detail floats both top and website controls', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('topOverlay: GlassIslandTopBar('));
    expect(source, contains('bottomOverlay: _EventBottomBar('));
    expect(source, contains('GlassContainer('));
    expect(source, contains('GlassIconButton('));
    expect(source, contains('GlassMotion.reduceMotion(context)'));
    expect(source, contains('minHeight: 48'));

    expect(source, isNot(contains('return Scaffold(')));
    expect(source, isNot(contains('appBar:')));
    expect(source, isNot(contains('bottomNavigationBar:')));
  });
}
