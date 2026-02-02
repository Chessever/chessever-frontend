import 'dart:async';
import 'dart:convert';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider for managing event favorites
/// Business logic lives here, not in a separate repository
final favoriteEventsProvider =
    AsyncNotifierProvider<FavoriteEventsNotifier, List<FavoriteEvent>>(
  FavoriteEventsNotifier.new,
);

class FavoriteEventsNotifier extends AsyncNotifier<List<FavoriteEvent>> {
  static const String _cacheKey = 'cached_favorite_events';

  SupabaseClient get _supabase => Supabase.instance.client;

  String? _getCurrentUserId() => _supabase.auth.currentUser?.id;

  @override
  Future<List<FavoriteEvent>> build() async {
    return await _loadFavorites();
  }

  Future<List<FavoriteEvent>> _loadFavorites() async {
    try {
      final cached = await _getCachedEvents();
      if (cached.isNotEmpty) {
        unawaited(_refreshFromSupabase());
        return cached;
      }

      return await _fetchFavoritesFromSupabase();
    } catch (e, st) {
      debugPrint('[FavoriteEvents] Error fetching from Supabase: $e');
      debugPrint('[FavoriteEvents] Stack: $st');

      // Fallback to local cache
      return await _getCachedEvents();
    }
  }

  Future<List<FavoriteEvent>> _fetchFavoritesFromSupabase() async {
    final userId = _getCurrentUserId();
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

    final events =
        (response as List)
            .map((json) => FavoriteEvent.fromSupabase(json))
            .toList();

    // Cache locally
    await _cacheEvents(events, userId);

    debugPrint('[FavoriteEvents] Fetched ${events.length} events from Supabase');
    return events;
  }

  Future<void> _refreshFromSupabase() async {
    try {
      final events = await _fetchFavoritesFromSupabase();
      state = AsyncValue.data(events);
      _syncFavoriteCountAnalytics(events.length);
    } catch (e, st) {
      debugPrint('[FavoriteEvents] Refresh error: $e');
      debugPrint('[FavoriteEvents] Stack: $st');
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
    final userId = _getCurrentUserId();
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
    await _cacheEvents(updatedEvents, userId);

    try {
      // STEP 2: Sync to Supabase in background (upsert prevents duplicates)
      await _supabase.from('user_favorite_events').upsert(
        {
          'user_id': userId,
          'event_id': eventId,
          'event_name': eventName,
          'metadata': metadata,
        },
        onConflict: 'user_id,event_id',
        ignoreDuplicates: true,
      );

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
      await _cacheEvents(currentEvents, userId);
      rethrow;
    }
  }

  /// Remove event from favorites (optimistic update)
  Future<void> removeFavorite(String eventId) async {
    final userId = _getCurrentUserId();
    if (userId == null) {
      throw Exception('User must be logged in to remove favorites');
    }

    // STEP 1: Optimistic update - update state immediately
    final currentEvents = state.valueOrNull ?? [];
    final updatedEvents = currentEvents.where((e) => e.eventId != eventId).toList();
    state = AsyncValue.data(updatedEvents);

    // Cache immediately
    await _cacheEvents(updatedEvents, userId);

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
      await _cacheEvents(currentEvents, userId);
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
  Future<void> _cacheEvents(List<FavoriteEvent> events, String? userId) async {
    try {
      final db = AppDatabase.instance;
      final json = jsonEncode(events.map((e) => e.toSupabase()).toList());
      await db.setCache(key: _cacheKey, value: json, userId: userId);
      debugPrint('[FavoriteEvents] Cached ${events.length} events locally');
    } catch (e) {
      debugPrint('[FavoriteEvents] Error caching events: $e');
    }
  }

  Future<List<FavoriteEvent>> _getCachedEvents() async {
    try {
      final db = AppDatabase.instance;
      final userId = _getCurrentUserId();
      final entry = await db.getCache(key: _cacheKey, userId: userId);
      if (entry == null) return [];

      final list = jsonDecode(entry.value) as List;
      return list.map((json) => FavoriteEvent.fromSupabase(json)).toList();
    } catch (e) {
      debugPrint('[FavoriteEvents] Error getting cached events: $e');
      return [];
    }
  }

  /// Clear cache (useful on sign out)
  Future<void> clearCache() async {
    try {
      final db = AppDatabase.instance;
      final userId = _getCurrentUserId();
      await db.removeCache(key: _cacheKey, userId: userId);
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
