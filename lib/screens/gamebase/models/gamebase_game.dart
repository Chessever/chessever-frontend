import 'package:dart_mappable/dart_mappable.dart';

part 'gamebase_game.mapper.dart';

/// Time control category enum
@MappableEnum()
enum TimeControl {
  @MappableValue('CLASSICAL')
  classical,
  @MappableValue('RAPID')
  rapid,
  @MappableValue('BLITZ')
  blitz,
}

extension TimeControlExtension on TimeControl {
  String get displayName {
    switch (this) {
      case TimeControl.classical:
        return 'Classical';
      case TimeControl.rapid:
        return 'Rapid';
      case TimeControl.blitz:
        return 'Blitz';
    }
  }
}

/// Game result enum
@MappableEnum()
enum GameResult {
  @MappableValue('W')
  whiteWins,
  @MappableValue('B')
  blackWins,
  @MappableValue('D')
  draw,
}

/// Game model from Gamebase API.
/// Maps to the Game schema from the Gamebase API.
@MappableClass()
class GamebaseGame with GamebaseGameMappable {
  const GamebaseGame({
    required this.id,
    required this.date,
    required this.result,
    required this.timeControl,
    this.whitePlayerId,
    this.blackPlayerId,
    this.data,
  });

  /// Game UUID
  final String id;

  /// Date the game was played
  final DateTime date;

  /// Game result
  final GameResult result;

  /// Time control category
  final TimeControl timeControl;

  /// White player UUID
  final String? whitePlayerId;

  /// Black player UUID
  final String? blackPlayerId;

  /// Full game data including moves and metadata
  final Map<String, dynamic>? data;

  factory GamebaseGame.fromJson(Map<String, dynamic> json) =>
      GamebaseGameMapper.fromMap(json);

  /// Get result as display string
  String get resultDisplay {
    switch (result) {
      case GameResult.whiteWins:
        return '1-0';
      case GameResult.blackWins:
        return '0-1';
      case GameResult.draw:
        return '½-½';
    }
  }

  /// Get time control as display string
  String get timeControlDisplay {
    switch (timeControl) {
      case TimeControl.classical:
        return 'Classical';
      case TimeControl.rapid:
        return 'Rapid';
      case TimeControl.blitz:
        return 'Blitz';
    }
  }
}

/// Extended Game model that includes the raw PGN.
/// Returned by `/api/game/{id}?includePgn=true`.
@MappableClass()
class GamebaseGameWithPgn with GamebaseGameWithPgnMappable {
  const GamebaseGameWithPgn({
    required this.id,
    required this.date,
    required this.result,
    required this.timeControl,
    this.whitePlayerId,
    this.blackPlayerId,
    this.data,
    this.pgn,
    this.eco,
    this.opening,
    this.variation,
    this.event,
    this.site,
    this.whiteName,
    this.blackName,
    this.whiteElo,
    this.blackElo,
  });

  final String id;
  final DateTime date;
  final GameResult result;
  final TimeControl timeControl;
  final String? whitePlayerId;
  final String? blackPlayerId;
  final Map<String, dynamic>? data;
  final String? pgn;
  final String? eco;
  final String? opening;
  final String? variation;
  final String? event;
  final String? site;
  final String? whiteName;
  final String? blackName;
  final int? whiteElo;
  final int? blackElo;

  factory GamebaseGameWithPgn.fromJson(Map<String, dynamic> json) =>
      GamebaseGameWithPgnMapper.fromMap(json);

  /// Get result as display string
  String get resultDisplay {
    switch (result) {
      case GameResult.whiteWins:
        return '1-0';
      case GameResult.blackWins:
        return '0-1';
      case GameResult.draw:
        return '½-½';
    }
  }
}
