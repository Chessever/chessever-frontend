import 'dart:async';

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

  const NotificationPreferences({
    required this.favoriteEventAlerts,
    required this.favoritePlayerAlerts,
    required this.headsUpAlerts,
    required this.liveGameUpdates,
    required this.dailyDigest,
  });

  NotificationPreferences copyWith({
    bool? favoriteEventAlerts,
    bool? favoritePlayerAlerts,
    bool? headsUpAlerts,
    bool? liveGameUpdates,
    bool? dailyDigest,
  }) {
    return NotificationPreferences(
      favoriteEventAlerts: favoriteEventAlerts ?? this.favoriteEventAlerts,
      favoritePlayerAlerts: favoritePlayerAlerts ?? this.favoritePlayerAlerts,
      headsUpAlerts: headsUpAlerts ?? this.headsUpAlerts,
      liveGameUpdates: liveGameUpdates ?? this.liveGameUpdates,
      dailyDigest: dailyDigest ?? this.dailyDigest,
    );
  }

  static const defaults = NotificationPreferences(
    favoriteEventAlerts: true,
    favoritePlayerAlerts: true,
    headsUpAlerts: false,
    liveGameUpdates: true,
    dailyDigest: true,
  );
}

final notificationPreferencesProvider =
    AsyncNotifierProvider<NotificationPreferencesNotifier, NotificationPreferences>(
  NotificationPreferencesNotifier.new,
);

class NotificationPreferencesNotifier
    extends AsyncNotifier<NotificationPreferences> {
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
      final response = await _supabase
          .from('user_notification_preferences')
          .select(
            'favorite_event_alerts,favorite_player_alerts,heads_up_alerts,live_game_updates,daily_digest',
          )
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        return NotificationPreferences.defaults;
      }

      return NotificationPreferences(
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
      );
    } catch (e, st) {
      debugPrint('[NotificationPreferences] Error: $e');
      debugPrintStack(stackTrace: st);
      return NotificationPreferences.defaults;
    }
  }

  Future<void> setFavoriteEventAlerts(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(
      favoriteEventAlerts: value,
    ));
  }

  Future<void> setFavoritePlayerAlerts(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(
      favoritePlayerAlerts: value,
    ));
  }

  Future<void> setHeadsUpAlerts(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(
      headsUpAlerts: value,
    ));
  }

  Future<void> setLiveGameUpdates(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(
      liveGameUpdates: value,
    ));
  }

  Future<void> setDailyDigest(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(
      dailyDigest: value,
    ));
  }

  Future<void> _updatePreferences(
    NotificationPreferences Function(NotificationPreferences) update,
  ) async {
    final current = state.valueOrNull ?? NotificationPreferences.defaults;
    final updated = update(current);
    state = AsyncValue.data(updated);

    final userId = _currentUserId();
    if (userId == null) return;

    try {
      await _supabase.from('user_notification_preferences').upsert(
        {
          'user_id': userId,
          'favorite_event_alerts': updated.favoriteEventAlerts,
          'favorite_player_alerts': updated.favoritePlayerAlerts,
          'heads_up_alerts': updated.headsUpAlerts,
          'live_game_updates': updated.liveGameUpdates,
          'daily_digest': updated.dailyDigest,
        },
        onConflict: 'user_id',
      );
    } catch (e, st) {
      debugPrint('[NotificationPreferences] Update failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }
}
