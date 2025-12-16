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
