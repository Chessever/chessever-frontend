import 'package:flutter/widgets.dart';
import 'package:upgrader/upgrader.dart';

/// Keeps Upgrader's store/version/URL contracts, but the app shell owns
/// launch/resume checks so they can be serialized and safely deferred.
class PhoneStoreUpgrader extends Upgrader {
  PhoneStoreUpgrader({required super.messages});

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
