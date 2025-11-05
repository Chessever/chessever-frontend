/// FIDE player model from Lichess API
/// Endpoint: GET /api/fide/player/{playerId}
class FidePlayer {
  final int id;
  final String name;
  final String? federation;
  final int? year;
  final String? title;
  final int? standard; // Classical rating
  final int? rapid;
  final int? blitz;

  const FidePlayer({
    required this.id,
    required this.name,
    this.federation,
    this.year,
    this.title,
    this.standard,
    this.rapid,
    this.blitz,
  });

  factory FidePlayer.fromJson(Map<String, dynamic> json) {
    return FidePlayer(
      id: json['id'] as int,
      name: json['name'] as String,
      federation: json['federation'] as String?,
      year: json['year'] as int?,
      title: json['title'] as String?,
      standard: json['standard'] as int?,
      rapid: json['rapid'] as int?,
      blitz: json['blitz'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (federation != null) 'federation': federation,
    if (year != null) 'year': year,
    if (title != null) 'title': title,
    if (standard != null) 'standard': standard,
    if (rapid != null) 'rapid': rapid,
    if (blitz != null) 'blitz': blitz,
  };

  /// Get rating for specific time control type
  int? getRating(String timeControlType) {
    switch (timeControlType.toLowerCase()) {
      case 'standard':
      case 'classical':
        return standard;
      case 'rapid':
        return rapid;
      case 'blitz':
        return blitz;
      default:
        return null;
    }
  }
}
