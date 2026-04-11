import 'package:dart_mappable/dart_mappable.dart';

part 'move_aggregate.mapper.dart';

/// Aggregated statistics for a move played from a given position.
/// Maps to the MoveAggregate schema from the Gamebase API.
@MappableClass()
class MoveAggregate with MoveAggregateMappable {
  const MoveAggregate({
    required this.uci,
    required this.white,
    required this.black,
    required this.draws,
    required this.total,
    this.gameId,
    this.lastPlayed,
  });

  /// Move in UCI notation (e.g., "e2e4")
  final String uci;

  /// Number of games won by white after this move
  final int white;

  /// Number of games won by black after this move
  final int black;

  /// Number of games drawn after this move
  final int draws;

  /// Total number of games with this move
  final int total;

  /// Game ID (only present when total = 1)
  final String? gameId;

  /// Most recent game date for this move.
  final DateTime? lastPlayed;

  factory MoveAggregate.fromJson(Map<String, dynamic> json) =>
      MoveAggregateMapper.fromMap(json);

  /// Win percentage for white (0.0 to 1.0)
  double get whiteWinRate => total > 0 ? white / total : 0.0;

  /// Win percentage for black (0.0 to 1.0)
  double get blackWinRate => total > 0 ? black / total : 0.0;

  /// Draw percentage (0.0 to 1.0)
  double get drawRate => total > 0 ? draws / total : 0.0;

  /// Formatted white win percentage string
  String get whiteWinPercent => '${(whiteWinRate * 100).toStringAsFixed(0)}%';

  /// Formatted black win percentage string
  String get blackWinPercent => '${(blackWinRate * 100).toStringAsFixed(0)}%';

  /// Formatted draw percentage string
  String get drawPercent => '${(drawRate * 100).toStringAsFixed(0)}%';

  /// Formatted total games string (e.g., "1.2K", "3.5M")
  String get formattedTotal {
    if (total >= 1000000) {
      return '${(total / 1000000).toStringAsFixed(1)}M';
    } else if (total >= 1000) {
      return '${(total / 1000).toStringAsFixed(1)}K';
    }
    return total.toString();
  }
}
