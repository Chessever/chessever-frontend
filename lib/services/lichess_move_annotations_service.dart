import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum LichessMoveAnnotationType {
  brilliant,
  missedWin,
  mistake,
  blunder,
  inaccuracy,
  goodMove,
  bestMove,
  bookMove,
}

class LichessMoveAnnotation {
  final LichessMoveAnnotationType type;
  final String comment;

  const LichessMoveAnnotation({required this.type, required this.comment});
}

class LichessMoveAnnotationsService {
  LichessMoveAnnotationsService._();

  static const String _functionUrl =
      'https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/fetch-lichess-annotations';
  static const String _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9lbGJzdWdncnp5cXd6bXZpZGp1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk5MDgyODYsImV4cCI6MjA2NTQ4NDI4Nn0.YpIEGIVCN2yUmh4ALnuF0i4jKI3ld1VHNVSCN2J7R30';

  static final Map<String, Map<int, LichessMoveAnnotation>?> _cache = {};
  static final Set<String> _attemptedFetches = {};

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
        debugPrint(
          '🔍 [AnnotationsService] Cache HIT for $lichessGameId: ${cached?.length ?? 0} annotations',
        );
        return cached;
      }
      if (_attemptedFetches.contains(cacheKey)) {
        debugPrint(
          '🔍 [AnnotationsService] Already attempted fetch for $lichessGameId, skipping',
        );
        return null;
      }
    }

    final uri = Uri.parse(_functionUrl);
    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_anonKey',
          'apikey': _anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'game_id': lichessGameId,
          'moves_signature': signature,
          'moves': moveSans,
          'force_refresh': forceRefresh,
          if (siteUrl != null) 'site_url': siteUrl,
        }),
      );

      _attemptedFetches.add(cacheKey);

      if (response.statusCode != 200) {
        debugPrint(
          'Lichess annotations error (${response.statusCode}): ${response.body}',
        );
        _cache[cacheKey] = null;
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final responseSignature = data['moves_signature'] as String?;
      if (responseSignature != null && responseSignature != signature) {
        debugPrint('🔍 [AnnotationsService] Signature mismatch!');
        debugPrint('🔍 [AnnotationsService] Requested: $signature');
        debugPrint('🔍 [AnnotationsService] Response:  $responseSignature');
        _cache[cacheKey] = null;
        return null;
      }

      final annotationsRaw = data['annotations'];
      if (annotationsRaw is! Map<String, dynamic>) {
        _cache[cacheKey] = null;
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
      return annotations;
    } catch (e) {
      debugPrint('Failed to fetch Lichess annotations: $e');
      _attemptedFetches.add(cacheKey);
      _cache[cacheKey] = null;
      return null;
    }
  }

  static void clearCache() {
    _cache.clear();
    _attemptedFetches.clear();
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
      case 'book move':
      case 'book_move':
      case 'book':
        return LichessMoveAnnotationType.bookMove;
      default:
        return null;
    }
  }
}
