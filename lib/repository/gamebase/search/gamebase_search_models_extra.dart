import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';

class GamebaseSearchResult {
  final String resource;
  final String id;
  final num score;
  final String label;
  final String? snippet;
  final Map<String, dynamic>? preview;

  const GamebaseSearchResult({
    required this.resource,
    required this.id,
    required this.score,
    required this.label,
    this.snippet,
    this.preview,
  });

  factory GamebaseSearchResult.fromJson(Map<String, dynamic> json) {
    return GamebaseSearchResult(
      resource: json['resource'] as String? ?? 'unknown',
      id: json['id'] as String? ?? '',
      score: (json['score'] as num?) ?? 0,
      label: json['label'] as String? ?? '',
      snippet: json['snippet'] as String?,
      preview:
          json['preview'] != null
              ? Map<String, dynamic>.from(json['preview'] as Map)
              : null,
    );
  }
}

class GamebaseGlobalSearchResponse {
  final String status;
  final List<GamebaseSearchResult> results;
  final GamebasePaginationMetadata metadata;

  const GamebaseGlobalSearchResponse({
    required this.status,
    required this.results,
    required this.metadata,
  });

  factory GamebaseGlobalSearchResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return GamebaseGlobalSearchResponse(
      status: json['status'] as String? ?? 'unknown',
      results:
          (data['results'] as List?)
              ?.whereType<Map>()
              .map(
                (e) =>
                    GamebaseSearchResult.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          const [],
      metadata: GamebasePaginationMetadata.fromJson(
        Map<String, dynamic>.from(data['metadata'] as Map? ?? const {}),
      ),
    );
  }
}

class GamebaseEventSearchItem {
  const GamebaseEventSearchItem({
    required this.id,
    required this.event,
    required this.gameCount,
    this.canonicalKey,
    this.broadcastSlug,
    this.wins,
    this.draws,
    this.losses,
    this.score,
    this.site,
    this.startDate,
    this.endDate,
    this.dominantTimeControl,
    this.avgElo,
    this.maxElo,
  });

  final String id;
  final String event;
  final int gameCount;
  final String? canonicalKey;
  final String? broadcastSlug;
  final int? wins;
  final int? draws;
  final int? losses;
  final double? score;
  final String? site;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? dominantTimeControl;
  final int? avgElo;
  final int? maxElo;

  factory GamebaseEventSearchItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    return GamebaseEventSearchItem(
      id: json['id'] as String? ?? '',
      event: json['event'] as String? ?? '',
      gameCount: (json['gameCount'] as num?)?.toInt() ?? 0,
      canonicalKey: json['canonicalKey'] as String?,
      broadcastSlug: json['broadcastSlug'] as String?,
      wins: (json['wins'] as num?)?.toInt(),
      draws: (json['draws'] as num?)?.toInt(),
      losses: (json['losses'] as num?)?.toInt(),
      score: (json['score'] as num?)?.toDouble(),
      site: json['site'] as String?,
      startDate: parseDate(json['startDate']),
      endDate: parseDate(json['endDate']),
      dominantTimeControl: json['dominantTimeControl'] as String?,
      avgElo: (json['avgElo'] as num?)?.toInt(),
      maxElo: (json['maxElo'] as num?)?.toInt(),
    );
  }
}

class GamebaseEventSearchResponse {
  const GamebaseEventSearchResponse({
    required this.status,
    required this.events,
    required this.metadata,
  });

  final String status;
  final List<GamebaseEventSearchItem> events;
  final GamebasePaginationMetadata metadata;

  factory GamebaseEventSearchResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    return GamebaseEventSearchResponse(
      status: json['status'] as String? ?? 'unknown',
      events:
          (data['events'] as List?)
              ?.whereType<Map>()
              .map(
                (e) => GamebaseEventSearchItem.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList() ??
          const [],
      metadata: GamebasePaginationMetadata.fromJson(
        Map<String, dynamic>.from(data['metadata'] as Map? ?? const {}),
      ),
    );
  }
}
