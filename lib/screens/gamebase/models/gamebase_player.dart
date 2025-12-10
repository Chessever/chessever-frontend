import 'package:dart_mappable/dart_mappable.dart';

part 'gamebase_player.mapper.dart';

/// Player gender enum
@MappableEnum()
enum PlayerGender {
  @MappableValue('MALE')
  male,
  @MappableValue('FEMALE')
  female,
}

/// Player model from Gamebase API.
/// Maps to the Player schema from the Gamebase API.
@MappableClass()
class GamebasePlayer with GamebasePlayerMappable {
  const GamebasePlayer({
    required this.id,
    required this.fideId,
    required this.name,
    required this.gender,
    required this.fed,
    this.title,
    this.ratingClassical,
    this.ratingRapid,
    this.ratingBlitz,
  });

  /// Internal player UUID
  final String id;

  /// FIDE player ID
  final String fideId;

  /// Player name (e.g., "Carlsen, Magnus")
  final String name;

  /// Player gender
  final PlayerGender gender;

  /// Country federation code (e.g., "NOR", "USA")
  final String fed;

  /// Chess title (e.g., "GM", "IM", "FM")
  final String? title;

  /// Classical rating
  final int? ratingClassical;

  /// Rapid rating
  final int? ratingRapid;

  /// Blitz rating
  final int? ratingBlitz;

  factory GamebasePlayer.fromJson(Map<String, dynamic> json) =>
      GamebasePlayerMapper.fromMap(json);

  /// Get the highest rating across all time controls
  int? get highestRating {
    final ratings =
        [ratingClassical, ratingRapid, ratingBlitz].whereType<int>().toList();
    if (ratings.isEmpty) return null;
    return ratings.reduce((a, b) => a > b ? a : b);
  }

  /// Get display name (first name last name format)
  String get displayName {
    if (name.contains(',')) {
      final parts = name.split(',');
      if (parts.length >= 2) {
        return '${parts[1].trim()} ${parts[0].trim()}';
      }
    }
    return name;
  }

  /// Get title with name (e.g., "GM Magnus Carlsen")
  String get titleAndName {
    if (title != null && title!.isNotEmpty) {
      return '$title $displayName';
    }
    return displayName;
  }
}
