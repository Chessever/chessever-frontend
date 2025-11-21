import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository();
});

class OnboardingRepository {
  static const String _completedUsersKey =
      'player_follow_onboarding_users_v1';

  Future<bool> isCompleted(String? userId) async {
    if (userId == null || userId.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final completedUsers = prefs.getStringList(_completedUsersKey) ?? [];
    return completedUsers.contains(userId);
  }

  Future<void> markCompleted(String? userId) async {
    if (userId == null || userId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final completedUsers = prefs.getStringList(_completedUsersKey) ?? [];

    if (!completedUsers.contains(userId)) {
      completedUsers.add(userId);
      await prefs.setStringList(_completedUsersKey, completedUsers);
    }
  }

  Future<void> resetForUser(String? userId) async {
    if (userId == null || userId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final completedUsers = prefs.getStringList(_completedUsersKey) ?? [];
    completedUsers.removeWhere((id) => id == userId);
    await prefs.setStringList(_completedUsersKey, completedUsers);
  }
}
