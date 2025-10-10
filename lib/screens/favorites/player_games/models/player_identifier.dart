import 'package:equatable/equatable.dart';

/// Identifies a player by either fideId or name
class PlayerIdentifier extends Equatable {
  final String? fideId;
  final String playerName;

  const PlayerIdentifier({
    this.fideId,
    required this.playerName,
  });

  /// Create identifier from fideId (preferred)
  factory PlayerIdentifier.fromFideId(String fideId, String playerName) {
    return PlayerIdentifier(
      fideId: fideId,
      playerName: playerName,
    );
  }

  /// Create identifier from name only (fallback)
  factory PlayerIdentifier.fromName(String playerName) {
    return PlayerIdentifier(
      fideId: null,
      playerName: playerName,
    );
  }

  /// Whether this identifier uses fideId
  bool get hasFideId => fideId != null && fideId!.isNotEmpty;

  /// Get a unique key for this identifier
  String get key => hasFideId ? 'fide_$fideId' : 'name_$playerName';

  @override
  List<Object?> get props => [fideId, playerName];

  @override
  String toString() => 'PlayerIdentifier(fideId: $fideId, playerName: $playerName)';
}
