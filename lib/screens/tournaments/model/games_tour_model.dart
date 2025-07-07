// models/game_card.dart
import 'package:chessever2/repository/supabase/game/games.dart';

class GamesTourModel {
  final String gameId;
  final PlayerCard whitePlayer;
  final PlayerCard blackPlayer;
  final String whiteTimeDisplay;
  final String blackTimeDisplay;
  final GameStatus gameStatus;
  final String? fen;

  GamesTourModel({
    required this.gameId,
    required this.whitePlayer,
    required this.blackPlayer,
    required this.whiteTimeDisplay,
    required this.blackTimeDisplay,
    required this.gameStatus,
    this.fen,
  });

  factory GamesTourModel.fromGame(Games game) {
    // Ensure we have exactly 2 players
    if (game.players == null || game.players!.length != 2) {
      throw ArgumentError('Game must have exactly 2 players');
    }

    final Player white = game.players!.first; // First player is white
    final Player black = game.players!.last; // Second player is black

    return GamesTourModel(
      gameId: game.id,
      whitePlayer: PlayerCard.fromPlayer(white),
      blackPlayer: PlayerCard.fromPlayer(black),
      whiteTimeDisplay: _formatTime(white.clock),
      blackTimeDisplay: _formatTime(black.clock),
      gameStatus: GameStatus.fromString(game.status),
      fen: game.fen,
    );
  }

  static String _formatTime(int clockTimeMs) {
    // Convert milliseconds to minutes and seconds
    final totalSeconds = (clockTimeMs / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// models/player_card.dart
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
    return PlayerCard(
      name: player.name,
      federation: player.fed,
      title: player.title,
      rating: player.rating,
      countryCode: player.fed,
    );
  }

  String get displayName => name;

  String get displayTitle => '$title $rating';
}

// models/game_status.dart
enum GameStatus {
  ongoing,
  whiteWins,
  blackWins,
  draw,
  unknown;

  static GameStatus fromString(String? status) {
    if (status == null) return GameStatus.unknown;

    switch (status) {
      case '1-0':
        return GameStatus.whiteWins;
      case '0-1':
        return GameStatus.blackWins;
      case '1/2-1/2':
      case '½-½':
        return GameStatus.draw;
      case '*':
        return GameStatus.ongoing;
      default:
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
        return 'Live';
      case GameStatus.unknown:
        return '';
    }
  }

  bool get isFinished {
    return this != GameStatus.ongoing && this != GameStatus.unknown;
  }
}
