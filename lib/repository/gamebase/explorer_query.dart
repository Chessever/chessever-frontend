import 'package:dartchess/dartchess.dart';

final _uciPattern = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');
final _playerIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// The board is authoritative. A line is context only when every move is
/// legal from the initial position and reaches that same board.
class GamebaseExplorerPosition {
  const GamebaseExplorerPosition._(this.fen, this.moves);

  final String fen;
  final List<String> moves;

  factory GamebaseExplorerPosition.resolve(String fen, List<String> moves) {
    final target = _positionFromFen(fen);
    final targetFen = target.fen;
    if (moves.isEmpty) {
      return GamebaseExplorerPosition._(targetFen, const []);
    }

    Position position = Chess.initial;
    final replayed = <String>[];
    for (final raw in moves) {
      final uci = raw.trim().toLowerCase();
      final move = _legalMove(position, uci);
      // Discard the entire path, rather than deleting a bad token and
      // accidentally constructing a different history.
      if (move == null) {
        return GamebaseExplorerPosition._(targetFen, const []);
      }
      replayed.add(_standardUci(position, move));
      position = position.play(move);
    }

    if (_positionKey(position.fen) != _positionKey(targetFen)) {
      return GamebaseExplorerPosition._(targetFen, const []);
    }

    // A pasted FEN can carry placeholder or stale counters. Send the counters
    // of the verified line so server reconciliation cannot use a different ply.
    return GamebaseExplorerPosition._(
      position.fen,
      List<String>.unmodifiable(replayed),
    );
  }

  /// A selected continuation belongs to this board, not to the child board.
  /// Invalid selections fail before HTTP; dropping one would broaden results.
  String? continuationUci(String? raw) {
    final uci = raw?.trim().toLowerCase();
    if (uci == null || uci.isEmpty) return null;
    final position = _positionFromFen(fen);
    final move = _legalMove(position, uci);
    if (move == null) {
      throw ArgumentError.value(raw, 'uci', 'Illegal move for explorer FEN');
    }
    return _standardUci(position, move);
  }
}

Position _positionFromFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length == 4) parts.addAll(['0', '1']);
  if (parts.length != 6 ||
      !RegExp(r'^[prnbqkPRNBQK1-8/]+$').hasMatch(parts[0]) ||
      !const ['w', 'b'].contains(parts[1]) ||
      !RegExp(r'^(?:-|[KQkq]+)$').hasMatch(parts[2]) ||
      !RegExp(r'^(?:-|[a-h][36])$').hasMatch(parts[3]) ||
      !RegExp(r'^\d+$').hasMatch(parts[4]) ||
      !RegExp(r'^\d+$').hasMatch(parts[5]) ||
      (int.tryParse(parts[5]) ?? 0) < 1) {
    throw const FormatException('Invalid standard chess FEN for explorer');
  }
  try {
    // Position.fen removes non-capturable en-passant squares, like chess.js.
    return Chess.fromSetup(Setup.parseFen(parts.join(' ')));
  } catch (_) {
    throw const FormatException('Invalid standard chess FEN for explorer');
  }
}

String _positionKey(String fen) => fen.split(' ').take(4).join(' ');

NormalMove? _legalMove(Position position, String uci) {
  if (!_uciPattern.hasMatch(uci)) return null;
  final move = NormalMove.fromUci(uci);
  if (position.isLegal(move)) return move;
  if (position.board.pieceAt(move.from)?.role != Role.king) return null;
  final alternate = alternateGamebaseCastlingUci(uci);
  if (alternate == null) return null;
  final castling = NormalMove.fromUci(alternate);
  return position.isLegal(castling) ? castling : null;
}

/// Bridge classical king-to-target and dartchess king-to-rook castling UCI.
String? alternateGamebaseCastlingUci(String uci) => const <String, String>{
  'e1h1': 'e1g1',
  'e1g1': 'e1h1',
  'e1a1': 'e1c1',
  'e1c1': 'e1a1',
  'e8h8': 'e8g8',
  'e8g8': 'e8h8',
  'e8a8': 'e8c8',
  'e8c8': 'e8a8',
}[uci];

String _standardUci(Position position, NormalMove move) {
  final piece = position.board.pieceAt(move.from);
  if (piece == null || piece.role != Role.king) return move.uci;
  final targetPiece = position.board.pieceAt(move.to);
  final ownRook =
      targetPiece?.role == Role.rook && targetPiece?.color == piece.color;
  if ((move.from.file - move.to.file).abs() < 2 && !ownRook) {
    return move.uci;
  }
  final targetFile = move.to.file > move.from.file ? File.g : File.c;
  return move.from.name + Square.fromCoords(targetFile, move.from.rank).name;
}

/// Preserve all active filters and reject values the API cannot represent.
/// Invalid filters must never disappear and turn into a broader search.
Map<String, dynamic> gamebaseExplorerFilterFields({
  String? timeControl,
  String? playerId,
  String? color,
  String? result,
  int? minRating,
  int? maxRating,
  int? yearFrom,
  int? yearTo,
  bool? isOnline,
}) {
  final player = playerId?.trim().toLowerCase();
  final control = timeControl?.trim().toUpperCase();
  final side = color?.trim().toLowerCase();
  final outcome = result?.trim().toUpperCase();
  if (player != null &&
      player.isNotEmpty &&
      !_playerIdPattern.hasMatch(player)) {
    throw ArgumentError.value(playerId, 'playerId', 'Expected a player UUID');
  }
  if (control != null &&
      !const ['CLASSICAL', 'RAPID', 'BLITZ'].contains(control)) {
    throw ArgumentError.value(
      timeControl,
      'timeControl',
      'Unsupported category',
    );
  }
  if (side != null && !const ['white', 'black'].contains(side)) {
    throw ArgumentError.value(color, 'color', 'Expected white or black');
  }
  if (outcome != null && !const ['W', 'B', 'D'].contains(outcome)) {
    throw ArgumentError.value(result, 'result', 'Expected W, B or D');
  }
  _validateRange('rating', minRating, maxRating);
  _validateRange('year', yearFrom, yearTo);
  return <String, dynamic>{
    if (player != null && player.isNotEmpty) 'playerId': player,
    if (control != null) 'timeControl': control,
    if (side != null) 'color': side,
    if (outcome != null) 'result': outcome,
    if (minRating != null) 'minRating': minRating,
    if (maxRating != null) 'maxRating': maxRating,
    if (yearFrom != null) 'yearFrom': yearFrom,
    if (yearTo != null) 'yearTo': yearTo,
    if (isOnline != null) 'isOnline': isOnline,
  };
}

void _validateRange(String name, int? lower, int? upper) {
  if ((lower != null && lower <= 0) ||
      (upper != null && upper <= 0) ||
      (lower != null && upper != null && lower > upper)) {
    throw ArgumentError('Invalid explorer $name range');
  }
}

Map<String, int> gamebaseExplorerPageFields({
  required int pageNumber,
  required int pageSize,
  required int notationPlies,
}) {
  if (pageNumber < 0 || pageSize < 1 || pageSize > 50 || notationPlies < 0) {
    throw ArgumentError('Invalid explorer pagination or continuation length');
  }
  return <String, int>{
    'pageNumber': pageNumber,
    'pageSize': pageSize,
    if (notationPlies > 0) 'notationPlies': notationPlies.clamp(1, 20),
  };
}
