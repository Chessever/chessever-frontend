import 'dart:convert';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:upgrader/upgrader.dart';

/// Store-version reminders only; independent of Shorebird patch downloads.
class PhoneUpdateReminder {
  PhoneUpdateReminder({
    DateTime Function()? now,
    Future<SharedPreferences?> Function()? preferences,
  }) : _now = now ?? DateTime.now,
       _preferences =
           preferences ?? SharedPreferencesService.instance.ensureInitialized;

  static const preferencesKey = 'phone_store_update_snooze_v1';
  static const cooldown = Duration(hours: 72);
  final DateTime Function() _now;
  final Future<SharedPreferences?> Function() _preferences;

  Future<bool> snooze(String offeredVersion) async {
    if (Upgrader.parseVersion(offeredVersion, 'offeredVersion', false) ==
        null) {
      return false;
    }
    // Capture the click time, not the completion time of the preference write.
    final until = _now().toUtc().add(cooldown);
    final prefs = await _preferences();
    if (prefs == null) return false;
    return prefs.setString(
      preferencesKey,
      jsonEncode({
        'version': offeredVersion,
        'until': until.microsecondsSinceEpoch,
      }),
    );
  }

  Future<bool> shouldOffer({
    required String? installedVersion,
    required String? offeredVersion,
    bool mandatory = false,
    bool manual = false,
  }) async {
    final installed = Upgrader.parseVersion(
      installedVersion,
      'installedVersion',
      false,
    );
    final offered = Upgrader.parseVersion(
      offeredVersion,
      'offeredVersion',
      false,
    );
    final prefs = await _preferences();
    DateTime? until;
    final raw = prefs?.getString(preferencesKey);
    if (raw != null) {
      try {
        final record = jsonDecode(raw) as Map<String, dynamic>;
        final target = Upgrader.parseVersion(
          record['version'] as String?,
          'snoozedVersion',
          false,
        );
        if (target == null || record['until'] is! int) {
          await prefs!.remove(preferencesKey);
        } else if (installed != null && installed >= target) {
          // Returning from a store is not proof of installation. Only the
          // installed package version can retire this version-bound record.
          await prefs!.remove(preferencesKey);
        } else {
          until = DateTime.fromMicrosecondsSinceEpoch(
            record['until'] as int,
            isUtc: true,
          );
        }
      } catch (_) {
        await prefs!.remove(preferencesKey);
      }
    }
    if (installed == null || offered == null || offered <= installed) {
      return false;
    }
    if (mandatory || manual) return true;
    if (prefs == null) return false;
    // A newer optional release does NOT reset or bypass the user's 72 hours.
    // Once due, offer the latest checked version, not the old snoozed target.
    return until == null || !_now().toUtc().isBefore(until);
  }
}
