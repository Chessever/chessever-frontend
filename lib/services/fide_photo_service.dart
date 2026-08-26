import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for fetching FIDE player photos from Supabase storage.
///
/// Photos are stored/cached by an edge function. We call the function first so
/// missing photos get fetched/uploaded automatically. Returns null if no valid
/// photo exists for the player.
///
/// Caching strategy:
/// - Positive URLs are cached for the session.
/// - "Confirmed absent" (the edge function reported no photo) is cached for
///   the session, because that answer already carries the function's own TTL.
/// - Transient failures (network exception, non-200) are backed off briefly
///   then retried, so a single blip does not disable photos for the session.
/// - Concurrent lookups for the same player share one request.
///
/// **Placeholder rejection is the edge function's job, not this client's.**
/// The function validates the *source* bytes from FIDE against a 5KB floor
/// before it ever uploads, and re-checks the stored file's size on a storage
/// hit. What it hands back is a Supabase render-CDN URL for a 300x300 WebP —
/// a re-encoded, downscaled derivative whose byte size has no fixed relation
/// to that floor. Re-applying a source-sized threshold to it here rejected
/// perfectly good headshots, and because a rejection was recorded as
/// "confirmed absent" the player then showed initials for the rest of the
/// session with no retry. `PlayerInitialsAvatar` still does pixel-level
/// black/placeholder detection on the decoded image, and falls back to
/// initials on any load error, so a bad or missing file degrades correctly
/// without this layer guessing from a byte count.
class FidePhotoService {
  FidePhotoService._();

  /// How long to wait before retrying after a transient failure.
  static const Duration _transientRetryBackoff = Duration(minutes: 2);

  /// Positive cache: fideId -> resolved URL.
  static final Map<String, String> _urlCache = {};

  /// Confirmed-absent: the edge function reported no photo for this player.
  /// Persists for the session.
  static final Set<String> _confirmedAbsent = {};

  /// Transient-failure timestamps. Entries expire after [_transientRetryBackoff].
  static final Map<String, DateTime> _transientFailures = {};

  /// Lookups currently in flight, keyed by fideId.
  ///
  /// Several widgets routinely ask for the same player at once — a scorecard
  /// header beside a list row, or three avatars in the onboarding cluster.
  /// Without this each one invoked the edge function separately, multiplying
  /// cold starts and pushing the function's own per-IP rate limit toward the
  /// point where it starts answering from its degraded path.
  static final Map<String, Future<String?>> _inFlight = {};

  /// Fetches or retrieves a cached FIDE profile photo URL.
  ///
  /// Returns null if no valid photo exists for the player.
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
      final pending = _inFlight[fideId];
      if (pending != null) return pending;
    }

    final request = _resolvePhotoUrl(fideId, forceRefresh: forceRefresh);
    _inFlight[fideId] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(fideId);
    }
  }

  static Future<String?> _resolvePhotoUrl(
    String fideId, {
    required bool forceRefresh,
  }) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'fetch-fide-photo-webp',
        method: HttpMethod.get,
        queryParameters: <String, dynamic>{
          'fide_id': fideId,
          if (forceRefresh) 'force_refresh': 'true',
        },
      );

      if (response.status == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final url = data['url'] as String?;

        if (url == null || url.isEmpty) {
          // The function distinguishes "this player has no photo" from "we
          // could not reach FIDE just now". Only the former is an answer.
          if (data['transient'] == true) {
            debugPrint(
              'FIDE photo unavailable for $fideId '
              '(transient: ${data['reason']}); will retry',
            );
            _transientFailures[fideId] = DateTime.now();
          } else {
            _markConfirmedAbsent(fideId);
          }
          return null;
        }

        _markResolved(fideId, url);
        return url;
      }

      // Non-200 from edge function: transient. Log, back off briefly, retry later.
      debugPrint('FIDE photo error (${response.status}): ${response.data}');
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
