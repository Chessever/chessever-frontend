import 'package:chessever2/repository/models/evaluation.dart';
import 'package:flutter/foundation.dart';

@immutable
class GameUser {
  final String id;
  final String name;

  const GameUser({required this.id, required this.name});

  factory GameUser.fromJson(Map<String, dynamic> json) {
    return GameUser(
      id: (json['id'] as String?) ?? 'unknown_id',
      name: (json['name'] as String?) ?? 'Anonymous',
    );
  }
}

@immutable
class Player {
  final GameUser user;
  final int? rating;
  final int? ratingDiff;

  const Player({required this.user, this.rating, this.ratingDiff});

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      user: GameUser.fromJson(
        (json['user'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      ),
      rating: json['rating'] as int?,
      ratingDiff: json['ratingDiff'] as int?,
    );
  }
}

@immutable
class GamePlayers {
  final Player white;
  final Player black;

  const GamePlayers({required this.white, required this.black});

  factory GamePlayers.fromJson(Map<String, dynamic> json) {
    return GamePlayers(
      white: Player.fromJson(
        (json['white'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      ),
      black: Player.fromJson(
        (json['black'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      ),
    );
  }
}

class BroadcastGame {
  final List<String> players;
  final String fen;
  final String id;
  final String lastMove;
  final String status;

  /// Immediately kicks off a call to Lichess cloud eval.
  final CloudEval evaluation;

  BroadcastGame(this.id, this.lastMove, this.status, {required this.players, required this.fen})
    : evaluation = CloudEval(fen: fen, multiPv: 2);

  factory BroadcastGame.fromJson(Map<String, dynamic> json) {
    try {
      final players =
          (json['players'] as List<dynamic>)
              .map((p) => (p as Map<String, dynamic>)['name'] as String)
              .toList();
      final fen =
          json.containsKey('fen')
              ? json['fen'] as String
              : 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final lastMove = json.containsKey('lastMove') ? json['lastMove'] as String : '';
      final status = json.containsKey('status') ? json['status'] as String : '';
      final id = json.containsKey('id') ? json['id'] as String : '';
      return BroadcastGame(id, lastMove, status, players: players, fen: fen);
    } catch (e) {
      rethrow;
    }
  }
}

class GameExport {
  final String id;
  final String pgn;
  final List<String> moves;

  const GameExport({
    required this.id,
    required this.pgn,
    required this.moves,
  });

  factory GameExport.fromJson(Map<String, dynamic> json) => GameExport(
        id: json['id'] as String,
        pgn: json['pgn'] as String,
        moves: (json['moves'] as List<dynamic>).cast<String>(),
      );
}

class DetailedGame {
  final BroadcastGame broadcastGame;

  const DetailedGame({required this.broadcastGame});
}
