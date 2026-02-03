import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class LiveUpdatesService {
  LiveUpdatesService._();

  static final LiveUpdatesService instance = LiveUpdatesService._();

  bool _setupDone = false;

  Future<void> setup() async {
    if (_setupDone) return;
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) return;

    try {
      OneSignal.LiveActivities.setupDefault();
      _setupDone = true;
    } catch (_) {
      // Live Activities not available on this device/OS.
    }
  }

  Future<void> startLiveActivity({
    required String activityId,
    required Map<String, dynamic> attributes,
    required Map<String, dynamic> content,
  }) async {
    await setup();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    try {
      OneSignal.LiveActivities.startDefault(activityId, attributes, content);
    } catch (_) {
      // Ignore failures (unsupported iOS version, etc.)
    }
  }

  Future<void> endLiveActivity(String activityId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      OneSignal.LiveActivities.exit(activityId);
    } catch (_) {
      // Ignore failures.
    }
  }
}
