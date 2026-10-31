import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Async storage is shared across FCM isolates; background never writes intent.
/// A late old callback has its own request key and cannot overwrite newer intent.
class NewsBindingStore {
  static const audience = 'chessever.favorite-player-news.v1';
  static const type = 'news_binding_challenge';
  static const intentKey = 'direct_push_news_binding_intent_v1';
  static const callbackPrefix = 'direct_push_news_binding_callback_v1_';
  SharedPreferencesAsync get prefs => SharedPreferencesAsync();
  static String tokenHash(String token) =>
      sha256.convert(utf8.encode(token)).toString();
  static String requestId() {
    final r = Random.secure();
    final h = List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-8${h.substring(17, 20)}-${h.substring(20)}';
  }

  Future<Map<String, dynamic>?> intent() async {
    final raw = await prefs.getString(intentKey);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> save(Map<String, dynamic> value) =>
      prefs.setString(intentKey, jsonEncode(value));
  Future<void> clear() async {
    await prefs.remove(intentKey);
    final keys = await prefs.getKeys();
    for (final key in keys.where((k) => k.startsWith(callbackPrefix))) {
      await prefs.remove(key);
    }
  }

  static bool matches(
    Map<String, dynamic> data,
    Map<String, dynamic> intent, {
    DateTime? now,
  }) {
    final expiry = DateTime.tryParse(
      data['expiresAt'] is String ? data['expiresAt'] as String : '',
    );
    final revision = data['registrationRevision'];
    return data['type'] == type &&
        data['audience'] == audience &&
        data['installationId'] == intent['installationId'] &&
        data['userId'] == intent['userId'] &&
        data['requestId'] == intent['requestId'] &&
        revision is String &&
        revision == intent['registrationRevision'].toString() &&
        data['tokenHash'] == tokenHash(intent['token'] as String) &&
        data['platform'] == intent['platform'] &&
        data['challengeId'] is String &&
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(data['challengeId'] as String) &&
        data['nonce'] is String &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(data['nonce'] as String) &&
        expiry != null &&
        expiry.isAfter(now ?? DateTime.now()) &&
        expiry.isBefore(
          (now ?? DateTime.now()).add(const Duration(minutes: 6)),
        );
  }

  /// Returns true for ALL reserved-type messages, including malformed/unknown:
  /// callers must never turn them into a notification, receipt or navigation.
  Future<bool> receive(Map<String, dynamic> data) async {
    if (data['type'] != type) return false;
    try {
      final active = await intent();
      if (active != null && matches(data, active)) {
        await prefs.setString(
          '$callbackPrefix${active['requestId']}',
          jsonEncode(data),
        );
      }
    } catch (_) {
      /* Invalid/local storage failure stays silent and pending. */
    }
    return true;
  }

  Future<Map<String, dynamic>?> callback(Map<String, dynamic> active) async {
    final raw = await prefs.getString('$callbackPrefix${active['requestId']}');
    if (raw == null) return null;
    final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return matches(data, active) ? data : null;
  }
}
