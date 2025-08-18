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
  final int? boardNr;

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
    this.boardNr,
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
        boardNr: json['board_nr'] != null
            ? (json['board_nr'] as num).toInt()
            : null,
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
      if (boardNr != null) 'board_nr': boardNr,
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
      'title': title,
      'rating': rating,
      'fideId': fideId,
      'fed': fed,
      'clock': clock,
    };
  }
}
class SearchPlayer {
  final String id;
  final String name;
  final String? title;
  final int? rating;
  final int? fideId;
  final String? fed;
  final String tournamentId;
  final String tournamentName;
  final String? gameId;
  final String? roundId;
  final bool isWhitePlayer;

  const SearchPlayer({
    required this.id,
    required this.name,
    this.title,
    this.rating,
    this.fideId,
    this.fed,
    required this.tournamentId,
    required this.tournamentName,
    this.gameId,
    this.roundId,
    this.isWhitePlayer = true,
  });

  // Create from your existing Player model
  factory SearchPlayer.fromPlayer(
      Player player,
      String tournamentId,
      String tournamentName, {
        String? gameId,
        String? roundId,
        bool isWhitePlayer = true,
      }) {
    return SearchPlayer(
      id: '${tournamentId}_${player.fideId}_${gameId ?? ''}',
      name: player.name,
      title: player.title.isNotEmpty ? player.title : null,
      rating: player.rating > 0 ? player.rating : null,
      fideId: player.fideId > 0 ? player.fideId : null,
      fed: player.fed.isNotEmpty ? player.fed : null,
      tournamentId: tournamentId,
      tournamentName: tournamentName,
      gameId: gameId,
      roundId: roundId,
      isWhitePlayer: isWhitePlayer,
    );
  }

  factory SearchPlayer.fromSearchTerm(
      String searchTerm,
      String tournamentId,
      String tournamentName,
      ) {
    return SearchPlayer(
      id: '${tournamentId}_${searchTerm.hashCode}',
      name: searchTerm,
      tournamentId: tournamentId,
      tournamentName: tournamentName,
    );
  }

  factory SearchPlayer.fromJson(
      Map<String, dynamic> json,
      String tournamentId,
      String tournamentName,
      ) {
    return SearchPlayer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString(),
      rating: json['rating'] != null ? int.tryParse(json['rating'].toString()) : null,
      fideId: json['fideId'] != null ? int.tryParse(json['fideId'].toString()) : null,
      fed: json['fed']?.toString(),
      tournamentId: tournamentId,
      tournamentName: tournamentName,
      gameId: json['gameId']?.toString(),
      roundId: json['roundId']?.toString(),
      isWhitePlayer: json['isWhitePlayer'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'title': title,
      'rating': rating,
      'fideId': fideId,
      'fed': fed,
      'tournament_id': tournamentId,
      'tournament_name': tournamentName,
      'game_id': gameId,
      'round_id': roundId,
      'is_white_player': isWhitePlayer,
    };
  }

  SearchPlayer copyWith({
    String? id,
    String? name,
    String? title,
    int? rating,
    int? fideId,
    String? fed,
    String? tournamentId,
    String? tournamentName,
    String? gameId,
    String? roundId,
    bool? isWhitePlayer,
  }) {
    return SearchPlayer(
      id: id ?? this.id,
      name: name ?? this.name,
      title: title ?? this.title,
      rating: rating ?? this.rating,
      fideId: fideId ?? this.fideId,
      fed: fed ?? this.fed,
      tournamentId: tournamentId ?? this.tournamentId,
      tournamentName: tournamentName ?? this.tournamentName,
      gameId: gameId ?? this.gameId,
      roundId: roundId ?? this.roundId,
      isWhitePlayer: isWhitePlayer ?? this.isWhitePlayer,
    );
  }

  @override
  String toString() {
    return 'SearchPlayer(id: $id, name: $name, rating: $rating, tournament: $tournamentName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchPlayer && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  // Helper getters
  String get displayName {
    if (title != null && title!.isNotEmpty) {
      return '$title $name';
    }
    return name;
  }

  String get displayRating {
    return rating?.toString() ?? 'Unrated';
  }

  String get displayFederation {
    return fed ?? 'Unknown';
  }

  bool get hasTitle => title != null && title!.isNotEmpty;

  bool get isRated => rating != null && rating! > 0;

  bool get hasFideId => fideId != null && fideId! > 0;
}
