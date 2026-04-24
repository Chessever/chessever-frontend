// models/round.dart
import 'dart:developer' as developer;

class Round {
  final String id;
  final String slug;
  final String tourId;
  final String tourSlug;
  final String name;
  final DateTime createdAt;
  final DateTime? startsAt;
  final String url;

  Round({
    required this.id,
    required this.slug,
    required this.tourId,
    required this.tourSlug,
    required this.name,
    required this.createdAt,
    this.startsAt,
    required this.url,
  });

  factory Round.fromJson(Map<String, dynamic> json) {
    try {
      // Validate required fields
      if (json['id'] == null) throw Exception('Missing required field: id');
      if (json['slug'] == null) throw Exception('Missing required field: slug');
      if (json['tour_id'] == null) {
        throw Exception('Missing required field: tour_id');
      }
      if (json['tour_slug'] == null) {
        throw Exception('Missing required field: tour_slug');
      }
      if (json['name'] == null) throw Exception('Missing required field: name');
      if (json['created_at'] == null) {
        throw Exception('Missing required field: created_at');
      }

      if (json['url'] == null) throw Exception('Missing required field: url');

      final rawSlug = json['slug'].toString();
      final rawName = json['name'].toString();
      final rawUrl = json['url'].toString();
      final canonicalSlug = _canonicalLichessRoundSlug(rawSlug, rawUrl);

      return Round(
        id: json['id'].toString(),
        slug: canonicalSlug,
        tourId: json['tour_id'].toString(),
        tourSlug: json['tour_slug'].toString(),
        name: _canonicalLichessRoundName(
          rawName,
          originalSlug: rawSlug,
          canonicalSlug: canonicalSlug,
        ),
        createdAt: _parseDateTime(json['created_at']),
        startsAt:
            json['starts_at'] != null
                ? _parseDateTime(json['starts_at'])
                : null,
        url: rawUrl,
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

  // Helper method to safely parse bool - not currently used but kept for future use
  // static bool _parseBool(dynamic boolValue) {
  //   if (boolValue == null) {
  //     throw Exception('Boolean value is null');
  //   }
  //
  //   if (boolValue is bool) {
  //     return boolValue;
  //   }
  //
  //   if (boolValue is String) {
  //     return boolValue.toLowerCase() == 'true';
  //   }
  //
  //   throw Exception('Boolean value must be bool or string: $boolValue');
  // }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
      'tour_id': tourId,
      'tour_slug': tourSlug,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'starts_at': startsAt?.toIso8601String(),
      'url': url,
    };
  }
}

String _canonicalLichessRoundSlug(String slug, String url) {
  final urlSlug = _lichessRoundSlugFromUrl(url);
  if (urlSlug == null) return slug;

  // Lichess broadcast URLs are canonical for round slugs. This repairs rows
  // imported while Lichess briefly exposed labels like round-4-1 for round-11.
  if (_isGenericRoundSlug(slug) || _roundNumberFromSlug(urlSlug) != null) {
    return urlSlug;
  }

  return slug;
}

String _canonicalLichessRoundName(
  String name, {
  required String originalSlug,
  required String canonicalSlug,
}) {
  if (canonicalSlug == originalSlug) return name;

  final roundNumber = _roundNumberFromSlug(canonicalSlug);
  if (roundNumber == null) return name;

  if (_looksLikeGenericRoundName(name) || _isGenericRoundSlug(originalSlug)) {
    return 'Round $roundNumber';
  }

  return name;
}

String? _lichessRoundSlugFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host != 'lichess.org') return null;

  final segments = uri.pathSegments;
  final broadcastIndex = segments.indexOf('broadcast');
  if (broadcastIndex < 0 || segments.length <= broadcastIndex + 2) {
    return null;
  }

  final candidate = segments[broadcastIndex + 2].trim();
  return candidate.isEmpty || candidate == '-' ? null : candidate;
}

bool _looksLikeGenericRoundName(String name) {
  return RegExp(
    r'^round\s+\d+(?:[._-]\d+)?$',
    caseSensitive: false,
  ).hasMatch(name.trim());
}

bool _isGenericRoundSlug(String slug) {
  return RegExp(
    r'^round-\d+(?:-\d+)?$',
    caseSensitive: false,
  ).hasMatch(slug.trim());
}

int? _roundNumberFromSlug(String slug) {
  final match = RegExp(
    r'^round-(\d+)$',
    caseSensitive: false,
  ).firstMatch(slug.trim());
  return match == null ? null : int.tryParse(match.group(1)!);
}
