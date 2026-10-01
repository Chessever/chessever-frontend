import 'dart:io';

import 'package:chessever2/config/app_environment.dart';
import 'package:flutter/foundation.dart';

abstract final class NativeAdsConfig {
  static const enabled = bool.fromEnvironment(
    'NATIVE_ADS_ENABLED',
    defaultValue: true,
  );
  static bool get available =>
      !AppEnvironment.isTest &&
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      enabled &&
      (kDebugMode || RegExp(r'^ca-app-pub-\d+/\d+$').hasMatch(liveUnitId));

  static String get liveUnitId => Platform.isAndroid
      ? const String.fromEnvironment(
          'ADMOB_ANDROID_NATIVE_ID',
          defaultValue: 'ca-app-pub-3681310687796023/2917470581',
        )
      : const String.fromEnvironment(
          'ADMOB_IOS_NATIVE_ID',
          defaultValue: 'ca-app-pub-3681310687796023/4370153050',
        );

  static String get unitId => kDebugMode
      ? (Platform.isAndroid
            ? 'ca-app-pub-3940256099942544/2247696110'
            : 'ca-app-pub-3940256099942544/3986624511')
      : liveUnitId;
}
