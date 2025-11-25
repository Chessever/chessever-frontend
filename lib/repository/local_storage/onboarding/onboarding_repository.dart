import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository();
});

class OnboardingRepository {
  /// Simple device-level key - shown once per fresh install
  /// Using new key (v3) to reset for all users after this fix
  static const String _hasSeenOnboardingKey = 'has_seen_onboarding_v3';

  /// Check if onboarding has been shown on this device.
  /// Simple boolean check - no user-specific or legacy logic.
  Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSeenOnboardingKey) ?? false;
  }

  /// Legacy method for backwards compatibility - delegates to hasSeenOnboarding
  Future<bool> isCompleted(String? userId) async {
    return hasSeenOnboarding();
  }

  /// Mark onboarding as seen on this device.
  Future<void> markAsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenOnboardingKey, true);
  }

  /// Legacy method for backwards compatibility - delegates to markAsSeen
  Future<void> markCompleted(String? userId) async {
    await markAsSeen();
  }

  /// Reset onboarding (for testing/debugging).
  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hasSeenOnboardingKey);
  }
}
