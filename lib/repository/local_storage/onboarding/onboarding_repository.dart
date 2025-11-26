import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository();
});

class OnboardingRepository {
  /// Simple device-level key - shown once per fresh install
  /// Using new key (v3) to reset for all users after this fix
  static const String _legacyDeviceKey = 'has_seen_onboarding_v3';

  /// Per-user key to avoid cross-account pollution on the same device
  static const String _baseKey = 'has_seen_onboarding_v4';
  static String _userKey(String userId) => '${_baseKey}_$userId';

  String _resolveKey(String? userId) {
    if (userId != null && userId.isNotEmpty) {
      return _userKey(userId);
    }
    return _baseKey; // device/global fallback for pre-auth state
  }

  /// Check if onboarding has been shown on this device.
  /// Simple boolean check - no user-specific or legacy logic.
  Future<bool> hasSeenOnboarding({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final supabaseUserId = userId ?? Supabase.instance.client.auth.currentUser?.id;

    // Prefer user-specific flag if available
    final userKey = _resolveKey(supabaseUserId);
    final userSeen = prefs.getBool(userKey);
    if (userSeen != null) return userSeen;

    // Fallback to device-level flag (pre-auth)
    final deviceSeen = prefs.getBool(_baseKey);
    if (deviceSeen != null) return deviceSeen;

    // Fallback to legacy key (v3)
    return prefs.getBool(_legacyDeviceKey) ?? false;
  }

  /// Legacy method for backwards compatibility - delegates to hasSeenOnboarding
  Future<bool> isCompleted(String? userId) async {
    return hasSeenOnboarding(userId: userId);
  }

  /// Mark onboarding as seen on this device.
  Future<void> markAsSeen({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final supabaseUserId = userId ?? Supabase.instance.client.auth.currentUser?.id;

    // Always set the device-level flag to avoid repeat onboarding on fresh installs
    await prefs.setBool(_baseKey, true);

    // Also set user-specific flag when we know the user
    if (supabaseUserId != null) {
      await prefs.setBool(_userKey(supabaseUserId), true);
    }

    // Clean up legacy key to prevent stale state from older versions
    await prefs.remove(_legacyDeviceKey);
  }

  /// Legacy method for backwards compatibility - delegates to markAsSeen
  Future<void> markCompleted(String? userId) async {
    await markAsSeen(userId: userId);
  }

  /// Reset onboarding (for testing/debugging).
  Future<void> resetOnboarding({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final supabaseUserId = userId ?? Supabase.instance.client.auth.currentUser?.id;
    await prefs.remove(_baseKey);
    await prefs.remove(_legacyDeviceKey);
    if (supabaseUserId != null) {
      await prefs.remove(_userKey(supabaseUserId));
    }
  }
}
