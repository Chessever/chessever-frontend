import 'dart:async';
import 'dart:convert';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider for managing event favorites
/// Business logic lives here, not in a separate repository
final favoriteEventsProvider =
    AsyncNotifierProvider<FavoriteEventsNotifier, List<FavoriteEvent>>(
  FavoriteEventsNotifier.new,
);

class FavoriteEventsNotifier extends AsyncNotifier<List<FavoriteEvent>> {
  static const String _cacheKeyPrefix = 'cached_favorite_events_';

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Get user-specific cache key to prevent cross-user cache pollution
  String get _cacheKey {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return '${_cacheKeyPrefix}anonymous';
    return '$_cacheKeyPrefix$userId';
  }

  @override
  Future<List<FavoriteEvent>> build() async {
    return await _loadFavorites();
  }

  Future<List<FavoriteEvent>> _loadFavorites() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[FavoriteEvents] No user logged in, returning empty list');
        return [];
      }

      // Fetch from Supabase (source of truth)
      final response = await _supabase
          .from('user_favorite_events')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final events = (response as List)
          .map((json) => FavoriteEvent.fromSupabase(json))
          .toList();

      // Cache locally
      await _cacheEvents(events);

      debugPrint('[FavoriteEvents] Fetched ${events.length} events from Supabase');
      return events;
    } catch (e, st) {
      debugPrint('[FavoriteEvents] Error fetching from Supabase: $e');
      debugPrint('[FavoriteEvents] Stack: $st');

      // Fallback to local cache
      return await _getCachedEvents();
    }
  }

  /// Add event to favorites (optimistic update)
  Future<void> addFavorite({
    required String eventId,
    required String eventName,
    String? timeControl,
    int? maxAvgElo,
    String? dates,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User must be logged in to favorite events');
    }

    final metadata = <String, dynamic>{
      if (timeControl != null) 'timeControl': timeControl,
      if (maxAvgElo != null) 'maxAvgElo': maxAvgElo,
      if (dates != null) 'dates': dates,
    };

    // Create optimistic event
    final optimisticEvent = FavoriteEvent(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      eventId: eventId,
      eventName: eventName,
      metadata: metadata,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // STEP 1: Optimistic update - update state immediately
    final currentEvents = state.valueOrNull ?? [];
    final updatedEvents = [...currentEvents, optimisticEvent];
    state = AsyncValue.data(updatedEvents);

    // Cache immediately
    await _cacheEvents(updatedEvents);

    try {
      // STEP 2: Sync to Supabase in background
      await _supabase.from('user_favorite_events').upsert({
        'user_id': userId,
        'event_id': eventId,
        'event_name': eventName,
        'metadata': metadata,
      });

      debugPrint('[FavoriteEvents] Added event $eventId to Supabase');

      // STEP 3: Fetch fresh data from Supabase (without loading state)
      final freshEvents = await _loadFavorites();
      state = AsyncValue.data(freshEvents);
      _syncFavoriteCountAnalytics(freshEvents.length);
    } catch (e, st) {
      debugPrint('[FavoriteEvents] Error adding event: $e');
      debugPrint('[FavoriteEvents] Stack: $st');

      // STEP 4: Revert optimistic update on error
      state = AsyncValue.data(currentEvents);
      await _cacheEvents(currentEvents);
      rethrow;
    }
  }

  /// Remove event from favorites (optimistic update)
  Future<void> removeFavorite(String eventId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User must be logged in to remove favorites');
    }

    // STEP 1: Optimistic update - update state immediately
    final currentEvents = state.valueOrNull ?? [];
    final updatedEvents = currentEvents.where((e) => e.eventId != eventId).toList();
    state = AsyncValue.data(updatedEvents);

    // Cache immediately
    await _cacheEvents(updatedEvents);

    try {
      // STEP 2: Sync to Supabase in background
      await _supabase
          .from('user_favorite_events')
          .delete()
          .eq('user_id', userId)
          .eq('event_id', eventId);

      debugPrint('[FavoriteEvents] Removed event $eventId from Supabase');

      // STEP 3: Fetch fresh data from Supabase (without loading state)
      final freshEvents = await _loadFavorites();
      state = AsyncValue.data(freshEvents);
      _syncFavoriteCountAnalytics(freshEvents.length);
    } catch (e, st) {
      debugPrint('[FavoriteEvents] Error removing event: $e');
      debugPrint('[FavoriteEvents] Stack: $st');

      // STEP 4: Revert optimistic update on error
      state = AsyncValue.data(currentEvents);
      await _cacheEvents(currentEvents);
      rethrow;
    }
  }

  /// Toggle event favorite status
  Future<bool> toggleFavorite({
    required String eventId,
    required String eventName,
    String? timeControl,
    int? maxAvgElo,
    String? dates,
  }) async {
    final currentState = state.valueOrNull ?? [];
    final isFavorited = currentState.any((e) => e.eventId == eventId);

    if (isFavorited) {
      await removeFavorite(eventId);
      return false;
    } else {
      await addFavorite(
        eventId: eventId,
        eventName: eventName,
        timeControl: timeControl,
        maxAvgElo: maxAvgElo,
        dates: dates,
      );
      return true;
    }
  }

  /// Check if event is favorited
  bool isFavorited(String eventId) {
    final currentState = state.valueOrNull;
    if (currentState == null) return false;
    return currentState.any((e) => e.eventId == eventId);
  }

  /// Refresh favorites from Supabase
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadFavorites());
  }

  /// Sync favorites from Supabase to local cache
  Future<void> syncFromSupabase() async {
    debugPrint('[FavoriteEvents] Starting sync...');
    try {
      await refresh();
      debugPrint('[FavoriteEvents] Sync complete');
    } catch (e, st) {
      debugPrint('[FavoriteEvents] Error syncing: $e');
      debugPrint('[FavoriteEvents] Stack: $st');
    }
  }

  // Cache management
  Future<void> _cacheEvents(List<FavoriteEvent> events) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(events.map((e) => e.toSupabase()).toList());
      await prefs.setString(_cacheKey, json);
      debugPrint('[FavoriteEvents] Cached ${events.length} events locally');
    } catch (e) {
      debugPrint('[FavoriteEvents] Error caching events: $e');
    }
  }

  Future<List<FavoriteEvent>> _getCachedEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey);
      if (json == null) return [];

      final list = jsonDecode(json) as List;
      return list.map((json) => FavoriteEvent.fromSupabase(json)).toList();
    } catch (e) {
      debugPrint('[FavoriteEvents] Error getting cached events: $e');
      return [];
    }
  }

  /// Clear cache (useful on sign out)
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      debugPrint('[FavoriteEvents] Cleared cache');
    } catch (e) {
      debugPrint('[FavoriteEvents] Error clearing cache: $e');
    }
  }

  void _syncFavoriteCountAnalytics(int count) {
    unawaited(
      AnalyticsService.instance.setUserProperties({
        'favorite_event_count': count,
      }),
    );
  }
}

/// Provider to check if a specific event is favorited
final isEventFavoritedProvider =
    Provider.family<bool, String>((ref, eventId) {
  final favorites = ref.watch(favoriteEventsProvider);
  return favorites.maybeWhen(
    data: (events) => events.any((e) => e.eventId == eventId),
    orElse: () => false,
  );
});
