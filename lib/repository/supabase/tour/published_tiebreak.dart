/// A published organizer value. Never recompute event-specific tiebreaks here.
class PublishedTiebreak {
  const PublishedTiebreak({
    required this.points,
    required this.description,
    this.extendedCode,
  });
  final num points;
  final String description;
  final String? extendedCode;
  String get label => extendedCode ?? description;
  String get identity => '$label\u0000$description';
  String get formattedPoints =>
      points % 1 == 0 ? points.toInt().toString() : points.toString();
  Map<String, dynamic> toJson() => {
    'points': points,
    'description': description,
    if (extendedCode != null) 'extendedCode': extendedCode,
  };
  static List<PublishedTiebreak> parse(dynamic value) {
    if (value is! List || value.length > 16) return const [];
    final result = <PublishedTiebreak>[];
    final seen = <String>{};
    for (final raw in value) {
      if (raw is! Map) return const [];
      final points = raw['points'];
      final description = raw['description'];
      final code = raw['extendedCode'];
      if (points is! num ||
          !points.isFinite ||
          points < 0 ||
          description is! String ||
          description.trim().isEmpty ||
          (code != null && (code is! String || code.trim().isEmpty))) {
        return const [];
      }
      final item = PublishedTiebreak(
        points: points,
        description: description.trim(),
        extendedCode: (code as String?)?.trim(),
      );
      if (!seen.add(item.identity)) return const [];
      result.add(item);
    }
    return List.unmodifiable(result);
  }

  static bool same(List<PublishedTiebreak> a, List<PublishedTiebreak> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  @override
  bool operator ==(Object other) =>
      other is PublishedTiebreak &&
      points == other.points &&
      description == other.description &&
      extendedCode == other.extendedCode;
  @override
  int get hashCode => Object.hash(points, description, extendedCode);
}
