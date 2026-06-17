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
  // Favourite Players time-control filters (opt-out — default true)
  final bool fpClassical;
  final bool fpRapid;
  final bool fpBlitz;
  // Starred Events time-control filters (opt-out — default true)
  final bool seClassical;
  final bool seRapid;
  final bool seBlitz;
  // Configurable heads-up lead time: 10 or 30 minutes before round start
  final int headsUpLeadMinutes;

  const NotificationPreferences({
    required this.favoriteEventAlerts,
    required this.favoritePlayerAlerts,
    required this.headsUpAlerts,
    required this.liveGameUpdates,
    required this.dailyDigest,
    required this.callToActionAlerts,
    required this.bookUpdateAlerts,
    required this.fpClassical,
    required this.fpRapid,
    required this.fpBlitz,
    required this.seClassical,
    required this.seRapid,
    required this.seBlitz,
    required this.headsUpLeadMinutes,
  });

  NotificationPreferences copyWith({
    bool? favoriteEventAlerts,
    bool? favoritePlayerAlerts,
    bool? headsUpAlerts,
    bool? liveGameUpdates,
    bool? dailyDigest,
    bool? callToActionAlerts,
    bool? bookUpdateAlerts,
    bool? fpClassical,
    bool? fpRapid,
    bool? fpBlitz,
    bool? seClassical,
    bool? seRapid,
    bool? seBlitz,
    int? headsUpLeadMinutes,
  }) {
    return NotificationPreferences(
      favoriteEventAlerts: favoriteEventAlerts ?? this.favoriteEventAlerts,
      favoritePlayerAlerts: favoritePlayerAlerts ?? this.favoritePlayerAlerts,
      headsUpAlerts: headsUpAlerts ?? this.headsUpAlerts,
      liveGameUpdates: liveGameUpdates ?? this.liveGameUpdates,
      dailyDigest: dailyDigest ?? this.dailyDigest,
      callToActionAlerts: callToActionAlerts ?? this.callToActionAlerts,
      bookUpdateAlerts: bookUpdateAlerts ?? this.bookUpdateAlerts,
      fpClassical: fpClassical ?? this.fpClassical,
      fpRapid: fpRapid ?? this.fpRapid,
      fpBlitz: fpBlitz ?? this.fpBlitz,
      seClassical: seClassical ?? this.seClassical,
      seRapid: seRapid ?? this.seRapid,
      seBlitz: seBlitz ?? this.seBlitz,
      headsUpLeadMinutes: headsUpLeadMinutes ?? this.headsUpLeadMinutes,
    );
  }

  static const defaults = NotificationPreferences(
    favoriteEventAlerts: true,
    favoritePlayerAlerts: true,
    headsUpAlerts: false,
    liveGameUpdates: false,
    dailyDigest: false,
    callToActionAlerts: false,
    bookUpdateAlerts: true,
    fpClassical: true,
    fpRapid: true,
    // Blitz notifications are OFF by default — users opt in manually.
    fpBlitz: false,
    seClassical: true,
    seRapid: true,
    seBlitz: false,
    headsUpLeadMinutes: 30,
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
                'favorite_event_alerts,favorite_player_alerts,heads_up_alerts,'
                'live_game_updates,daily_digest,call_to_action_alerts,'
                'book_update_alerts,'
                'fp_classical,fp_rapid,fp_blitz,'
                'se_classical,se_rapid,se_blitz,'
                'heads_up_lead_minutes',
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
        fpClassical:
            response['fp_classical'] as bool? ??
            NotificationPreferences.defaults.fpClassical,
        fpRapid:
            response['fp_rapid'] as bool? ??
            NotificationPreferences.defaults.fpRapid,
        fpBlitz:
            response['fp_blitz'] as bool? ??
            NotificationPreferences.defaults.fpBlitz,
        seClassical:
            response['se_classical'] as bool? ??
            NotificationPreferences.defaults.seClassical,
        seRapid:
            response['se_rapid'] as bool? ??
            NotificationPreferences.defaults.seRapid,
        seBlitz:
            response['se_blitz'] as bool? ??
            NotificationPreferences.defaults.seBlitz,
        headsUpLeadMinutes:
            response['heads_up_lead_minutes'] as int? ??
            NotificationPreferences.defaults.headsUpLeadMinutes,
      );

      unawaited(_cachePreferences(prefs));
      return prefs;
    } catch (e, st) {
      debugPrint('[NotificationPreferences] Error: $e');
      debugPrintStack(stackTrace: st);
      return await _getCachedPreferences();
    }
  }

  // ---------------------------------------------------------------------------
  // Setters — parent toggles
  // ---------------------------------------------------------------------------

  /// Enables favourite-player alerts and auto-resets all three sub-filters to
  /// true (matching the "all selected" initial state shown in the UI).
  /// Disabling only silences the parent; sub-filter choices are preserved.
  Future<void> setFavoritePlayerAlerts(bool value) async {
    await _updatePreferences((prefs) {
      if (value) {
        return prefs.copyWith(
          favoritePlayerAlerts: true,
          fpClassical: true,
          fpRapid: true,
          // Blitz stays off on parent re-enable — manual opt-in only.
          fpBlitz: false,
        );
      }
      return prefs.copyWith(favoritePlayerAlerts: false);
    });
  }

  /// Enables starred-event alerts and auto-resets all three sub-filters to
  /// true.  Disabling preserves sub-filter choices.
  Future<void> setFavoriteEventAlerts(bool value) async {
    await _updatePreferences((prefs) {
      if (value) {
        return prefs.copyWith(
          favoriteEventAlerts: true,
          seClassical: true,
          seRapid: true,
          // Blitz stays off on parent re-enable — manual opt-in only.
          seBlitz: false,
        );
      }
      return prefs.copyWith(favoriteEventAlerts: false);
    });
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

  // ---------------------------------------------------------------------------
  // Setters — Favourite Players time-control sub-filters
  // ---------------------------------------------------------------------------

  Future<void> setFpClassical(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(fpClassical: value));
  }

  Future<void> setFpRapid(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(fpRapid: value));
  }

  Future<void> setFpBlitz(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(fpBlitz: value));
  }

  // ---------------------------------------------------------------------------
  // Setters — Starred Events time-control sub-filters
  // ---------------------------------------------------------------------------

  Future<void> setSeClassical(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(seClassical: value));
  }

  Future<void> setSeRapid(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(seRapid: value));
  }

  Future<void> setSeBlitz(bool value) async {
    await _updatePreferences((prefs) => prefs.copyWith(seBlitz: value));
  }

  // ---------------------------------------------------------------------------
  // Setter — heads-up lead time
  // ---------------------------------------------------------------------------

  /// [value] must be either 10 or 30.
  Future<void> setHeadsUpLeadMinutes(int value) async {
    assert(value == 10 || value == 30, 'headsUpLeadMinutes must be 10 or 30');
    await _updatePreferences(
      (prefs) => prefs.copyWith(headsUpLeadMinutes: value),
    );
  }

  Future<void> disableAll() async {
    await _updatePreferences(
      (current) => NotificationPreferences(
        favoriteEventAlerts: false,
        favoritePlayerAlerts: false,
        headsUpAlerts: false,
        liveGameUpdates: false,
        dailyDigest: false,
        callToActionAlerts: false,
        bookUpdateAlerts: false,
        // Time-control filters remain as-is — disableAll only silences alerts,
        // not the user's personal filter preferences.
        fpClassical: current.fpClassical,
        fpRapid: current.fpRapid,
        fpBlitz: current.fpBlitz,
        seClassical: current.seClassical,
        seRapid: current.seRapid,
        seBlitz: current.seBlitz,
        headsUpLeadMinutes: current.headsUpLeadMinutes,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<void> _updatePreferences(
    NotificationPreferences Function(NotificationPreferences) update,
  ) async {
    final current = state.valueOrNull ?? NotificationPreferences.defaults;
    final updated = update(current);
    state = AsyncValue.data(updated);

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
        'fp_classical': updated.fpClassical,
        'fp_rapid': updated.fpRapid,
        'fp_blitz': updated.fpBlitz,
        'se_classical': updated.seClassical,
        'se_rapid': updated.seRapid,
        'se_blitz': updated.seBlitz,
        'heads_up_lead_minutes': updated.headsUpLeadMinutes,
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
        'fpClassical': prefs.fpClassical,
        'fpRapid': prefs.fpRapid,
        'fpBlitz': prefs.fpBlitz,
        'seClassical': prefs.seClassical,
        'seRapid': prefs.seRapid,
        'seBlitz': prefs.seBlitz,
        'headsUpLeadMinutes': prefs.headsUpLeadMinutes,
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
        // New category-specific filters — fall back to legacy shared keys if
        // the cache was written by an older build that used notifyClassical etc.
        fpClassical:
            (map['fpClassical'] ?? map['notifyClassical']) as bool? ??
            NotificationPreferences.defaults.fpClassical,
        fpRapid:
            (map['fpRapid'] ?? map['notifyRapid']) as bool? ??
            NotificationPreferences.defaults.fpRapid,
        fpBlitz:
            (map['fpBlitz'] ?? map['notifyBlitz']) as bool? ??
            NotificationPreferences.defaults.fpBlitz,
        seClassical:
            (map['seClassical'] ?? map['notifyClassical']) as bool? ??
            NotificationPreferences.defaults.seClassical,
        seRapid:
            (map['seRapid'] ?? map['notifyRapid']) as bool? ??
            NotificationPreferences.defaults.seRapid,
        seBlitz:
            (map['seBlitz'] ?? map['notifyBlitz']) as bool? ??
            NotificationPreferences.defaults.seBlitz,
        headsUpLeadMinutes:
            map['headsUpLeadMinutes'] as int? ??
            NotificationPreferences.defaults.headsUpLeadMinutes,
      );
    } catch (e) {
      debugPrint('[NotificationPreferences] Error reading cache: $e');
      return NotificationPreferences.defaults;
    }
  }
}
