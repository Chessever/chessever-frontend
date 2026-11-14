import 'package:flutter/widgets.dart';
import 'package:upgrader/upgrader.dart';

/// Keeps Upgrader's store/version/URL contracts, but the app shell owns
/// launch/resume checks so they can be serialized and safely deferred.
class PhoneStoreUpgrader extends Upgrader {
  PhoneStoreUpgrader({required super.messages})
    : super(storeController: UpgraderStoreController(oniOS: PhoneAppStore.new));

  Future<UpgraderVersionInfo?>? _inFlight;

  @override
  Future<void> didChangeAppLifecycleState(
    AppLifecycleState lifecycleState,
  ) async {}

  @override
  Future<UpgraderVersionInfo?> updateVersionInfo() {
    return _inFlight ??= _refresh();
  }

  Future<UpgraderVersionInfo?> _refresh() async {
    try {
      final info = await super.updateVersionInfo();
      // Upgrader's copyWith retains old info on a null store response.
      // Failed checks must never redisplay a stale offer.
      if (info == null) updateState(state.copyWithNull(versionInfo: true));
      return info;
    } catch (_) {
      updateState(state.copyWithNull(versionInfo: true));
      return null;
    } finally {
      _inFlight = null;
    }
  }
}

/// An iTunes lookup response for this app, or null when it failed.
typedef StoreLookup =
    Future<Map?> Function(
      UpgraderState state,
      String? country,
      String? language,
    );

/// Upgrader's App Store check plus the field it ignores: the store build's
/// `minimumOsVersion`. A device below it cannot install that build, so it is
/// reported as no update. Otherwise a mandatory update (a new major, or the
/// remote `min_app_version`) would lock that phone out with nothing to
/// install, e.g. after a release raises the iOS deployment target.
class PhoneAppStore extends UpgraderStore {
  /// [lookup] and [deviceOsVersion] replace the iTunes request and the
  /// device's OS version in tests.
  PhoneAppStore({this._lookup, this._deviceOsVersion});

  final StoreLookup? _lookup;
  final String Function()? _deviceOsVersion;

  @override
  Future<UpgraderVersionInfo> getVersionInfo({
    required UpgraderState state,
    // Loosely typed so the transitive `version` package need not be imported.
    required dynamic installedVersion,
    required String? country,
    required String? language,
  }) async {
    final packageInfo = state.packageInfo;
    if (packageInfo == null) return UpgraderVersionInfo();
    final iTunes = ITunesSearchAPI()
      ..debugLogging = state.debugLogging
      ..client = state.client
      ..clientHeaders = state.clientHeaders;
    final response = await (_lookup != null
        ? _lookup(state, country, language)
        : iTunes.lookupByBundleId(
            packageInfo.packageName,
            country: country,
            language: language,
          ));
    final deviceOs =
        _deviceOsVersion?.call() ?? state.upgraderOS.operatingSystemVersion;
    if (response == null ||
        !canInstallOn(
          deviceOs: deviceOs,
          minimumOs: storeMinimumOsVersion(response),
        )) {
      return UpgraderVersionInfo(installedVersion: installedVersion);
    }
    final version = iTunes.version(response);
    return UpgraderVersionInfo(
      installedVersion: installedVersion,
      appStoreListingURL: iTunes.trackViewUrl(response),
      appStoreVersion: version == null
          ? null
          : Upgrader.parseVersion(version, 'appStoreVersion', false),
      minAppVersion: iTunes.minAppVersion(response),
      releaseNotes: iTunes.releaseNotes(response),
    );
  }
}

/// The iTunes lookup's `minimumOsVersion` for the store build, e.g. `16.1`.
String? storeMinimumOsVersion(Map response) {
  try {
    final value = response['results'][0]['minimumOsVersion'];
    return value is String ? value : null;
  } catch (_) {
    return null;
  }
}

/// Whether a device on [deviceOs] can install a build that needs [minimumOs].
/// [deviceOs] is read the way `Platform.operatingSystemVersion` reports it,
/// e.g. `Version 17.4 (Build 21E213)`. Unknown either way counts as
/// installable, so a parsing gap never hides a real update.
bool canInstallOn({required String? deviceOs, required String? minimumOs}) {
  final device = _leadingVersion(deviceOs);
  final minimum = _leadingVersion(minimumOs);
  if (device == null || minimum == null) return true;
  for (var i = 0; i < 3; i++) {
    if (device[i] != minimum[i]) return device[i] > minimum[i];
  }
  return true;
}

final _versionPattern = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?');

List<int>? _leadingVersion(String? text) {
  final match = _versionPattern.firstMatch(text ?? '');
  if (match == null) return null;
  return [for (var g = 1; g <= 3; g++) int.parse(match.group(g) ?? '0')];
}
