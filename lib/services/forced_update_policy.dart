import 'dart:async';

import 'package:chessever2/services/firebase_app.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:upgrader/upgrader.dart';

/// Remote Config key for Upgrader's `minAppVersion`: installs below it must
/// update, e.g. `38.12.0` (`39` reads as `39.0.0`). It overrides the store
/// listing's minimum tag; blank or unpublished falls back to that tag.
const minAppVersionKey = 'min_app_version';

/// Remote Config key: a store release with a higher major version than the
/// installed app is mandatory. Unpublished reads as on; only an explicit
/// `false` or `0` turns it off.
const forceUpdateOnMajorKey = 'force_update_on_major';

/// When a store update stops being optional.
///
/// [minimumVersion] is applied as Upgrader's `minAppVersion`, so the package's
/// own `blocked()` enforces it. [forceOnMajor] is checked by
/// [requiresMajorUpdate].
@immutable
class ForcedUpdatePolicy {
  const ForcedUpdatePolicy({this.minimumVersion, this.forceOnMajor = true});

  /// Before Remote Config answers, and on a fresh install that is offline.
  static const fallback = ForcedUpdatePolicy();

  final String? minimumVersion;
  final bool forceOnMajor;

  @override
  bool operator ==(Object other) =>
      other is ForcedUpdatePolicy &&
      other.minimumVersion == minimumVersion &&
      other.forceOnMajor == forceOnMajor;

  @override
  int get hashCode => Object.hash(minimumVersion, forceOnMajor);

  @override
  String toString() =>
      'ForcedUpdatePolicy(minimumVersion: $minimumVersion, '
      'forceOnMajor: $forceOnMajor)';
}

/// Builds a policy from raw Remote Config strings; null means unpublished.
ForcedUpdatePolicy forcedUpdatePolicyFrom({
  String? minimumVersion,
  String? forceOnMajor,
}) {
  final minimum = minimumVersion?.trim() ?? '';
  final onMajor = forceOnMajor?.trim().toLowerCase() ?? '';
  return ForcedUpdatePolicy(
    minimumVersion: minimum.isEmpty ? null : minimum,
    // A typo keeps enforcement on; switching it off has to be deliberate.
    forceOnMajor: onMajor != 'false' && onMajor != '0',
  );
}

/// Whether the store's [offeredVersion] is a new major version that must be
/// installed before the app can be used.
bool requiresMajorUpdate({
  required String? installedVersion,
  required String? offeredVersion,
  required ForcedUpdatePolicy policy,
}) {
  if (!policy.forceOnMajor) return false;
  final installed = _major(installedVersion, 'installedVersion');
  final offered = _major(offeredVersion, 'offeredVersion');
  return installed != null && offered != null && offered > installed;
}

/// Writes [policy]'s minimum into Upgrader's `minAppVersion`, without the
/// store re-query the public `minAppVersion` setter starts. An unreadable
/// value clears it (the store listing's tag applies again), so a typo can
/// never lock anyone out.
void applyMinAppVersion(Upgrader upgrader, ForcedUpdatePolicy policy) {
  final text = policy.minimumVersion?.trim() ?? '';
  final minimum = text.isEmpty
      ? null
      : Upgrader.parseVersion(text, 'minAppVersion', false);
  upgrader.updateState(
    minimum == null
        ? upgrader.state.copyWithNull(minAppVersion: true)
        : upgrader.state.copyWith(minAppVersion: minimum),
  );
}

// Upgrader prints on input it cannot parse; blanks never reach it.
int? _major(String? value, String name) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : Upgrader.parseVersion(text, name, false)?.major;
}

/// Where the policy comes from.
abstract interface class ForcedUpdatePolicySource {
  /// Never throws. Falls back to the last activated values, then to
  /// [ForcedUpdatePolicy.fallback].
  Future<ForcedUpdatePolicy> load();

  /// Fires when the policy may have changed while the app is open.
  Stream<void> get changes;
}

/// A policy that never changes. The default when none is supplied.
class FixedForcedUpdatePolicySource implements ForcedUpdatePolicySource {
  const FixedForcedUpdatePolicySource([
    this.policy = ForcedUpdatePolicy.fallback,
  ]);

  final ForcedUpdatePolicy policy;

  @override
  Future<ForcedUpdatePolicy> load() async => policy;

  @override
  Stream<void> get changes => const Stream<void>.empty();
}

/// Reads [minAppVersionKey] and [forceUpdateOnMajorKey] from Firebase
/// Remote Config, and follows real-time updates while the app is open.
///
/// Fetches once per process, like the other Remote Config features. A fetch
/// on every resume would activate templates ahead of the real-time stream,
/// which then sees nothing new and never tells `discovery_dots` or the home
/// ad flag. Later changes arrive through [changes], which activates them.
class FirebaseForcedUpdatePolicySource implements ForcedUpdatePolicySource {
  Future<FirebaseRemoteConfig>? _ready;
  Future<void>? _fetched;

  Future<FirebaseRemoteConfig> _config() => _ready ??= _prepare();

  Future<FirebaseRemoteConfig> _prepare() async {
    try {
      await ensureFirebaseInitialized();
      final config = FirebaseRemoteConfig.instance;
      // No setDefaults: it replaces the defaults other features installed.
      // An unpublished key is recognised by its static source instead.
      await config.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: kDebugMode
              ? const Duration(minutes: 1)
              : const Duration(hours: 1),
        ),
      );
      return config;
    } catch (_) {
      _ready = null;
      rethrow;
    }
  }

  @override
  Future<ForcedUpdatePolicy> load() async {
    try {
      final config = await _config();
      // Offline: the last activated values apply, and the real-time stream
      // fetches anything newer once it connects.
      await (_fetched ??= config.fetchAndActivate().then<void>(
        (_) {},
        onError: (Object _) {},
      ));
      return _read(config);
    } catch (_) {
      debugPrint('[ForcedUpdate] Remote Config unavailable; using fallback.');
      return ForcedUpdatePolicy.fallback;
    }
  }

  @override
  Stream<void> get changes => Stream.fromFuture(_config()).asyncExpand(
    (config) => config.onConfigUpdated
        .where(
          (update) =>
              update.updatedKeys.contains(minAppVersionKey) ||
              update.updatedKeys.contains(forceUpdateOnMajorKey),
        )
        .asyncMap((_) => config.activate()),
  );

  ForcedUpdatePolicy _read(FirebaseRemoteConfig config) {
    String? published(String key) {
      final value = config.getValue(key);
      return value.source == ValueSource.valueStatic ? null : value.asString();
    }

    return forcedUpdatePolicyFrom(
      minimumVersion: published(minAppVersionKey),
      forceOnMajor: published(forceUpdateOnMajorKey),
    );
  }
}
