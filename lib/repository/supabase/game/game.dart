// models/game.dart
class Game {
  final String id;
  final String roundId;
  final String roundSlug;
  final String tourId;
  final String tourSlug;
  final String? name;
  final String? fen;
  final List<Player>? players;
  final String? lastMove;
  final int? thinkTime;
  final String? status;
  final String? pgn;

  Game({
    required this.id,
    required this.roundId,
    required this.roundSlug,
    required this.tourId,
    required this.tourSlug,
    this.name,
    this.fen,
    this.players,
    this.lastMove,
    this.thinkTime,
    this.status,
    this.pgn,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id'] as String,
      roundId: json['round_id'] as String,
      roundSlug: json['round_slug'] as String,
      tourId: json['tour_id'] as String,
      tourSlug: json['tour_slug'] as String,
      name: json['name'] as String?,
      fen: json['fen'] as String?,
      players: json['players'] != null
          ? (json['players'] as List)
          .map((player) => Player.fromJson(player as Map<String, dynamic>))
          .toList()
          : null,
      lastMove: json['last_move'] as String?,
      thinkTime: json['think_time'] != null
          ? (json['think_time'] as num).toInt()
          : null,
      status: json['status'] as String?,
      pgn: json['pgn'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'round_id': roundId,
      'round_slug': roundSlug,
      'tour_id': tourId,
      'tour_slug': tourSlug,
      'name': name,
      'fen': fen,
      'players': players?.map((player) => player.toJson()).toList(),
      'last_move': lastMove,
      'think_time': thinkTime,
      'status': status,
      'pgn': pgn,
    };
  }
}

// models/player.dart
class Player {
  final String fed;
  final String name;
  final int clock;
  final String title;
  final int fideId;
  final int rating;

  Player({
    required this.fed,
    required this.name,
    required this.clock,
    required this.title,
    required this.fideId,
    required this.rating,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      fed: json['fed'] as String,
      name: json['name'] as String,
      clock: (json['clock'] as num).toInt(),
      title: json['title'] as String,
      fideId: (json['fideId'] as num).toInt(),
      rating: (json['rating'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fed': fed,
      'name': name,
      'clock': clock,
      'title': title,
      'fideId': fideId,
      'rating': rating,
    };
  }
}