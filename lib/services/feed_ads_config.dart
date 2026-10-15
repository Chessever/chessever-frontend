import 'dart:io';

import 'package:chessever2/config/app_environment.dart';
import 'package:flutter/foundation.dart';

/// Feed's in-feed ad: an inline adaptive banner on a page of its own between
/// posts, for viewers without Premium access. See docs/feed-ads.md.
abstract final class FeedAdsConfig {
  static const enabled = bool.fromEnvironment(
    'FEED_ADS_ENABLED',
    defaultValue: true,
  );

  static bool get available =>
      !AppEnvironment.isTest &&
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      enabled &&
      (kDebugMode || RegExp(r'^ca-app-pub-\d+/\d+$').hasMatch(liveUnitId));

  /// The "Feed inline adaptive banner" units (banner format, automatic
  /// refresh off: every ad page requests its own ad).
  static String get liveUnitId => Platform.isAndroid
      ? const String.fromEnvironment(
          'ADMOB_ANDROID_FEED_BANNER_ID',
          defaultValue: 'ca-app-pub-3681310687796023/7169486456',
        )
      : const String.fromEnvironment(
          'ADMOB_IOS_FEED_BANNER_ID',
          defaultValue: 'ca-app-pub-3681310687796023/9843751253',
        );

  /// Google's adaptive banner test units in debug.
  static String get unitId => kDebugMode
      ? (Platform.isAndroid
            ? 'ca-app-pub-3940256099942544/9214589741'
            : 'ca-app-pub-3940256099942544/2435281174')
      : liveUnitId;
}
