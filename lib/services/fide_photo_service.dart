import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service for fetching FIDE player photos from Supabase storage.
///
/// Photos are stored/cached by an edge function. We call the function first so
/// missing photos get fetched/uploaded automatically. Returns null if no valid
/// photo exists for the player.
///
/// Caching strategy:
/// - Positive URLs are cached for the session.
/// - "Confirmed absent" (edge function returned no URL, or image was a
///   too-small placeholder) is cached permanently for the session.
/// - Transient failures (HTTP exception, non-200, HEAD validation error)
///   are backed off briefly then retried, so a single network blip does not
///   disable photos for the rest of the session.
class FidePhotoService {
  FidePhotoService._();

  static const String _functionUrl =
      'https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/fetch-fide-photo-webp';
  static const String _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9lbGJzdWdncnp5cXd6bXZpZGp1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk5MDgyODYsImV4cCI6MjA2NTQ4NDI4Nn0.YpIEGIVCN2yUmh4ALnuF0i4jKI3ld1VHNVSCN2J7R30';

  /// Minimum file size in bytes for a valid photo (5KB).
  /// Placeholder/default images from FIDE are typically smaller.
  static const int _minValidPhotoSize = 5000;

  /// How long to wait before retrying after a transient failure.
  static const Duration _transientRetryBackoff = Duration(minutes: 2);

  /// Positive cache: fideId -> resolved URL.
  static final Map<String, String> _urlCache = {};

  /// Confirmed-absent: edge function said no photo, or the image was a
  /// known placeholder (below [_minValidPhotoSize]). Persists for the session.
  static final Set<String> _confirmedAbsent = {};

  /// Transient-failure timestamps. Entries expire after [_transientRetryBackoff].
  static final Map<String, DateTime> _transientFailures = {};

  /// Fetches or retrieves a cached FIDE profile photo URL.
  ///
  /// Returns null if no valid photo exists for the player.
  /// Only returns a URL when the edge function confirms a photo exists
  /// AND the image file size is above the minimum threshold.
  static Future<String?> getPhotoUrl(
    String fideId, {
    bool forceRefresh = false,
  }) async {
    if (fideId.isEmpty) return null;

    if (!forceRefresh) {
      final cached = _urlCache[fideId];
      if (cached != null) return cached;
      if (_confirmedAbsent.contains(fideId)) return null;
      final lastFailure = _transientFailures[fideId];
      if (lastFailure != null &&
          DateTime.now().difference(lastFailure) < _transientRetryBackoff) {
        return null;
      }
    }

    final uri = Uri.parse(
      '$_functionUrl?fide_id=$fideId${forceRefresh ? '&force_refresh=true' : ''}',
    );

    try {
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $_anonKey', 'apikey': _anonKey},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final url = data['url'] as String?;

        if (url == null || url.isEmpty) {
          _markConfirmedAbsent(fideId);
          return null;
        }

        final validity = await _checkPhotoValidity(url);
        switch (validity) {
          case _PhotoValidity.valid:
            _markResolved(fideId, url);
            return url;
          case _PhotoValidity.tooSmall:
            debugPrint(
              'FIDE photo for $fideId rejected: too small (likely placeholder)',
            );
            _markConfirmedAbsent(fideId);
            return null;
          case _PhotoValidity.unknown:
            // HEAD failed or content-length missing. Trust the URL and let the
            // widget-level pixel validation catch real placeholders. Do not
            // poison the cache on a transient HEAD failure.
            _markResolved(fideId, url);
            return url;
        }
      }

      // Non-200 from edge function: transient. Log, back off briefly, retry later.
      try {
        final error = jsonDecode(response.body);
        debugPrint(
          'FIDE photo error (${response.statusCode}): ${error['error']}',
        );
      } catch (_) {
        debugPrint(
          'FIDE photo error (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Failed to fetch FIDE photo for $fideId: $e');
    }

    _transientFailures[fideId] = DateTime.now();
    return null;
  }

  static void _markResolved(String fideId, String url) {
    _urlCache[fideId] = url;
    _confirmedAbsent.remove(fideId);
    _transientFailures.remove(fideId);
  }

  static void _markConfirmedAbsent(String fideId) {
    _urlCache.remove(fideId);
    _confirmedAbsent.add(fideId);
    _transientFailures.remove(fideId);
  }

  /// Classifies a photo URL by HEAD request. Network errors collapse to
  /// [unknown] so transient issues never turn into permanent absences.
  static Future<_PhotoValidity> _checkPhotoValidity(String url) async {
    try {
      final response = await http.head(Uri.parse(url));
      if (response.statusCode != 200) return _PhotoValidity.unknown;

      final contentLength = response.headers['content-length'];
      if (contentLength == null) return _PhotoValidity.unknown;

      final size = int.tryParse(contentLength) ?? 0;
      if (size < _minValidPhotoSize) return _PhotoValidity.tooSmall;
      return _PhotoValidity.valid;
    } catch (e) {
      debugPrint('Failed to validate photo URL: $e');
      return _PhotoValidity.unknown;
    }
  }

  /// Returns the photo URL or null if fideId is null/empty.
  static Future<String?> getPhotoUrlOrNull(
    String? fideId, {
    bool forceRefresh = false,
  }) async {
    if (fideId == null || fideId.isEmpty) return null;
    return getPhotoUrl(fideId, forceRefresh: forceRefresh);
  }

  /// Clears all cached photo URLs. Useful when debugging or after updates.
  static void clearCache() {
    _urlCache.clear();
    _confirmedAbsent.clear();
    _transientFailures.clear();
    debugPrint('FidePhotoService: Cache cleared');
  }

  /// Clears the cache for a specific player.
  static void clearCacheFor(String fideId) {
    _urlCache.remove(fideId);
    _confirmedAbsent.remove(fideId);
    _transientFailures.remove(fideId);
  }
}

enum _PhotoValidity { valid, tooSmall, unknown }
