import 'dart:convert';
import 'dart:typed_data';

import 'package:dartchess/dartchess.dart';

/// How deep a device-built opening tree reaches, as the server's trees do.
const int kGameTreeMaxPly = 24;

/// Bumped whenever the on-disk layout or what is indexed changes; an index
/// written by another version is rebuilt from its PGN sources.
const int kGameTreeSchemaVersion = 2;

/// The first four FEN fields: what identifies a position in the tree.
String gameTreeFenKey(String fen) =>
    fen.trim().split(RegExp(r'\s+')).take(4).join(' ');

/// A 64-bit FNV-1a hash of a [gameTreeFenKey]. Collisions across a million
/// positions are about one in ten million, and a collision only merges two
/// positions' statistics, so a numeric key is worth it: it is 8 bytes on
/// disk where the FEN is ~60.
int gameTreeFenHash(String fenKey) {
  var hash = -3750763034362895579; // 0xcbf29ce484222325
  for (var i = 0; i < fenKey.length; i++) {
    hash ^= fenKey.codeUnitAt(i);
    hash *= 1099511628211; // 0x100000001b3, wraps at 64 bits
  }
  return hash;
}

/// The hash of the position a FEN describes.
int gameTreeHashOfFen(String fen) => gameTreeFenHash(gameTreeFenKey(fen));

/// The start position's hash, the root of every tree.
final int kGameTreeRootHash = gameTreeHashOfFen(kInitialFEN);

// ------------------------------------------------------------------ moves

const _promotions = ['', 'q', 'r', 'b', 'n'];

/// A UCI move as a small integer: from | to << 6 | promotion << 12. Zero is
/// never a move (a1a1), so it stands for "no move" (a game's last tree ply).
int encodeTreeMove(String uci) {
  if (uci.length < 4) return 0;
  int square(int file, int rank) =>
      (file - 0x61) + (rank - 0x31) * 8; // 'a' and '1'
  final from = square(uci.codeUnitAt(0), uci.codeUnitAt(1));
  final to = square(uci.codeUnitAt(2), uci.codeUnitAt(3));
  if (from < 0 || from > 63 || to < 0 || to > 63) return 0;
  final promo = uci.length > 4 ? _promotions.indexOf(uci[4].toLowerCase()) : 0;
  return from | to << 6 | (promo < 0 ? 0 : promo) << 12;
}

String decodeTreeMove(int code) {
  if (code <= 0) return '';
  String square(int s) =>
      '${String.fromCharCode(0x61 + s % 8)}${String.fromCharCode(0x31 + s ~/ 8)}';
  final promo = (code >> 12) & 7;
  return '${square(code & 63)}${square((code >> 6) & 63)}'
      '${promo < _promotions.length ? _promotions[promo] : ''}';
}

/// Castling written king-to-destination, as the server's trees write it.
String standardTreeUci(Position position, Move move) {
  if (move is NormalMove) {
    final piece = position.board.pieceAt(move.from);
    if (piece?.role == Role.king) {
      final castle = switch ('${move.from.name}${move.to.name}') {
        'e1h1' => 'e1g1',
        'e1a1' => 'e1c1',
        'e8h8' => 'e8g8',
        'e8a8' => 'e8c8',
        _ => null,
      };
      if (castle != null) return castle;
    }
  }
  return move.uci;
}

// ------------------------------------------------------------------ buckets

/// The explorer filters a tree move by side and clock. Each move's counts
/// are kept per (side, clock) bucket: side 0 none / 1 white / 2 black,
/// clock 0 none / 1 blitz / 2 rapid / 3 classical.
int treeBucket({required int side, required int clock}) => side * 4 + clock;

String? treeBucketColor(int bucket) => switch (bucket ~/ 4) {
  1 => 'white',
  2 => 'black',
  _ => null,
};

String? treeBucketClock(int bucket) => switch (bucket % 4) {
  1 => 'blitz',
  2 => 'rapid',
  3 => 'classical',
  _ => null,
};

/// Clock categories by index, matching `PrepTimeControl`'s order.
abstract final class TreeSpeed {
  static const ultrabullet = 0;
  static const bullet = 1;
  static const blitz = 2;
  static const rapid = 3;
  static const classical = 4;
  static const correspondence = 5;

  /// The explorer's three clock filters, which fold the fast and slow ends
  /// in: 1 blitz, 2 rapid, 3 classical, 0 unknown.
  static int explorerClock(int? speed) => switch (speed) {
    ultrabullet || bullet || blitz => 1,
    rapid => 2,
    classical || correspondence => 3,
    _ => 0,
  };
}

/// The clock category of a game. Chess.com's own TimeClass is
/// authoritative; otherwise the estimated-duration bands Lichess uses.
int? classifyTreeSpeed({
  required bool lichess,
  String? timeControl,
  String? timeClass,
}) {
  switch (timeClass?.toLowerCase()) {
    case 'bullet':
      return TreeSpeed.bullet;
    case 'blitz':
      return TreeSpeed.blitz;
    case 'rapid':
      return TreeSpeed.rapid;
    case 'daily':
      return TreeSpeed.correspondence;
  }
  final tc = timeControl?.trim();
  if (tc == null || tc.isEmpty || tc == '?') return null;
  if (tc == '-' || tc.contains('/')) return TreeSpeed.correspondence;
  final parts = tc.split('+');
  final base = int.tryParse(parts.first);
  if (base == null) return null;
  final inc = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final estimate = base + 40 * inc;
  if (lichess && estimate < 30) return TreeSpeed.ultrabullet;
  if (estimate < 180) return TreeSpeed.bullet;
  if (estimate < 480) return TreeSpeed.blitz;
  if (estimate < 1500) return TreeSpeed.rapid;
  return TreeSpeed.classical;
}

// ------------------------------------------------------------------ dates

/// A PGN date (`2026.09.01`) as yyyymmdd, which sorts like the date.
int? treeDateOf(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^(\d{4})\.(\d{2}|\?\?)\.(\d{2}|\?\?)').firstMatch(raw);
  if (m == null) return null;
  final year = int.parse(m.group(1)!);
  if (year < 1800) return null;
  final month = (int.tryParse(m.group(2)!) ?? 1).clamp(1, 12);
  final day = (int.tryParse(m.group(3)!) ?? 1).clamp(1, 31);
  return year * 10000 + month * 100 + day;
}

DateTime? treeDateTime(int? yyyymmdd) {
  if (yyyymmdd == null || yyyymmdd <= 0) return null;
  return DateTime.utc(
    yyyymmdd ~/ 10000,
    (yyyymmdd ~/ 100) % 100,
    yyyymmdd % 100,
  );
}

/// A PGN time (`14:05:09`) as HHMMSS, 0 when absent.
int treeTimeOf(String? raw) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(raw ?? '');
  if (m == null) return 0;
  final h = int.parse(m.group(1)!).clamp(0, 23);
  final min = int.parse(m.group(2)!).clamp(0, 59);
  final s = int.tryParse(m.group(3) ?? '')?.clamp(0, 59) ?? 0;
  return h * 10000 + min * 100 + s;
}

/// Results as stored: 0 white won, 1 black won, 2 drawn, 3 unknown.
int treeResultCode(String? result) => switch (result?.trim()) {
  '1-0' => 0,
  '0-1' => 1,
  '1/2-1/2' => 2,
  _ => 3,
};

String treeResultText(int code) => switch (code) {
  0 => '1-0',
  1 => '0-1',
  2 => '1/2-1/2',
  _ => '*',
};

// ------------------------------------------------------------------ PGN

/// One game's headers and the start of its main line, read without
/// building a move tree.
class PgnScan {
  const PgnScan({
    required this.headers,
    required this.sans,
    required this.plies,
  });

  final Map<String, String> headers;

  /// The first main-line moves (up to the scan's limit), as written.
  final List<String> sans;

  /// How many main-line moves the game has in total.
  final int plies;

  String? tag(String key) {
    final value = headers[key]?.trim();
    return value == null || value.isEmpty || value == '?' ? null : value;
  }
}

final RegExp _headerLine = RegExp(r'^\[(\w+)\s+"((?:[^"\\]|\\.)*)"\s*\]');
final RegExp _moveNumber = RegExp(r'^\d+\.+');

/// Reads [pgn]'s headers and main line, skipping comments, variations,
/// NAGs and move numbers. Much cheaper than a full PGN parse, which builds
/// every variation and comment just to be thrown away.
PgnScan scanPgnGame(String pgn, {int sanLimit = kGameTreeMaxPly}) {
  final headers = <String, String>{};
  var i = 0;
  final n = pgn.length;
  // Headers: leading `[Key "Value"]` lines.
  while (i < n) {
    var lineEnd = pgn.indexOf('\n', i);
    if (lineEnd < 0) lineEnd = n;
    final line = pgn.substring(i, lineEnd).trim();
    if (line.isEmpty) {
      i = lineEnd + 1;
      if (headers.isEmpty) continue;
      break;
    }
    if (!line.startsWith('[')) break;
    final m = _headerLine.firstMatch(line);
    if (m != null) {
      headers[m.group(1)!] = m.group(2)!.replaceAll(r'\"', '"');
    }
    i = lineEnd + 1;
  }

  final sans = <String>[];
  var plies = 0;
  var depth = 0;
  while (i < n) {
    final c = pgn.codeUnitAt(i);
    if (c == 0x7B) {
      // { comment }
      final end = pgn.indexOf('}', i + 1);
      i = end < 0 ? n : end + 1;
      continue;
    }
    if (c == 0x3B) {
      // ; comment to end of line
      final end = pgn.indexOf('\n', i + 1);
      i = end < 0 ? n : end + 1;
      continue;
    }
    if (c == 0x28) {
      depth++;
      i++;
      continue;
    }
    if (c == 0x29) {
      if (depth > 0) depth--;
      i++;
      continue;
    }
    if (c <= 0x20) {
      i++;
      continue;
    }
    // A token runs to whitespace or a structural character.
    var j = i;
    while (j < n) {
      final d = pgn.codeUnitAt(j);
      if (d <= 0x20 || d == 0x7B || d == 0x28 || d == 0x29 || d == 0x3B) {
        break;
      }
      j++;
    }
    var token = pgn.substring(i, j);
    i = j;
    if (depth > 0) continue;
    if (token.startsWith(r'$')) continue;
    if (token == '1-0' || token == '0-1' || token == '1/2-1/2' || token == '*') {
      break;
    }
    token = token.replaceFirst(_moveNumber, '');
    if (token.isEmpty) continue;
    // Strip move annotations; keep check marks, which parsing accepts.
    while (token.isNotEmpty &&
        (token.endsWith('!') || token.endsWith('?'))) {
      token = token.substring(0, token.length - 1);
    }
    if (token.isEmpty) continue;
    if (token.startsWith('0-0')) token = token.replaceAll('0', 'O');
    plies++;
    if (sans.length < sanLimit) sans.add(token);
  }
  return PgnScan(headers: headers, sans: sans, plies: plies);
}

/// A provider game's stable identity: its Lichess or Chess.com URL.
String? treeGameKey(Map<String, String> headers) {
  for (final key in const ['Link', 'Site']) {
    final url = headers[key];
    if (url != null &&
        (url.contains('lichess.org/') || url.contains('chess.com/'))) {
      return url.trim();
    }
  }
  return null;
}

/// Where each game starts in a PGN byte buffer: at every `[Event ` tag that
/// opens a line. [from] skips a prefix already accounted for.
List<int> pgnGameStarts(Uint8List bytes, {int from = 0}) {
  const pattern = [0x5B, 0x45, 0x76, 0x65, 0x6E, 0x74]; // "[Event"
  final starts = <int>[];
  final last = bytes.length - pattern.length - 1;
  for (var i = from; i <= last; i++) {
    if (bytes[i] != 0x5B) continue;
    if (i > 0 && bytes[i - 1] != 0x0A) continue;
    // Match the whole tag name. EventDate/EventType belong to this game's
    // headers; splitting there loses the player names and result above them.
    final separator = bytes[i + pattern.length];
    if (separator != 0x20 && separator != 0x09) continue;
    var match = true;
    for (var k = 1; k < pattern.length; k++) {
      if (bytes[i + k] != pattern[k]) {
        match = false;
        break;
      }
    }
    if (match) starts.add(i);
  }
  return starts;
}

/// Decodes one game's bytes, tolerating a stray invalid sequence.
String decodePgnBytes(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true).replaceAll('\r\n', '\n').trim();
