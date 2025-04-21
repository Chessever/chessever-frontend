// lib/models/game.dart
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

// @immutable
// class Game {
//   final String id;
//   final bool rated;
//   final String variantKey;
//   final String speed;
//   final String perf;
//   final DateTime? createdAt;
//   final String status;
//   final GamePlayers players;
//   final String? winner;
//   final String moves;

//   const Game({
//     required this.id,
//     required this.rated,
//     required this.variantKey,
//     required this.speed,
//     required this.perf,
//     this.createdAt,
//     required this.status,
//     required this.players,
//     this.winner,
//     required this.moves,
//   });

//   factory Game.fromJson(Map<String, dynamic> json) {
//     // Safely parse date
//     final createdDate = json['createdAt'] != null
//         ? DateTime.tryParse(json['createdAt'] as String)
//         : null;

//     // Handle variant being either a String or an object
//     late final String variantKey;
//     if (json['variant'] is String) {
//       variantKey = json['variant'] as String;
//     } else if (json['variant'] is Map<String, dynamic>) {
//       variantKey = (json['variant']['key'] as String?) ?? 'unknown';
//     } else {
//       variantKey = 'unknown';
//     }

//     return Game(
//       id: (json['id'] as String?) ?? 'unknown_id',
//       rated: (json['rated'] as bool?) ?? false,
//       variantKey: variantKey,
//       speed: (json['speed'] as String?) ?? 'unknown',
//       perf: (json['perf'] as String?) ?? 'unknown',
//       createdAt: createdDate,
//       status: (json['status'] as String?) ?? 'unknown',
//       players: GamePlayers.fromJson(
//         (json['players'] as Map<String, dynamic>?) ?? <String, dynamic>{},
//       ),
//       winner: json['winner'] as String?, // may be null
//       moves: (json['moves'] as String?) ?? '', // default to empty if missing
//     );
//   }

//   @override
//   bool operator ==(Object other) =>
//       identical(this, other) ||
//       other is Game && runtimeType == other.runtimeType && id == other.id;

//   @override
//   int get hashCode => id.hashCode;

//   String get playerVsText =>
//       '${players.white.user.name} vs ${players.black.user.name}';
// }



class BroadcastGame {
  final List<String> players;
  final String fen;

  BroadcastGame({
    required this.players,
    required this.fen,
  });

  factory BroadcastGame.fromJson(Map<String, dynamic> json) {
    // json['players'] is a List of { name, title, rating, … }
    final players = (json['players'] as List<dynamic>)
        .map((p) => (p as Map<String, dynamic>)['name'] as String)
        .toList();

    return BroadcastGame(
      players: players,
      fen: json['fen'] as String,
    );
  }
}

