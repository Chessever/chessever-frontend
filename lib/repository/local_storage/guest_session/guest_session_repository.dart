import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final guestSessionRepositoryProvider = Provider<GuestSessionRepository>((ref) {
  return GuestSessionRepository();
});

/// Timestamps that drive the guest (anonymous) upgrade prompts.
@immutable
class GuestSessionTimestamps {
  const GuestSessionTimestamps({this.startedAt, this.lastPromptAt});

  /// When this device first continued as a guest. Null = never was a guest.
  final DateTime? startedAt;

  /// When the soft upgrade prompt was last shown, so we don't nag every open.
  final DateTime? lastPromptAt;

  static const empty = GuestSessionTimestamps();

  @override
  bool operator ==(Object other) =>
      other is GuestSessionTimestamps &&
      other.startedAt == startedAt &&
      other.lastPromptAt == lastPromptAt;

  @override
  int get hashCode => Object.hash(startedAt, lastPromptAt);
}

/// Device-level storage for the guest session clock.
///
/// Deliberately kept in SharedPreferences rather than the per-user sqlite
/// store: the clock belongs to the *install*, must survive the anonymous →
/// authenticated user id switch, and has to be readable before any user row
/// exists.
class GuestSessionRepository {
  static const String _startedAtKey = 'guest_session_started_at_ms';
  static const String _lastPromptAtKey = 'guest_session_last_prompt_at_ms';

  Future<SharedPreferences?> _prefs() {
    return SharedPreferencesService.instance.ensureInitialized();
  }

  DateTime? _readDate(SharedPreferences prefs, String key) {
    final millis = prefs.getInt(key);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<GuestSessionTimestamps> read() async {
    try {
      final prefs = await _prefs();
      if (prefs == null) return GuestSessionTimestamps.empty;
      return GuestSessionTimestamps(
        startedAt: _readDate(prefs, _startedAtKey),
        lastPromptAt: _readDate(prefs, _lastPromptAtKey),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GuestSession] Failed to read guest session: $e');
      }
      return GuestSessionTimestamps.empty;
    }
  }

  /// Stamps the start of the guest clock. Never moves an existing stamp, so a
  /// guest cannot reset their trial by re-running onboarding.
  Future<DateTime?> startIfMissing(DateTime now) async {
    try {
      final prefs = await _prefs();
      if (prefs == null) return null;
      final existing = _readDate(prefs, _startedAtKey);
      if (existing != null) return existing;
      await prefs.setInt(_startedAtKey, now.millisecondsSinceEpoch);
      return now;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GuestSession] Failed to stamp guest start: $e');
      }
      return null;
    }
  }

  Future<void> markPromptShown(DateTime now) async {
    try {
      final prefs = await _prefs();
      if (prefs == null) return;
      await prefs.setInt(_lastPromptAtKey, now.millisecondsSinceEpoch);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GuestSession] Failed to mark prompt shown: $e');
      }
    }
  }

  /// Called once the guest upgrades to a real account.
  Future<void> clear() async {
    try {
      final prefs = await _prefs();
      if (prefs == null) return;
      await prefs.remove(_startedAtKey);
      await prefs.remove(_lastPromptAtKey);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GuestSession] Failed to clear guest session: $e');
      }
    }
  }
}
