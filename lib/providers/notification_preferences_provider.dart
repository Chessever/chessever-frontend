import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_state_provider.dart';

class NotificationPreferences {
  final bool favoriteEventAlerts;
  final bool favoritePlayerAlerts;
  final bool headsUpAlerts;
  final bool liveGameUpdates;
  final bool dailyDigest;
  final bool callToActionAlerts;
  final bool bookUpdateAlerts;

  const NotificationPreferences({
    required this.favoriteEventAlerts,
    required this.favoritePlayerAlerts,
    required this.headsUpAlerts,
    required this.liveGameUpdates,
    required this.dailyDigest,
    required this.callToActionAlerts,
    required this.bookUpdateAlerts,
  });

  NotificationPreferences copyWith({
    bool? favoriteEventAlerts,
    bool? favoritePlayerAlerts,
    bool? headsUpAlerts,
    bool? liveGameUpdates,
    bool? dailyDigest,
    bool? callToActionAlerts,
    bool? bookUpdateAlerts,
  }) {
    return NotificationPreferences(
      favoriteEventAlerts: favoriteEventAlerts ?? this.favoriteEventAlerts,
      favoritePlayerAlerts: favoritePlayerAlerts ?? this.favoritePlayerAlerts,
      headsUpAlerts: headsUpAlerts ?? this.headsUpAlerts,
      liveGameUpdates: liveGameUpdates ?? this.liveGameUpdates,
      dailyDigest: dailyDigest ?? this.dailyDigest,
      callToActionAlerts: callToActionAlerts ?? this.callToActionAlerts,
      bookUpdateAlerts: bookUpdateAlerts ?? this.bookUpdateAlerts,
    );
  }

  static const defaults = NotificationPreferences(
    favoriteEventAlerts: false,
    favoritePlayerAlerts: true,
    headsUpAlerts: false,
    liveGameUpdates: false,
    dailyDigest: false,
    callToActionAlerts: false,
    bookUpdateAlerts: true,
  );
}

final notificationPreferencesProvider = AsyncNotifierProvider<
  NotificationPreferencesNotifier,
  NotificationPreferences
>(NotificationPreferencesNotifier.new);

class NotificationPreferencesNotifier
    extends AsyncNotifier<NotificationPreferences> {
  static const String _cacheKey = 'cached_notification_preferences';

  SupabaseClient get _supabase => Supabase.instance.client;
  bool _listening = false;

  @override
  Future<NotificationPreferences> build() async {
    if (!_listening) {
      _listening = true;
      ref.listen(currentUserProvider, (prev, next) {
        if (prev?.id != next?.id) {
          unawaited(_reloadForUser());
        }
      });
    }

    return _fetchPreferences();
  }

  Future<void> _reloadForUser() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchPreferences);
  }

  String? _currentUserId() => _supabase.auth.currentUser?.id;

  Future<NotificationPreferences> _fetchPreferences() async {
    final userId = _currentUserId();
    if (userId == null) {
      return NotificationPreferences.defaults;
    }

    try {
      final response =
          await _supabase
              .from('user_notification_preferences')
              .select(
                'favorite_event_alerts,favorite_player_alerts,heads_up_alerts,live_game_updates,daily_digest,call_to_action_alerts,book_update_alerts',
              )
              .eq('user_id', userId)
              .maybeSingle();

      if (response == null) {
        return NotificationPreferences.defaults;
      }

      final prefs = NotificationPreferences(
        favoriteEventAlerts:
            response['favorite_event_alerts'] as bool? ??
            NotificationPreferences.defaults.favoriteEventAlerts,
        favoritePlayerAlerts:
            response['favorite_player_alerts'] as bool? ??
            NotificationPreferences.defaults.favoritePlayerAlerts,
        headsUpAlerts:
            response['heads_up_alerts'] as bool? ??
            NotificationPreferences.defaults.headsUpAlerts,
        liveGameUpdates:
            response['live_game_updates'] as bool? ??
            NotificationPreferences.defaults.liveGameUpdates,
        dailyDigest:
            response['daily_digest'] as bool? ??
            NotificationPreferences.defaults.dailyDigest,
        callToActionAlerts:
            response['call_to_action_alerts'] as bool? ??
            NotificationPreferences.defaults.callToActionAlerts,
        bookUpdateAlerts:
            response['book_update_alerts'] as bool? ??
            NotificationPreferences.defaults.bookUpdateAlerts,
      );

      // Cache locally for offline fallback (non-blocking)
      unawaited(_cachePreferences(prefs));
      return prefs;
    } catch (e, st) {
      debugPrint('[NotificationPreferences] Error: $e');
      debugPrintStack(stackTrace: st);
      // Fallback to local cache
      return await _getCachedPreferences();
    }
  }

  Future<void> setFavoriteEventAlerts(bool value) async {
    await _updatePreferences(
      (prefs) => prefs.copyWith(favoriteEventAlerts: value),
    );
  }

  Future<void> setFavoritePlayerAlerts(bool value) async {
    await _updatePreferences(
      (prefs) => prefs.copyWith(favoritePlayerAlerts: value),
    );
  }

  Future<void> setHeadsUpAlerts(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(headsUpAlerts: value));
  }

  Future<void> setLiveGameUpdates(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(liveGameUpdates: value));
  }

  Future<void> setDailyDigest(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(dailyDigest: value));
  }

  Future<void> setCallToActionAlerts(bool value) async {
    await _updatePreferences(
      (prefs) => prefs.copyWith(callToActionAlerts: value),
    );
  }

  Future<void> setBookUpdateAlerts(bool value) async {
    await _updatePreferences(
      (prefs) => prefs.copyWith(bookUpdateAlerts: value),
    );
  }

  Future<void> disableAll() async {
    await _updatePreferences(
      (_) => const NotificationPreferences(
        favoriteEventAlerts: false,
        favoritePlayerAlerts: false,
        headsUpAlerts: false,
        liveGameUpdates: false,
        dailyDigest: false,
        callToActionAlerts: false,
        bookUpdateAlerts: false,
      ),
    );
  }

  Future<void> _updatePreferences(
    NotificationPreferences Function(NotificationPreferences) update,
  ) async {
    final current = state.valueOrNull ?? NotificationPreferences.defaults;
    final updated = update(current);
    state = AsyncValue.data(updated);

    // Cache locally in background (best-effort fallback only)
    unawaited(_cachePreferences(updated));

    final userId = _currentUserId();
    if (userId == null) return;

    try {
      await _supabase.from('user_notification_preferences').upsert({
        'user_id': userId,
        'favorite_event_alerts': updated.favoriteEventAlerts,
        'favorite_player_alerts': updated.favoritePlayerAlerts,
        'heads_up_alerts': updated.headsUpAlerts,
        'live_game_updates': updated.liveGameUpdates,
        'daily_digest': updated.dailyDigest,
        'call_to_action_alerts': updated.callToActionAlerts,
        'book_update_alerts': updated.bookUpdateAlerts,
      }, onConflict: 'user_id');
    } catch (e, st) {
      debugPrint('[NotificationPreferences] Update failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> _cachePreferences(NotificationPreferences prefs) async {
    try {
      final db = AppDatabase.instance;
      final json = jsonEncode({
        'favoriteEventAlerts': prefs.favoriteEventAlerts,
        'favoritePlayerAlerts': prefs.favoritePlayerAlerts,
        'headsUpAlerts': prefs.headsUpAlerts,
        'liveGameUpdates': prefs.liveGameUpdates,
        'dailyDigest': prefs.dailyDigest,
        'callToActionAlerts': prefs.callToActionAlerts,
        'bookUpdateAlerts': prefs.bookUpdateAlerts,
      });
      await db.setString(_cacheKey, json);
    } catch (e) {
      debugPrint('[NotificationPreferences] Error caching: $e');
    }
  }

  Future<NotificationPreferences> _getCachedPreferences() async {
    try {
      final db = AppDatabase.instance;
      final json = await db.getString(_cacheKey);
      if (json == null) {
        return NotificationPreferences.defaults;
      }

      final map = jsonDecode(json) as Map<String, dynamic>;
      return NotificationPreferences(
        favoriteEventAlerts:
            map['favoriteEventAlerts'] as bool? ??
            NotificationPreferences.defaults.favoriteEventAlerts,
        favoritePlayerAlerts:
            map['favoritePlayerAlerts'] as bool? ??
            NotificationPreferences.defaults.favoritePlayerAlerts,
        headsUpAlerts:
            map['headsUpAlerts'] as bool? ??
            NotificationPreferences.defaults.headsUpAlerts,
        liveGameUpdates:
            map['liveGameUpdates'] as bool? ??
            NotificationPreferences.defaults.liveGameUpdates,
        dailyDigest:
            map['dailyDigest'] as bool? ??
            NotificationPreferences.defaults.dailyDigest,
        callToActionAlerts:
            map['callToActionAlerts'] as bool? ??
            NotificationPreferences.defaults.callToActionAlerts,
        bookUpdateAlerts:
            map['bookUpdateAlerts'] as bool? ??
            NotificationPreferences.defaults.bookUpdateAlerts,
      );
    } catch (e) {
      debugPrint('[NotificationPreferences] Error reading cache: $e');
      return NotificationPreferences.defaults;
    }
  }
}
