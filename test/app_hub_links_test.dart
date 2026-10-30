import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/for_you/discovery/reports_share.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_share.dart';
import 'package:chessever2/services/app_destination.dart';
import 'package:flutter_test/flutter_test.dart';

/// chessever_web_frontend answers these same addresses with web pages and
/// mirrors this fixture; change and test both copies.
void main() {
  final fixtures =
      jsonDecode(File('test/fixtures/app-hub-links.json').readAsStringSync())
          as List;
  for (final fixture in fixtures) {
    final hub = fixture['hub'] as String;
    final section = fixture['section'] as String;
    final date = fixture['date'] as String?;
    final path = fixture['path'] as String;
    test('native and web share contract: $path', () {
      final uri = hub == 'miniatures'
          ? miniaturesShareUri(
              MiniaturesScreenMode.values.byName(section),
              date: date,
            )
          : reportsShareUri(
              section == 'all'
                  ? null
                  : ReportGameType.values.firstWhere(
                      (type) => type.key == section,
                    ),
              date: date,
            );
      expect(uri.toString(), 'https://chessever.com$path');
      for (final raw in [
        'https://chessever.com$path',
        'https://www.chessever.com$path',
        path,
        'com.chessever.app:/$path',
      ]) {
        final target = parseAppDestination(raw);
        expect(
          target?.kind,
          hub == 'miniatures'
              ? AppDestinationKind.miniatures
              : AppDestinationKind.reports,
          reason: raw,
        );
        expect(target?.section, section, reason: raw);
        expect(target?.query['date'], date, reason: raw);
      }
    });
  }

  test('the shared fixture covers every report type', () {
    final shared = fixtures
        .where((fixture) => fixture['hub'] == 'reports')
        .map((fixture) => fixture['section'])
        .toSet();
    expect(shared, {'all', ...ReportGameType.values.map((type) => type.key)});
  });
}
