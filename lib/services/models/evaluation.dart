import 'package:chessever2/services/stockfish_evaluator.dart';

/// Represents a single principal variation (PV) line from Lichess cloud-eval.
class PrincipalVariation {
  /// Sequence of SAN moves or move UCI strings.
  final List<String> moves;

  /// Centipawn evaluation, if available.
  final int? cp;

  /// Mate distance in moves, if available.
  final int? mate;

  PrincipalVariation({
    required this.moves,
    this.cp,
    this.mate,
  });

  /// Parses a JSON map into a [PrincipalVariation], handling both
  /// List and whitespace-separated String for moves.
  factory PrincipalVariation.fromJson(Map<String, dynamic> json) {
    final rawMoves = json['moves'];
    final List<String> movesList;
    if (rawMoves is String) {
      // e.g. "e2d1 e4d3 d1e1"
      movesList = rawMoves.split(RegExp(r'\s+'));
    } else if (rawMoves is List) {
      movesList = List<String>.from(rawMoves.cast<String>());
    } else {
      movesList = [];
    }

    return PrincipalVariation(
      moves: movesList,
      cp: json['cp'] is int ? json['cp'] as int : null,
      mate: json['mate'] is int ? json['mate'] as int : null,
    );
  }

  @override
  String toString() {
    if (mate != null) {
      return '#$mate (${moves.join(' ')})';
    } else if (cp != null) {
      final score = (cp! / 100.0).toStringAsFixed(2);
      return '$score (${moves.join(' ')})';
    } else {
      return moves.join(' ');
    }
  }
}

/// Fetches cloud evaluation from Lichess and provides both a string eval
/// and a list of PVs.
class CloudEval {
  /// FEN string to evaluate.
  final String fen;

  /// Number of variations to fetch (multiPv parameter).
  final int multiPv;

  /// Internal cache of the fetched JSON data.
  late final Future<Map<String, dynamic>> _dataFuture;

  CloudEval({
    required this.fen,
    this.multiPv = 3,
  }) {
    // Use the Riverpod provider for the evaluator instead of the singleton
    _dataFuture = LichessCloudEvaluator().fetchData(fen, multiPv);
  }

  /// Returns the top-line evaluation string (e.g. "#3" or "0.45").
  Future<String> get evalString async {
    final data = await _dataFuture;
    final pvsData = data['pvs'];
    if (pvsData is! List || pvsData.isEmpty) return '?';
    final firstPv = pvsData.first;
    if (firstPv is! Map<String, dynamic>) return '?';
    if (firstPv.containsKey('mate')) {
      return '#${firstPv['mate']}';
    } else if (firstPv.containsKey('cp')) {
      final cpValue = firstPv['cp'];
      if (cpValue is int) {
        return (cpValue / 100.0).toStringAsFixed(2);
      }
    }
    return '?';
  }

  /// Returns the list of parsed principal variations.
  Future<List<PrincipalVariation>> get variations async {
    final data = await _dataFuture;
    final pvsData = data['pvs'];
    if (pvsData is! List) return [];
    return pvsData
        .whereType<Map<String, dynamic>>()
        .map(PrincipalVariation.fromJson)
        .toList();
  }
}
