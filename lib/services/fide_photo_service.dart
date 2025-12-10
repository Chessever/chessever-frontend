import 'dart:convert';

import 'package:http/http.dart' as http;

/// Service for fetching FIDE player photos from Supabase storage.
///
/// Photos are stored/cached by an edge function. We call the function first so
/// missing photos get fetched/uploaded automatically, then fall back to the
/// predictable storage URL if needed.
class FidePhotoService {
  FidePhotoService._();

  static const String _functionUrl =
      'https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/fetch-fide-photo';
  static const String _storageBaseUrl =
      'https://oelbsuggrzyqwzmvidju.supabase.co/storage/v1/object/public/player-photos/fide';
  static const String _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9lbGJzdWdncnp5cXd6bXZpZGp1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk5MDgyODYsImV4cCI6MjA2NTQ4NDI4Nn0.YpIEGIVCN2yUmh4ALnuF0i4jKI3ld1VHNVSCN2J7R30';

  // In-memory cache to avoid repeated network calls per session.
  static final Map<String, String?> _urlCache = {};

  /// Fetches or retrieves a cached FIDE profile photo URL.
  ///
  /// - Tries the Supabase Edge Function first (auto-fetches+stores if missing).
  /// - Falls back to the direct storage path so already-fetched photos still
  ///   render even if the function responds with an error.
  static Future<String?> getPhotoUrl(
    String fideId, {
    bool forceRefresh = false,
  }) async {
    if (fideId.isEmpty) return null;

    if (!forceRefresh && _urlCache.containsKey(fideId)) {
      return _urlCache[fideId];
    }

    final uri = Uri.parse(
      '$_functionUrl?fide_id=$fideId${forceRefresh ? '&force_refresh=true' : ''}',
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_anonKey',
          'apikey': _anonKey,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final url = data['url'] as String?;
        _urlCache[fideId] = url;
        return url;
      } else {
        final error = jsonDecode(response.body);
        // Keep this lightweight: log to console for debugging and fall back.
        // ignore: avoid_print
        print('FIDE photo error (${response.statusCode}): ${error['error']}');
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to fetch FIDE photo for $fideId: $e');
    }

    final fallback = '$_storageBaseUrl/$fideId.jpg';
    _urlCache[fideId] = fallback;
    return fallback;
  }

  /// Returns the photo URL or null if fideId is null/empty.
  static Future<String?> getPhotoUrlOrNull(
    String? fideId, {
    bool forceRefresh = false,
  }) async {
    if (fideId == null || fideId.isEmpty) return null;
    return getPhotoUrl(fideId, forceRefresh: forceRefresh);
  }
}
