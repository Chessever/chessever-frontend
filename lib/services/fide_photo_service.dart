import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service for fetching FIDE player photos from Supabase storage.
///
/// Photos are stored/cached by an edge function. We call the function first so
/// missing photos get fetched/uploaded automatically. Returns null if no valid
/// photo exists for the player.
class FidePhotoService {
  FidePhotoService._();

  static const String _functionUrl =
      'https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/fetch-fide-photo';
  static const String _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9lbGJzdWdncnp5cXd6bXZpZGp1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk5MDgyODYsImV4cCI6MjA2NTQ4NDI4Nn0.YpIEGIVCN2yUmh4ALnuF0i4jKI3ld1VHNVSCN2J7R30';

  /// Minimum file size in bytes for a valid photo (5KB).
  /// Placeholder/default images from FIDE are typically smaller.
  static const int _minValidPhotoSize = 5000;

  // In-memory cache to avoid repeated network calls per session.
  // Key: fideId, Value: URL or null (null means no photo available)
  static final Map<String, String?> _urlCache = {};

  // Track which fideIds we've already attempted to fetch (including failures)
  // This prevents repeated calls for players without photos.
  static final Set<String> _attemptedFetches = {};

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

    // Check cache first (unless forcing refresh)
    if (!forceRefresh) {
      if (_urlCache.containsKey(fideId)) {
        return _urlCache[fideId];
      }
      // If we already tried and failed, don't retry
      if (_attemptedFetches.contains(fideId)) {
        return null;
      }
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

      _attemptedFetches.add(fideId);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final url = data['url'] as String?;

        // Validate URL and check image size
        if (url != null && url.isNotEmpty) {
          final isValid = await _isValidPhotoUrl(url);
          if (isValid) {
            _urlCache[fideId] = url;
            return url;
          } else {
            debugPrint('FIDE photo for $fideId rejected: too small (likely placeholder)');
            _urlCache[fideId] = null;
            return null;
          }
        }
      } else {
        // Log error for debugging
        try {
          final error = jsonDecode(response.body);
          debugPrint('FIDE photo error (${response.statusCode}): ${error['error']}');
        } catch (_) {
          debugPrint('FIDE photo error (${response.statusCode}): ${response.body}');
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch FIDE photo for $fideId: $e');
      _attemptedFetches.add(fideId);
    }

    // No valid photo found - cache null to prevent repeated attempts
    _urlCache[fideId] = null;
    return null;
  }

  /// Validates that the photo URL points to a real image (not a placeholder).
  /// Uses HEAD request to check Content-Length without downloading the full image.
  static Future<bool> _isValidPhotoUrl(String url) async {
    try {
      final response = await http.head(Uri.parse(url));
      if (response.statusCode != 200) return false;

      final contentLength = response.headers['content-length'];
      if (contentLength == null) {
        // No content-length header - assume valid and let pixel validation handle it
        return true;
      }

      final size = int.tryParse(contentLength) ?? 0;
      return size >= _minValidPhotoSize;
    } catch (e) {
      debugPrint('Failed to validate photo URL: $e');
      // On error, assume valid and let pixel validation handle it
      return true;
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
    _attemptedFetches.clear();
    debugPrint('FidePhotoService: Cache cleared');
  }

  /// Clears the cache for a specific player.
  static void clearCacheFor(String fideId) {
    _urlCache.remove(fideId);
    _attemptedFetches.remove(fideId);
  }
}
