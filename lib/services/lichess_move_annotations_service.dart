import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum LichessMoveAnnotationType {
  brilliant,
  missedWin,
  mistake,
  blunder,
  inaccuracy,
  goodMove,
  bestMove,
  forced,
  bookMove,
}

class LichessMoveAnnotation {
  final LichessMoveAnnotationType type;
  final String comment;
  final bool useClassificationIcon;

  const LichessMoveAnnotation({
    required this.type,
    required this.comment,
    this.useClassificationIcon = false,
  });
}

class LichessMoveAnnotationsService {
  LichessMoveAnnotationsService._();

  static final Map<String, Map<int, LichessMoveAnnotation>?> _cache = {};
  static final Set<String> _attemptedFetches = {};

  /// Empty / pending fetches are not permanent — Lichess analysis may finish
  /// after the first probe. Allow a quiet retry after this backoff.
  static final Map<String, DateTime> _emptyOrFailedAt = {};
  static final Map<String, int> _emptyRetryCount = {};
  static const Duration _emptyRetryAfter = Duration(seconds: 20);
  static const int maxEmptyRetries = 3;

  /// Whether a soft re-probe should be scheduled after an empty/null result.
  static bool shouldScheduleEmptyRetry(String lichessGameId, String signature) {
    final key = '$lichessGameId::$signature';
    return (_emptyRetryCount[key] ?? 0) < maxEmptyRetries;
  }

  static void recordEmptyRetryScheduled(
    String lichessGameId,
    String signature,
  ) {
    final key = '$lichessGameId::$signature';
    _emptyRetryCount[key] = (_emptyRetryCount[key] ?? 0) + 1;
  }

  static Future<Map<int, LichessMoveAnnotation>?> getAnnotations({
    required String lichessGameId,
    required List<String> moveSans,
    required String signature,
    String? siteUrl,
    bool forceRefresh = false,
  }) async {
    if (lichessGameId.isEmpty || moveSans.isEmpty) return null;

    final cacheKey = '$lichessGameId::$signature';
    if (!forceRefresh) {
      if (_cache.containsKey(cacheKey)) {
        final cached = _cache[cacheKey];
        // Non-empty results are stable — return immediately.
        if (cached != null && cached.isNotEmpty) {
          debugPrint(
            '🔍 [AnnotationsService] Cache HIT for $lichessGameId: ${cached.length} annotations',
          );
          return cached;
        }
        // Empty / null may mean "analysis not ready yet". Retry after backoff
        // so markers can appear automatically once the report is generated.
        final emptyAt = _emptyOrFailedAt[cacheKey];
        if (emptyAt != null &&
            DateTime.now().difference(emptyAt) < _emptyRetryAfter) {
          debugPrint(
            '🔍 [AnnotationsService] Empty cache within backoff for $lichessGameId',
          );
          return cached;
        }
        debugPrint(
          '🔍 [AnnotationsService] Empty cache expired — retrying $lichessGameId',
        );
      } else if (_attemptedFetches.contains(cacheKey)) {
        final emptyAt = _emptyOrFailedAt[cacheKey];
        if (emptyAt != null &&
            DateTime.now().difference(emptyAt) < _emptyRetryAfter) {
          debugPrint(
            '🔍 [AnnotationsService] Already attempted fetch for $lichessGameId, skipping',
          );
          return null;
        }
      }
    }

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'fetch-lichess-annotations',
        body: <String, dynamic>{
          'game_id': lichessGameId,
          'moves_signature': signature,
          'moves': moveSans,
          'force_refresh': forceRefresh,
          if (siteUrl != null) 'site_url': siteUrl,
        },
      );

      _attemptedFetches.add(cacheKey);

      if (response.status != 200) {
        debugPrint(
          'Lichess annotations error (${response.status}): ${response.data}',
        );
        _cache[cacheKey] = null;
        _emptyOrFailedAt[cacheKey] = DateTime.now();
        return null;
      }

      if (response.data is! Map) {
        _cache[cacheKey] = null;
        _emptyOrFailedAt[cacheKey] = DateTime.now();
        return null;
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      final responseSignature = data['moves_signature'] as String?;
      if (responseSignature != null && responseSignature != signature) {
        debugPrint('🔍 [AnnotationsService] Signature mismatch!');
        debugPrint('🔍 [AnnotationsService] Requested: $signature');
        debugPrint('🔍 [AnnotationsService] Response:  $responseSignature');
        _cache[cacheKey] = null;
        _emptyOrFailedAt[cacheKey] = DateTime.now();
        return null;
      }

      final annotationsRaw = data['annotations'];
      if (annotationsRaw is! Map<String, dynamic>) {
        _cache[cacheKey] = null;
        _emptyOrFailedAt[cacheKey] = DateTime.now();
        return null;
      }

      final annotations = <int, LichessMoveAnnotation>{};
      for (final entry in annotationsRaw.entries) {
        final index = int.tryParse(entry.key);
        if (index == null) continue;
        if (entry.value is! Map<String, dynamic>) continue;
        final payload = entry.value as Map<String, dynamic>;
        final name = payload['name'] as String?;
        final comment = (payload['comment'] as String?) ?? '';
        final type = _annotationTypeFromName(name);
        if (type == null) continue;
        annotations[index] = LichessMoveAnnotation(
          type: type,
          comment: comment,
        );
      }

      debugPrint(
        '🔍 [AnnotationsService] Parsed ${annotations.length} annotations: ${annotations.keys.toList()}',
      );
      _cache[cacheKey] = annotations;
      if (annotations.isEmpty) {
        _emptyOrFailedAt[cacheKey] = DateTime.now();
      } else {
        _emptyOrFailedAt.remove(cacheKey);
      }
      return annotations;
    } catch (e) {
      debugPrint('Failed to fetch Lichess annotations: $e');
      _attemptedFetches.add(cacheKey);
      _cache[cacheKey] = null;
      _emptyOrFailedAt[cacheKey] = DateTime.now();
      return null;
    }
  }

  static void clearCache() {
    _cache.clear();
    _attemptedFetches.clear();
    _emptyOrFailedAt.clear();
    _emptyRetryCount.clear();
  }

  static LichessMoveAnnotationType? _annotationTypeFromName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final normalized = name.trim().toLowerCase();
    switch (normalized) {
      case 'brilliant':
        return LichessMoveAnnotationType.brilliant;
      case 'missed win':
      case 'missed_win':
      case 'miss':
        return LichessMoveAnnotationType.missedWin;
      case 'mistake':
        return LichessMoveAnnotationType.mistake;
      case 'blunder':
        return LichessMoveAnnotationType.blunder;
      case 'inaccuracy':
        return LichessMoveAnnotationType.inaccuracy;
      case 'good move':
      case 'good_move':
      case 'good':
        return LichessMoveAnnotationType.goodMove;
      case 'best move':
      case 'best_move':
      case 'best':
        return LichessMoveAnnotationType.bestMove;
      case 'forced':
      case 'forced move':
      case 'forced_move':
        return LichessMoveAnnotationType.forced;
      case 'book move':
      case 'book_move':
      case 'book':
        return LichessMoveAnnotationType.bookMove;
      default:
        return null;
    }
  }
}
