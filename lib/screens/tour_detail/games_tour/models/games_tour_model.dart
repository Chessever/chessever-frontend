// models/game_card.dart
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:dartchess/dartchess.dart';

class GamesScreenModel {
  GamesScreenModel({
    required this.gamesTourModels,
    required this.pinnedGamedIs,
    this.scrollToIndex, // New field for scroll position
  });

  final List<GamesTourModel> gamesTourModels;
  final List<String> pinnedGamedIs;
  final int? scrollToIndex; // Index to scroll to when round changes

  GamesScreenModel copyWith({
    List<GamesTourModel>? gamesTourModels,
    List<String>? pinnedGamedIs,
    int? scrollToIndex,
  }) {
    return GamesScreenModel(
      gamesTourModels: gamesTourModels ?? this.gamesTourModels,
      pinnedGamedIs: pinnedGamedIs ?? this.pinnedGamedIs,
      scrollToIndex: scrollToIndex ?? this.scrollToIndex,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GamesScreenModel &&
        other.gamesTourModels == gamesTourModels &&
        other.pinnedGamedIs == pinnedGamedIs &&
        other.scrollToIndex == scrollToIndex;
  }

  @override
  int get hashCode =>
      gamesTourModels.hashCode ^
      pinnedGamedIs.hashCode ^
      (scrollToIndex?.hashCode ?? 0);
}

class GamesTourModel {
  final String gameId;
  final PlayerCard whitePlayer;
  final PlayerCard blackPlayer;
  final String whiteTimeDisplay;
  final String blackTimeDisplay;
  final GameStatus gameStatus;
  final String? fen;
  final String? pgn;
  final String? lastMove;
  final int? boardNr;
  final String roundId;
  final DateTime? lastMoveTime;

  GamesTourModel({
    required this.gameId,
    required this.whitePlayer,
    required this.blackPlayer,
    required this.whiteTimeDisplay,
    required this.blackTimeDisplay,
    required this.gameStatus,
    required this.roundId, // Make required
    this.lastMove,
    this.fen,
    this.pgn,
    this.boardNr,
    this.lastMoveTime,
  });

  GamesTourModel copyWith({
    String? gameId,
    PlayerCard? whitePlayer,
    PlayerCard? blackPlayer,
    String? whiteTimeDisplay,
    String? blackTimeDisplay,
    GameStatus? gameStatus,
    String? lastMove,
    String? fen,
    String? pgn,
    int? boardNr,
    String? roundId,
    DateTime? lastMoveTime,
  }) {
    return GamesTourModel(
      gameId: gameId ?? this.gameId,
      whitePlayer: whitePlayer ?? this.whitePlayer,
      blackPlayer: blackPlayer ?? this.blackPlayer,
      whiteTimeDisplay: whiteTimeDisplay ?? this.whiteTimeDisplay,
      blackTimeDisplay: blackTimeDisplay ?? this.blackTimeDisplay,
      gameStatus: gameStatus ?? this.gameStatus,
      lastMove: lastMove ?? this.lastMove,
      fen: fen ?? this.fen,
      pgn: pgn ?? this.pgn,
      boardNr: boardNr ?? this.boardNr,
      roundId: roundId ?? this.roundId,
      lastMoveTime: lastMoveTime ?? this.lastMoveTime,
    );
  }

  factory GamesTourModel.fromGame(Games game) {
    // Enhanced null safety and validation
    if (game.players == null || game.players!.length < 2) {
      throw ArgumentError(
        'Game must have at least 2 players, found: ${game.players?.length ?? 0}',
      );
    }

    final players = game.players!;

    // Ensure we have exactly 2 players, take first two if more
    final Player white = players.first;
    final Player black = players.length > 1 ? players[1] : players.first;

    // Validate player data
    if (white.name.isEmpty || black.name.isEmpty) {
      throw ArgumentError('Player names cannot be empty');
    }

    try {
      return GamesTourModel(
        gameId: game.id,
        whitePlayer: PlayerCard.fromPlayer(white),
        blackPlayer: PlayerCard.fromPlayer(black),
        whiteTimeDisplay: _formatTime(white.clock),
        blackTimeDisplay: _formatTime(black.clock),
        gameStatus: GameStatus.fromString(game.status),
        roundId: game.roundId, // Include roundId in model
        fen: game.fen?.isNotEmpty == true ? game.fen : null,
        pgn: game.pgn?.isNotEmpty == true ? game.pgn : null,
        lastMove: game.lastMove?.isNotEmpty == true ? game.lastMove : null,
        boardNr: game.boardNr,
        lastMoveTime: game.lastMoveTime,
      );
    } catch (e) {
      throw ArgumentError(
        'Failed to create GamesTourModel from game ${game.id}: $e',
      );
    }
  }

  static String _formatTime(int? clockTimeMs) {
    // Enhanced null safety for clock time
    if (clockTimeMs == null || clockTimeMs < 0) {
      return '--:--';
    }

    // Convert milliseconds to minutes and seconds
    final totalSeconds = (clockTimeMs / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    // Handle display for very long games (over 99 minutes)
    if (minutes > 99) {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return '${hours}h${remainingMinutes.toString().padLeft(2, '0')}m';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Helper method to get round display name
  String get roundDisplayName {
    // Extract round number for display (e.g., "round7" -> "Round 7")
    final match = RegExp(
      r'round(\d+)',
      caseSensitive: false,
    ).firstMatch(roundId);
    if (match != null) {
      final roundNumber = match.group(1);
      return 'Round $roundNumber';
    }
    // Fallback to original roundId with capitalization
    return roundId.replaceAllMapped(
      RegExp(r'\b\w'),
      (match) => match.group(0)!.toUpperCase(),
    );
  }

  Side? get activePlayer {
    if (fen == null || fen!.isEmpty) return Side.white; // Default to white

    try {
      final setup = Setup.parseFen(fen!);
      return setup.turn;
    } catch (e) {
      // Fallback if FEN is invalid
      return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GamesTourModel &&
        other.gameId == gameId &&
        other.whitePlayer == whitePlayer &&
        other.blackPlayer == blackPlayer &&
        other.whiteTimeDisplay == whiteTimeDisplay &&
        other.blackTimeDisplay == blackTimeDisplay &&
        other.gameStatus == gameStatus &&
        other.lastMove == lastMove &&
        other.fen == fen &&
        other.pgn == pgn &&
        other.boardNr == boardNr &&
        other.roundId == roundId;
  }

  @override
  int get hashCode {
    return gameId.hashCode ^
        whitePlayer.hashCode ^
        blackPlayer.hashCode ^
        whiteTimeDisplay.hashCode ^
        blackTimeDisplay.hashCode ^
        gameStatus.hashCode ^
        (lastMove?.hashCode ?? 0) ^
        (fen?.hashCode ?? 0) ^
        (pgn?.hashCode ?? 0) ^
        (boardNr?.hashCode ?? 0) ^
        roundId.hashCode;
  }
}

// Rest of the classes remain the same...
class PlayerCard {
  final String name;
  final String federation;
  final String title;
  final int rating;
  final String countryCode;

  PlayerCard({
    required this.name,
    required this.federation,
    required this.title,
    required this.rating,
    required this.countryCode,
  });

  factory PlayerCard.fromPlayer(Player player) {
    final name = player.name.trim();
    if (name.isEmpty) {
      throw ArgumentError('Player name cannot be empty');
    }

    return PlayerCard(
      name: name,
      federation: player.fed.trim(),
      title: player.title.trim(),
      rating: player.rating >= 0 ? player.rating : 0,
      countryCode: player.fed.trim(),
    );
  }

  PlayerCard copyWith({
    String? name,
    String? federation,
    String? title,
    int? rating,
    String? countryCode,
  }) {
    return PlayerCard(
      name: name ?? this.name,
      federation: federation ?? this.federation,
      title: title ?? this.title,
      rating: rating ?? this.rating,
      countryCode: countryCode ?? this.countryCode,
    );
  }

  String get displayName => name;
  String get displayTitle => title.isNotEmpty ? title : '';
  String get displayRating => rating > 0 ? rating.toString() : 'Unrated';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlayerCard &&
        other.name == name &&
        other.federation == federation &&
        other.title == title &&
        other.rating == rating &&
        other.countryCode == countryCode;
  }

  @override
  int get hashCode {
    return name.hashCode ^
        federation.hashCode ^
        title.hashCode ^
        rating.hashCode ^
        countryCode.hashCode;
  }
}

enum GameStatus {
  ongoing,
  whiteWins,
  blackWins,
  draw,
  unknown;

  static GameStatus fromString(String? status) {
    if (status == null || status.trim().isEmpty) {
      return GameStatus.unknown;
    }

    final normalizedStatus = status.trim();

    switch (normalizedStatus) {
      case '1-0':
        return GameStatus.whiteWins;
      case '0-1':
        return GameStatus.blackWins;
      case '1/2-1/2':
      case '½-½':
      case '0.5-0.5':
        return GameStatus.draw;
      case '*':
        return GameStatus.ongoing;
      default:
        print('Unknown game status: "$normalizedStatus"');
        return GameStatus.unknown;
    }
  }

  String get displayText {
    switch (this) {
      case GameStatus.whiteWins:
        return '1-0';
      case GameStatus.blackWins:
        return '0-1';
      case GameStatus.draw:
        return '½-½';
      case GameStatus.ongoing:
        return '*';
      case GameStatus.unknown:
        return '';
    }
  }

  bool get isFinished {
    return this != GameStatus.ongoing && this != GameStatus.unknown;
  }

  bool get isOngoing {
    return this == GameStatus.ongoing;
  }
}
