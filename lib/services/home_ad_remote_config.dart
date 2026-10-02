import 'dart:async';

import 'package:chessever2/services/firebase_app.dart';
import 'package:chessever2/services/native_ads_config.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const homeNativeAdConfigKey = 'home_native_ad_enabled';

final homeNativeAdEnabledProvider =
    StateNotifierProvider<HomeAdRemoteConfigNotifier, bool>((ref) {
      return HomeAdRemoteConfigNotifier(
        source: FirebaseHomeAdConfigSource(),
        enabled: NativeAdsConfig.available,
      );
    });

abstract interface class HomeAdConfigSource {
  Future<bool> initialize();
  Future<bool> fetch();
  Stream<bool> get updates;
}

class FirebaseHomeAdConfigSource implements HomeAdConfigSource {
  late FirebaseRemoteConfig _config;

  @override
  Future<bool> initialize() async {
    await ensureFirebaseInitialized();
    _config = FirebaseRemoteConfig.instance;
    await _config.setDefaults(const {homeNativeAdConfigKey: false});
    await _config.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? const Duration(minutes: 1)
            : const Duration(hours: 1),
      ),
    );
    return _config.getBool(homeNativeAdConfigKey);
  }

  @override
  Future<bool> fetch() async {
    await _config.fetchAndActivate();
    return _config.getBool(homeNativeAdConfigKey);
  }

  @override
  Stream<bool> get updates => _config.onConfigUpdated.asyncMap((_) async {
    await _config.activate();
    return _config.getBool(homeNativeAdConfigKey);
  });
}

/// Hidden until Firebase supplies an activated value. An offline app can retain
/// its last activated setting; a new install or missing key stays hidden.
class HomeAdRemoteConfigNotifier extends StateNotifier<bool> {
  HomeAdRemoteConfigNotifier({required this.source, required bool enabled})
    : super(false) {
    if (enabled) unawaited(_initialize());
  }

  final HomeAdConfigSource source;
  StreamSubscription<bool>? _updates;

  void _apply(bool visible) {
    if (mounted) state = visible;
  }

  Future<void> _initialize() async {
    try {
      final cached = await source.initialize();
      if (!mounted) return;
      _apply(cached);
      _updates = source.updates.listen(
        _apply,
        onError: (Object _) {
          debugPrint('[HomeAds] Remote Config update unavailable.');
        },
      );
      try {
        _apply(await source.fetch());
      } catch (_) {
        // Preserve the default or last activated setting on network failure.
        debugPrint('[HomeAds] Remote Config fetch unavailable.');
      }
    } catch (_) {
      debugPrint(
        '[HomeAds] Remote Config unavailable; placement stays hidden.',
      );
    }
  }

  @override
  void dispose() {
    unawaited(_updates?.cancel());
    super.dispose();
  }
}
