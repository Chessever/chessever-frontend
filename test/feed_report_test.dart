import 'dart:convert';

import 'package:chessever2/screens/chessboard/game_review/saved_game_report.dart';
import 'package:chessever2/screens/feed/logic/feed_moments.dart';
import 'package:chessever2/screens/feed/logic/feed_report.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _pgn = '[Result "1-0"]\n\n1. e4 \$242 {[%eval 0.3]} e5 1-0';

Map<String, Object?> _metadata(List<String> tags) => {
  'version': 1,
  'result': '1-0',
  'tags': tags,
  'pgnHash': md5.convert(utf8.encode(_pgn)).toString(),
};

void main() {
  test('Feed labels use Reports categories and story precedence', () {
    expect(
      feedReportType(_metadata(['miniature', 'comeback']), _pgn, '1-0'),
      ReportGameType.comeback,
    );
    expect(
      feedReportType(
        _metadata(['comeback', 'upside_down', 'miniature']),
        _pgn,
        '1-0',
      ),
      ReportGameType.upsideDown,
    );
    expect(
      feedReportType(_metadata(['miniature']), _pgn, '1-0'),
      ReportGameType.miniature,
    );
  });

  test(
    'missing, stale, unsupported and rating-gap labels earn no category',
    () {
      for (final metadata in [
        null,
        _metadata(['upset']),
        {
          ..._metadata(['comeback']),
          'version': 2,
        },
        {
          ..._metadata(['comeback']),
          'pgnHash': 'old',
        },
        {
          ..._metadata(['comeback']),
          'result': '0-1',
        },
        {
          ..._metadata(['comeback']),
          'tags': 'comeback',
        },
      ]) {
        expect(feedReportType(metadata, _pgn, '1-0'), isNull);
      }
      expect(feedReportType(_metadata(['comeback']), '$_pgn\n', '1-0'), isNull);
    },
  );

  test('draw results share the database normalization', () {
    expect(
      feedReportType(
        {
          ..._metadata(['great_escape']),
          'result': '1/2-1/2',
        },
        _pgn,
        '½-½',
      ),
      ReportGameType.greatEscape,
    );
  });

  test('Reports and Feed agree on genuine mainline report evidence', () {
    for (final (pgn, expected) in [
      (_pgn, true),
      (_pgn.replaceFirst(r'$242', r'$1'), false),
      (_pgn.replaceFirst('{[%eval 0.3]}', ''), false),
      ('[Result "1-0"]\n\n1. e4 {[%eval 0.3]} e5 \$242 1-0', false),
      ('[Result "1-0"]\n\n1. e4 (1. d4 \$242 {[%eval 0.3]}) e5 1-0', false),
      ('[Result "1-0"]\n\n1. e4 {literal \$242 [%eval 0.3]} e5 1-0', false),
      ('$_pgn\n\n$_pgn', false),
    ]) {
      expect(hasSavedGameReport(pgn), expected, reason: pgn);
      expect(feedClipFromPgn(pgn)?.hasReport, expected, reason: pgn);
    }
  });
}
