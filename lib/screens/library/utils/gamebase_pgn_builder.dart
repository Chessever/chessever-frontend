import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

const _defaultStartingFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Builds a PGN string from Gamebase `data` payloads.
///
/// Gamebase game payloads commonly look like:
/// - `sf`: starting FEN
/// - `md`: metadata (PGN headers)
/// - `m`: list of moves (usually UCI under `u`)
///
/// Also supports alternative formats:
/// - `moves`: array of move objects or strings
/// - `metadata`: PGN headers map
/// - Direct UCI strings in array
///
/// Returns `null` if the payload doesn't include enough information.
String? buildPgnFromGamebaseData(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) {
    if (kDebugMode) {
      debugPrint('[GamebasePgnBuilder] data is null or empty');
    }
    return null;
  }

  if (kDebugMode) {
    debugPrint('[GamebasePgnBuilder] data keys: ${data.keys.toList()}');
  }

  // Try to extract metadata from various possible locations
  final mdRaw = data['md'] ?? data['metadata'] ?? data['headers'];
  Map<String, dynamic> md = {};
  if (mdRaw is Map) {
    md = Map<String, dynamic>.from(mdRaw);
  }

  // Try to extract moves from various possible locations
  final movesRaw = data['m'] ?? data['moves'] ?? data['moveList'];

  if (kDebugMode) {
    debugPrint(
      '[GamebasePgnBuilder] movesRaw type: ${movesRaw?.runtimeType}, isEmpty: ${movesRaw is List ? movesRaw.isEmpty : 'N/A'}',
    );
    if (movesRaw is List && movesRaw.isNotEmpty) {
      debugPrint('[GamebasePgnBuilder] first move sample: ${movesRaw.first}');
    }
  }

  if (movesRaw is! List || movesRaw.isEmpty) {
    if (kDebugMode) {
      debugPrint('[GamebasePgnBuilder] No moves found in data');
    }
    return null;
  }

  final startingFen =
      (data['sf'] ?? data['fen'] ?? data['startFen'] as String?)?.trim();
  final effectiveFen =
      (startingFen != null && startingFen.isNotEmpty)
          ? startingFen
          : _defaultStartingFen;

  final headers = <String, String>{};
  for (final entry in md.entries) {
    final key = entry.key.toString().trim();
    if (key.isEmpty) continue;
    final value = (entry.value?.toString() ?? '').trim();
    if (value.isEmpty) continue;
    headers[key] = value;
  }

  headers['Result'] = _normalizePgnResult(headers['Result']);

  if (effectiveFen != _defaultStartingFen) {
    headers.putIfAbsent('FEN', () => effectiveFen);
    headers.putIfAbsent('SetUp', () => '1');
  }

  final sans = <String>[];
  try {
    final setup = Setup.parseFen(effectiveFen);
    Position position = Chess.fromSetup(setup);

    for (final item in movesRaw) {
      // Support multiple move formats:
      // 1. Map with 'u' or 'uci' key: {u: "e2e4"} or {uci: "e2e4"}
      // 2. Map with 'san' key: {san: "e4"}
      // 3. Plain string UCI: "e2e4"
      // 4. Plain string SAN: "e4"
      String? uci;
      String? san;

      if (item is Map) {
        uci = (item['u'] ?? item['uci'])?.toString();
        san = item['san']?.toString();
      } else if (item is String) {
        // Could be UCI or SAN - UCI is 4+ chars with square names
        final trimmed = item.trim();
        if (trimmed.length >= 4 && _looksLikeUci(trimmed)) {
          uci = trimmed;
        } else {
          san = trimmed;
        }
      }

      // If we have SAN directly, use it
      if (san != null && san.isNotEmpty) {
        final move = position.parseSan(san);
        if (move != null) {
          position = position.play(move);
          sans.add(san);
          continue;
        }
      }

      // Otherwise parse UCI
      if (uci == null || uci.isEmpty) continue;
      final trimmed = uci.trim();
      if (trimmed.length < 4) continue;

      final from = Square.fromName(trimmed.substring(0, 2));
      final to = Square.fromName(trimmed.substring(2, 4));
      Role? promotion;
      if (trimmed.length > 4) {
        promotion = Role.fromChar(trimmed[4]);
      }

      final move = NormalMove(from: from, to: to, promotion: promotion);
      final result = position.makeSan(move);
      position = result.$1;
      sans.add(result.$2);
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[GamebasePgnBuilder] Error parsing moves: $e');
    }
    return null;
  }

  if (sans.isEmpty) {
    if (kDebugMode) {
      debugPrint('[GamebasePgnBuilder] No valid moves parsed');
    }
    return null;
  }

  if (kDebugMode) {
    debugPrint('[GamebasePgnBuilder] Successfully parsed ${sans.length} moves');
  }

  final sb = StringBuffer();
  for (final entry in headers.entries) {
    sb.writeln('[${entry.key} "${entry.value}"]');
  }
  sb.writeln();

  for (var i = 0; i < sans.length; i++) {
    if (i.isEven) {
      final moveNo = (i ~/ 2) + 1;
      sb.write('$moveNo. ');
    }
    sb.write('${sans[i]} ');
  }

  sb.write(headers['Result'] ?? '*');

  return sb.toString().trim();
}

/// Checks if a string looks like a UCI move (e.g., "e2e4", "e7e8q")
bool _looksLikeUci(String s) {
  if (s.length < 4) return false;
  // Check if first two chars are a valid square (a-h + 1-8)
  final file1 = s[0].toLowerCase();
  final rank1 = s[1];
  final file2 = s[2].toLowerCase();
  final rank2 = s[3];
  return file1.compareTo('a') >= 0 &&
      file1.compareTo('h') <= 0 &&
      rank1.compareTo('1') >= 0 &&
      rank1.compareTo('8') <= 0 &&
      file2.compareTo('a') >= 0 &&
      file2.compareTo('h') <= 0 &&
      rank2.compareTo('1') >= 0 &&
      rank2.compareTo('8') <= 0;
}

/// Builds a minimal PGN (headers + result only) for cases where we don't have
/// the move list available (e.g. Gamebase search previews).
///
/// This prevents the board from attempting Supabase PGN lookups (which can
/// show confusing "No rows found" errors) and still preserves the correct
/// player/event context for the user.
String buildHeaderOnlyPgn({
  required String whiteName,
  required String blackName,
  required String result,
  String? event,
  String? site,
  DateTime? date,
  String? eco,
  String? opening,
  String? variation,
  String? fen,
}) {
  final normalizedResult = _normalizePgnResult(result);
  final headers = <String, String>{
    'White': whiteName.trim().isEmpty ? 'White' : whiteName.trim(),
    'Black': blackName.trim().isEmpty ? 'Black' : blackName.trim(),
    'Result': normalizedResult,
  };

  final eventTrim = (event ?? '').trim();
  if (eventTrim.isNotEmpty) headers['Event'] = eventTrim;

  final siteTrim = (site ?? '').trim();
  if (siteTrim.isNotEmpty) headers['Site'] = siteTrim;

  if (date != null) {
    headers['Date'] =
        '${date.year.toString().padLeft(4, '0')}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }

  final ecoTrim = (eco ?? '').trim();
  if (ecoTrim.isNotEmpty) headers['ECO'] = ecoTrim;

  final openingTrim = (opening ?? '').trim();
  if (openingTrim.isNotEmpty) headers['Opening'] = openingTrim;

  final variationTrim = (variation ?? '').trim();
  if (variationTrim.isNotEmpty) headers['Variation'] = variationTrim;

  final fenTrim = (fen ?? '').trim();
  if (fenTrim.isNotEmpty && fenTrim != _defaultStartingFen) {
    headers['FEN'] = fenTrim;
    headers['SetUp'] = '1';
  }

  final sb = StringBuffer();
  for (final entry in headers.entries) {
    sb.writeln('[${entry.key} "${entry.value}"]');
  }
  sb.writeln();
  sb.write(normalizedResult);
  return sb.toString();
}

/// Returns `true` if the given PGN contains actual moves (not just headers).
///
/// Header-only PGNs (like those generated by `buildHeaderOnlyPgn`) contain
/// only tag pairs and a result termination marker (e.g. "*", "1-0").
/// This function checks if there's at least one move number (e.g. "1.") which
/// indicates real move content.
bool pgnHasMoves(String? pgn) {
  if (pgn == null || pgn.trim().isEmpty) return false;

  // Collect movetext lines: everything that isn't a PGN header ([Key "Value"])
  // or a blank line. Handles three formats:
  //   1. Standard PGN (headers + blank line + movetext)
  //   2. No blank-line separator (headers immediately followed by movetext)
  //   3. Movetext-only (no headers at all)
  final lines = pgn.split('\n');
  final movetextLines = <String>[];

  bool inHeaders = true;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      if (inHeaders) inHeaders = false; // blank line after headers
      continue;
    }
    if (inHeaders && trimmed.startsWith('[')) {
      continue; // still in headers
    }
    // Any non-header, non-empty line is movetext
    inHeaders = false;
    movetextLines.add(trimmed);
  }

  final movetext = movetextLines.join(' ').trim();
  if (movetext.isEmpty) return false;

  // Check if movetext is just a result marker
  final resultOnly = RegExp(r'^(1-0|0-1|1/2-1/2|\*)$');
  if (resultOnly.hasMatch(movetext)) return false;

  // Check for at least one move number (e.g., "1." or "1...")
  final hasMoveNumber = RegExp(r'\d+\.');
  return hasMoveNumber.hasMatch(movetext);
}

String _normalizePgnResult(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return '*';

  final upper = trimmed.toUpperCase();
  switch (upper) {
    case '1-0':
      return '1-0';
    case '0-1':
      return '0-1';
    case '1/2-1/2':
    case '½-½':
    case '0.5-0.5':
      return '1/2-1/2';
    case '*':
      return '*';
    case 'W':
      return '1-0';
    case 'B':
      return '0-1';
    case 'D':
    case 'DRAW':
      return '1/2-1/2';
    default:
      return '*';
  }
}
