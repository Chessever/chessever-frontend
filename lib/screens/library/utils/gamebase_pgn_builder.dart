import 'package:dartchess/dartchess.dart';

const _defaultStartingFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Builds a PGN string from Gamebase `data` payloads.
///
/// Gamebase game payloads commonly look like:
/// - `sf`: starting FEN
/// - `md`: metadata (PGN headers)
/// - `m`: list of moves (usually UCI under `u`)
///
/// Returns `null` if the payload doesn't include enough information.
String? buildPgnFromGamebaseData(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return null;

  final mdRaw = data['md'] ?? data['metadata'];
  if (mdRaw is! Map) return null;
  final md = Map<String, dynamic>.from(mdRaw);

  final movesRaw = data['m'] ?? data['moves'];
  if (movesRaw is! List || movesRaw.isEmpty) return null;

  final startingFen = (data['sf'] as String?)?.trim();
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
      final uci =
          item is Map
              ? (item['u'] ?? item['uci'])?.toString()
              : item?.toString();
      if (uci == null) continue;
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
  } catch (_) {
    return null;
  }

  if (sans.isEmpty) return null;

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
