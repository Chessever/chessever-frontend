// models/round.dart
class Round {
  final String id;
  final String slug;
  final String tourId;
  final String tourSlug;
  final String name;
  final DateTime createdAt;
  final bool ongoing;
  final DateTime? startsAt;
  final String url;

  Round({
    required this.id,
    required this.slug,
    required this.tourId,
    required this.tourSlug,
    required this.name,
    required this.createdAt,
    required this.ongoing,
    this.startsAt,
    required this.url,
  });

  factory Round.fromJson(Map<String, dynamic> json) {
    return Round(
      id: json['id'] as String,
      slug: json['slug'] as String,
      tourId: json['tour_id'] as String,
      tourSlug: json['tour_slug'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      ongoing: json['ongoing'] as bool,
      startsAt: json['starts_at'] != null
          ? DateTime.parse(json['starts_at'] as String)
          : null,
      url: json['url'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
      'tour_id': tourId,
      'tour_slug': tourSlug,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'ongoing': ongoing,
      'starts_at': startsAt?.toIso8601String(),
      'url': url,
    };
  }
}