import 'dart:async';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The auth `user_metadata` key that records, for the whole account, that My
/// Space has been given its defaults. Additive: GoTrue merges metadata keys,
/// and nothing else reads this one.
const String kSpaceSeededMetadataKey = 'my_space_seeded_v1';

/// Where seeding stands on this device for one account.
enum SpaceSeedMark {
  /// Nothing recorded yet.
  none,

  /// Defaults added here; the account flag is not confirmed written yet.
  seeded,

  /// The account flag is written (or was found set): never seed again.
  synced,
}

/// What the store should do about defaults for one account, right now.
enum SpaceSeedStep {
  /// Nothing: already done, or not safe to decide yet.
  skip,

  /// Add the defaults.
  seed,

  /// Defaults were added before (here or on another device); only record
  /// that on the account and this device.
  markOnly,
}

/// Decides whether an account gets its defaults, from what this device and
/// the account remember. Pure, so every path is unit tested.
///
/// * A guest (no account) seeds once per device.
/// * An account seeds once, ever: the account flag, a seeded row already on
///   the server, or this device having seeded it all count, so a default the
///   user removed never comes back on another phone or after a reinstall.
/// * Until the server has answered ([serverKnown]) an account is left alone,
///   rather than risk bringing back something removed elsewhere.
SpaceSeedStep planSpaceSeed({
  required bool signedIn,
  required SpaceSeedMark local,
  bool serverKnown = false,
  bool remoteFlag = false,
  bool serverHasSeededRows = false,
}) {
  if (local == SpaceSeedMark.synced) return SpaceSeedStep.skip;
  if (!signedIn) {
    return local == SpaceSeedMark.none
        ? SpaceSeedStep.seed
        : SpaceSeedStep.skip;
  }
  if (remoteFlag) return SpaceSeedStep.markOnly;
  if (!serverKnown) return SpaceSeedStep.skip;
  if (serverHasSeededRows || local == SpaceSeedMark.seeded) {
    return SpaceSeedStep.markOnly;
  }
  return SpaceSeedStep.seed;
}

/// Reads and writes the two seed flags: one on this device (per account, or
/// "guest"), one on the account. Every call fails soft; injectable for tests.
class SpaceSeedGate {
  const SpaceSeedGate();

  static const _localPrefix = 'my_space_seeded_v1:';

  static String _localKey(String? userId) =>
      '$_localPrefix${userId == null || userId.isEmpty ? 'guest' : userId}';

  SpaceSeedMark readLocal(String? userId) {
    final raw = SharedPreferencesService.instance.prefsOrNull?.getString(
      _localKey(userId),
    );
    return switch (raw) {
      'seeded' => SpaceSeedMark.seeded,
      'synced' => SpaceSeedMark.synced,
      _ => SpaceSeedMark.none,
    };
  }

  Future<void> writeLocal(String? userId, SpaceSeedMark mark) async {
    try {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      await prefs?.setString(_localKey(userId), mark.name);
    } catch (e) {
      debugPrint('[MySpace] seed mark not saved: $e');
    }
  }

  static const _trimPrefix = 'my_space_trim_openings_v1:';

  static String _trimKey(String? userId) =>
      '$_trimPrefix${userId == null || userId.isEmpty ? 'guest' : userId}';

  /// Whether this device already took back the retired default openings for
  /// one account (see `planSpaceDefaultTrim`), so the trim runs once.
  bool readTrimmed(String? userId) =>
      SharedPreferencesService.instance.prefsOrNull?.getBool(
        _trimKey(userId),
      ) ??
      false;

  Future<void> writeTrimmed(String? userId) async {
    try {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      await prefs?.setBool(_trimKey(userId), true);
    } catch (e) {
      debugPrint('[MySpace] trim mark not saved: $e');
    }
  }

  /// The account flag, read fresh from the server when it answers in time,
  /// else from the session this device already holds.
  Future<bool> readRemote() async {
    final auth = Supabase.instance.client.auth;
    try {
      final fresh = await auth.getUser().timeout(const Duration(seconds: 4));
      return fresh.user?.userMetadata?[kSpaceSeededMetadataKey] == true;
    } catch (_) {
      return auth.currentUser?.userMetadata?[kSpaceSeededMetadataKey] == true;
    }
  }

  /// Sets the account flag. False when it could not be written.
  Future<bool> writeRemote() async {
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(data: {kSpaceSeededMetadataKey: true}))
          .timeout(const Duration(seconds: 6));
      return true;
    } catch (e) {
      debugPrint('[MySpace] seed flag not written: $e');
      return false;
    }
  }
}

final spaceSeedGateProvider = Provider<SpaceSeedGate>(
  (ref) => const SpaceSeedGate(),
);
