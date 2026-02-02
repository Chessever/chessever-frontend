import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository();
});

class OnboardingRepository {
  /// Simple device-level key - shown once per fresh install
  static const String _baseKey = 'has_seen_onboarding';

  /// Per-user key to avoid cross-account pollution on the same device
  static String _userKey(String userId) => '${_baseKey}_$userId';

  String _resolveKey(String? userId) {
    if (userId != null && userId.isNotEmpty) {
      return _userKey(userId);
    }
    return _baseKey; // device/global fallback for pre-auth state
  }

  /// Check if onboarding has been shown on this device.
  Future<bool> hasSeenOnboarding({String? userId}) async {
    try {
      final supabaseUserId =
          userId ?? Supabase.instance.client.auth.currentUser?.id;
      final db = AppDatabase.instance;

      // Prefer user-specific flag if available
      final userKey = _resolveKey(supabaseUserId);
      final userSeen = await db.getBool(userKey);
      if (userSeen != null) return userSeen;

      // Fallback to device-level flag (pre-auth)
      final deviceSeen = await db.getBool(_baseKey);
      return deviceSeen ?? false;
    } catch (e) {
      // Local storage failure - assume not seen to be safe
      return false;
    }
  }

  /// Legacy method for backwards compatibility - delegates to hasSeenOnboarding
  Future<bool> isCompleted(String? userId) async {
    return hasSeenOnboarding(userId: userId);
  }

  /// Mark onboarding as seen on this device.
  Future<void> markAsSeen({String? userId}) async {
    try {
      final supabaseUserId =
          userId ?? Supabase.instance.client.auth.currentUser?.id;
      final db = AppDatabase.instance;

      // Always set the device-level flag
      await db.setBool(_baseKey, true);

      // Also set user-specific flag when we know the user
      if (supabaseUserId != null) {
        await db.setBool(_userKey(supabaseUserId), true);
      }
    } catch (e) {
      // Local storage failure is not critical
    }
  }

  /// Legacy method for backwards compatibility - delegates to markAsSeen
  Future<void> markCompleted(String? userId) async {
    await markAsSeen(userId: userId);
  }

  /// Reset onboarding (for testing/debugging).
  Future<void> resetOnboarding({String? userId}) async {
    try {
      final supabaseUserId =
          userId ?? Supabase.instance.client.auth.currentUser?.id;
      final db = AppDatabase.instance;
      await db.remove(_baseKey);
      if (supabaseUserId != null) {
        await db.remove(_userKey(supabaseUserId));
      }
    } catch (e) {
      // Local storage failure is not critical
    }
  }
}
