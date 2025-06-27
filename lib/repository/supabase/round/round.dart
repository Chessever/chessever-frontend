// models/round.dart
import 'dart:developer' as developer;

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
    try {
      // Debug logging
      developer.log('Parsing Round from JSON: $json', name: 'Round.fromJson');

      // Validate required fields
      if (json['id'] == null) throw Exception('Missing required field: id');
      if (json['slug'] == null) throw Exception('Missing required field: slug');
      if (json['tour_id'] == null)
        throw Exception('Missing required field: tour_id');
      if (json['tour_slug'] == null)
        throw Exception('Missing required field: tour_slug');
      if (json['name'] == null) throw Exception('Missing required field: name');
      if (json['created_at'] == null)
        throw Exception('Missing required field: created_at');
      if (json['ongoing'] == null)
        throw Exception('Missing required field: ongoing');
      if (json['url'] == null) throw Exception('Missing required field: url');

      return Round(
        id: json['id'].toString(),
        slug: json['slug'].toString(),
        tourId: json['tour_id'].toString(),
        tourSlug: json['tour_slug'].toString(),
        name: json['name'].toString(),
        createdAt: _parseDateTime(json['created_at']),
        ongoing: _parseBool(json['ongoing']),
        startsAt:
            json['starts_at'] != null
                ? _parseDateTime(json['starts_at'])
                : null,
        url: json['url'].toString(),
      );
    } catch (e, stackTrace) {
      developer.log(
        'Error parsing Round from JSON: $e',
        name: 'Round.fromJson',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // Helper method to safely parse DateTime
  static DateTime _parseDateTime(dynamic dateValue) {
    if (dateValue == null) {
      throw Exception('DateTime value is null');
    }

    if (dateValue is String) {
      try {
        return DateTime.parse(dateValue);
      } catch (e) {
        throw Exception('Invalid DateTime format: $dateValue');
      }
    }

    throw Exception('DateTime value must be a string: $dateValue');
  }

  // Helper method to safely parse bool
  static bool _parseBool(dynamic boolValue) {
    if (boolValue == null) {
      throw Exception('Boolean value is null');
    }

    if (boolValue is bool) {
      return boolValue;
    }

    if (boolValue is String) {
      return boolValue.toLowerCase() == 'true';
    }

    throw Exception('Boolean value must be bool or string: $boolValue');
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
