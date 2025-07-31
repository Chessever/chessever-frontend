import 'dart:convert';

class Games {
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
  final List<String>? search;

  Games({
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
    this.search,
  });

  factory Games.fromJson(Map<String, dynamic> json) {
    try {
      return Games(
        id: json['id'] as String,
        roundId: json['round_id'] as String,
        roundSlug: json['round_slug'] as String,
        tourId: json['tour_id'] as String,
        tourSlug: json['tour_slug'] as String,
        name: json['name'] as String?,
        fen: json['fen'] as String?,
        players:
            json['players'] != null
                ? (json['players'] as List)
                    .map(
                      (player) =>
                          Player.fromJson(player as Map<String, dynamic>),
                    )
                    .toList()
                : null,
        lastMove: json['last_move'] as String?,
        thinkTime:
            json['think_time'] != null
                ? (json['think_time'] as num).toInt()
                : null,
        status: json['status'] as String?,
        pgn: json['pgn'] as String?,
        search: (json['search'] as List).map((e) => e as String).toList(),
      );
    } catch (e, _) {
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'round_id': roundId,
      'round_slug': roundSlug,
      'tour_id': tourId,
      'tour_slug': tourSlug,
      if (name != null) 'name': name,
      if (fen != null) 'fen': fen,
      if (players != null) 'players': players!.map((p) => p.toJson()).toList(),
      if (lastMove != null) 'last_move': lastMove,
      if (thinkTime != null) 'think_time': thinkTime,
      if (status != null) 'status': status,
      if (pgn != null) 'pgn': pgn,
      if (search != null) 'search': search!.map((s) => s).toList(),
    };
  }
}

class SearchGame {
  final Player whitePlayer;
  final Player blackPlayer;
  final String gameTitle;

  SearchGame({
    required this.whitePlayer,
    required this.blackPlayer,
    required this.gameTitle,
  });

  // For string list format: ["player1_json", "player2_json", "game_title"]
  factory SearchGame.fromStringList(List<String> jsonList) {
    if (jsonList.length != 3) {
      throw ArgumentError(
        'Expected 3 elements in the list, got ${jsonList.length}',
      );
    }

    return SearchGame(
      whitePlayer: Player.fromJsonString(jsonList[0]),
      blackPlayer: Player.fromJsonString(jsonList[1]),
      gameTitle: jsonList[2],
    );
  }

  // For object format: {"whitePlayer": {...}, "blackPlayer": {...}, "gameTitle": "..."}
  factory SearchGame.fromJsonMap(Map<String, dynamic> json) {
    return SearchGame(
      whitePlayer: Player.fromJson(json['whitePlayer'] as Map<String, dynamic>),
      blackPlayer: Player.fromJson(json['blackPlayer'] as Map<String, dynamic>),
      gameTitle: json['gameTitle'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'whitePlayer': whitePlayer.toJson(),
      'blackPlayer': blackPlayer.toJson(),
      'gameTitle': gameTitle,
    };
  }
}

class Player {
  final String name;
  final String title;
  final int rating;
  final int fideId;
  final String fed;
  final int clock;

  Player({
    required this.name,
    required this.title,
    required this.rating,
    required this.fideId,
    required this.fed,
    required this.clock,
  });

  factory Player.fromJsonString(String jsonString) {
    try {
      final Map<String, dynamic> json = jsonDecode(jsonString);
      return Player.fromJson(json);
    } catch (e) {
      throw FormatException(
        'Invalid JSON string for Player: $jsonString. Error: $e',
      );
    }
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      name: json['name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      fideId: (json['fideId'] as num?)?.toInt() ?? 0,
      fed: json['fed'] as String? ?? '',
      clock: (json['clock'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (title != null) 'title': title,
      'rating': rating,
      'fideId': fideId,
      'fed': fed,
      'clock': clock,
    };
  }

  String get displayName => title != null ? '$title $name' : name;
}
