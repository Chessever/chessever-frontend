import 'dart:convert';

import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:crypto/crypto.dart';

/// Uses the same categories and PGN/result binding as the Reports filters.
/// Missing, outdated or unknown metadata earns no invented game label.
ReportGameType? feedReportType(Object? metadata, String pgn, String result) {
  if (metadata is! Map ||
      metadata['version'] != 1 ||
      metadata['pgnHash'] != md5.convert(utf8.encode(pgn)).toString() ||
      metadata['result'] != (result == '½-½' ? '1/2-1/2' : result)) {
    return null;
  }
  final tags = metadata['tags'];
  if (tags is! List) return null;
  // Story precedence mirrors the report classifier. Length is a fallback.
  for (final type in const [
    ReportGameType.upsideDown,
    ReportGameType.comeback,
    ReportGameType.greatEscape,
    ReportGameType.oneBlunder,
    ReportGameType.squeeze,
    ReportGameType.domination,
    ReportGameType.deadlock,
    ReportGameType.miniature,
    ReportGameType.marathon,
  ]) {
    if (tags.contains(type.key)) return type;
  }
  return null;
}
