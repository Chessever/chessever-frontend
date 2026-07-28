const pgnHeaderOrder = <String>[
  'Event',
  'Site',
  'Date',
  'Round',
  'White',
  'Black',
  'Result',
  'WhiteElo',
  'BlackElo',
  'WhiteTitle',
  'BlackTitle',
  'WhiteFideId',
  'BlackFideId',
  'ECO',
  'Opening',
  'EventDate',
];

const pgnSevenTagDefaults = <String, String>{
  'Event': '?',
  'Site': '?',
  'Date': '????.??.??',
  'Round': '?',
  'White': '?',
  'Black': '?',
  'Result': '*',
};

const internalPgnMetadataKeys = <String>{
  'allowMainlineExtension',
  'isLiveGame',
  'gameEndingPlyIndex',
};

/// Returns user-facing PGN headers in deterministic interchange order.
///
/// The Seven Tag Roster is always present first. Public source metadata is
/// retained, while ChessEver runtime/editing fields are omitted.
Map<String, String> canonicalPgnHeaders(Map<String, String> source) {
  final headers = <String, String>{};
  for (final entry in source.entries) {
    final key = entry.key.trim();
    if (key.isEmpty || internalPgnMetadataKeys.contains(key)) continue;
    headers[key] = entry.value;
  }

  for (final entry in pgnSevenTagDefaults.entries) {
    final current = headers[entry.key]?.trim();
    if (current == null || current.isEmpty) {
      headers[entry.key] = entry.value;
    }
  }

  final ordered = <String, String>{};
  for (final key in pgnHeaderOrder) {
    final value = headers[key];
    if (value != null) ordered[key] = value;
  }

  final remaining =
      headers.keys.where((key) => !ordered.containsKey(key)).toList()..sort();
  for (final key in remaining) {
    ordered[key] = headers[key]!;
  }
  return ordered;
}

/// Rewrites only the PGN tag-pair section and preserves movetext verbatim.
///
/// This lets clipboard/share exports follow the same standard order as
/// Lichess without dropping clock/evaluation comments, NAGs, or variations.
String canonicalizePgnForExport(String rawPgn) {
  final normalized = rawPgn.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final headers = <String, String>{};
  var movetextStart = lines.length;
  var sawHeader = false;
  final tagPattern = RegExp(r'^\[([^\s\]]+)\s+"((?:\\.|[^"\\])*)"\]\s*$');

  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    if (trimmed.isEmpty) continue;
    final match = tagPattern.firstMatch(trimmed);
    if (match != null) {
      sawHeader = true;
      headers[match.group(1)!] = match.group(2)!;
      continue;
    }
    movetextStart = i;
    break;
  }

  if (!sawHeader && normalized.trim().isEmpty) return '';

  final movetext =
      movetextStart < lines.length
          ? lines.sublist(movetextStart).join('\n').trim()
          : '';
  final output = StringBuffer();
  for (final entry in canonicalPgnHeaders(headers).entries) {
    output.writeln('[${entry.key} "${entry.value}"]');
  }
  if (movetext.isNotEmpty) {
    output.writeln();
    output.write(movetext);
  }
  return output.toString().trimRight();
}
