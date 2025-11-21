import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository();
});

class OnboardingRepository {
  /// Device-level key for onboarding completion (survives reinstalls via backup)
  static const String _deviceOnboardingKey = 'onboarding_completed_v2';

  /// Legacy user-specific key (for migration)
  static const String _completedUsersKey = 'player_follow_onboarding_users_v1';

  /// Check if onboarding has been completed on this device.
  /// Uses device-level flag that doesn't depend on user authentication.
  Future<bool> isCompleted(String? userId) async {
    final prefs = await SharedPreferences.getInstance();

    // First check device-level flag (new approach)
    final deviceCompleted = prefs.getBool(_deviceOnboardingKey) ?? false;
    if (deviceCompleted) return true;

    // Fallback: check legacy user-specific completion for migration
    if (userId != null && userId.isNotEmpty) {
      final completedUsers = prefs.getStringList(_completedUsersKey) ?? [];
      if (completedUsers.contains(userId)) {
        // Migrate to device-level flag
        await prefs.setBool(_deviceOnboardingKey, true);
        return true;
      }
    }

    return false;
  }

  /// Mark onboarding as completed at device level.
  /// Also stores userId for legacy compatibility.
  Future<void> markCompleted(String? userId) async {
    final prefs = await SharedPreferences.getInstance();

    // Set device-level flag (primary)
    await prefs.setBool(_deviceOnboardingKey, true);

    // Also store userId for legacy tracking (optional)
    if (userId != null && userId.isNotEmpty) {
      final completedUsers = prefs.getStringList(_completedUsersKey) ?? [];
      if (!completedUsers.contains(userId)) {
        completedUsers.add(userId);
        await prefs.setStringList(_completedUsersKey, completedUsers);
      }
    }
  }

  /// Reset onboarding for this device (for testing/debugging).
  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceOnboardingKey);
  }

  /// Legacy: Reset for a specific user
  Future<void> resetForUser(String? userId) async {
    if (userId == null || userId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final completedUsers = prefs.getStringList(_completedUsersKey) ?? [];
    completedUsers.removeWhere((id) => id == userId);
    await prefs.setStringList(_completedUsersKey, completedUsers);
  }
}
