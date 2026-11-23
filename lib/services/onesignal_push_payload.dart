import 'dart:convert';

import 'package:chessever2/screens/feed/news/news_links.dart';
import 'package:chessever2/services/app_destination.dart';
import 'package:chessever2/services/webview_link.dart';

/// A push in OneSignal's format (docs/deep_links.md, O6).
///
/// The app no longer carries the OneSignal SDK, but a phone that updated
/// from a build that did keeps its OneSignal registration (a "mirror") until
/// it registers with ChessEver's notification service directly, which it
/// does on its first launch with a session. Pushes sent to that mirror in
/// the meantime arrive in OneSignal's envelope:
///
/// * iOS: the tap's `userInfo` holds `custom` (a dictionary, or its JSON as
///   a string) with `i` (the notification id), `a` (the data the sender set:
///   `type`, `game_id`, `route`, ...) and `u` (a launch URL). There is no
///   `gcm.message_id`.
/// * Android: a data-only FCM message whose `custom` key is that JSON as a
///   string, with the text beside it (`title` / `headings`, `alert` /
///   `contents`). The SDK used to draw it; nothing does now unless the app
///   shows it itself.
class OneSignalPush {
  const OneSignalPush({
    required this.id,
    required this.data,
    this.title,
    this.body,
  });

  /// OneSignal's notification id (`custom.i`).
  final String id;

  /// The push as the router reads any push: the sender's data, every value
  /// a string, the way FCM carries them.
  final Map<String, dynamic> data;

  final String? title;
  final String? body;
}

/// Keys of a push that name its destination themselves. With any of them,
/// a OneSignal launch URL (`custom.u`) is never used: pushes are routed by
/// their data.
const _destinationKeys = {'route', 'url', 'type', 'inbox_message_id'};

/// Router keys a sender may have set beside the envelope rather than in it.
const _topLevelRouterKeys = {'type', 'route'};

/// Reads OneSignal's envelope out of a push payload: an iOS tap's `userInfo`
/// or an FCM message's data. Null for anything else, a ChessEver push
/// included, so a normal payload is never touched.
OneSignalPush? parseOneSignalPush(Map<dynamic, dynamic> raw) {
  final custom = _asMap(raw['custom']);
  if (custom == null) return null;
  final id = custom['i'];
  if (id is! String || id.trim().isEmpty) return null;

  final data = <String, dynamic>{};
  final sent = _asMap(custom['a']);
  if (sent != null) {
    for (final entry in sent.entries) {
      final key = entry.key;
      final value = _asPushString(entry.value);
      if (key is String && key.isNotEmpty && value != null) data[key] = value;
    }
  }
  for (final key in _topLevelRouterKeys) {
    final value = _asPushString(raw[key]);
    if (value != null) data.putIfAbsent(key, () => value);
  }
  // A launch URL is a browser link unless it is a chessever.com page the
  // app opens itself, and only stands in when the data names nothing.
  final launch = custom['u'];
  if (launch is String && !data.keys.any(_destinationKeys.contains)) {
    final uri = Uri.tryParse(launch.trim());
    if (uri != null && _routableChesseverLink(uri)) {
      data['url'] = uri.toString();
    }
  }

  String? text(List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  return OneSignalPush(
    id: id.trim(),
    data: data,
    title: text(const ['title', 'headings']),
    body: text(const ['alert', 'contents']),
  );
}

/// [raw] as the router reads a push: a OneSignal envelope unwrapped
/// ([parseOneSignalPush]), any other payload as it is.
Map<String, dynamic> unwrapOneSignalPush(Map<String, dynamic> raw) =>
    parseOneSignalPush(raw)?.data ?? raw;

/// A stable Android notification id for OneSignal notification [id], the
/// same in every isolate and on every launch: one OneSignal push delivered
/// twice replaces itself instead of showing twice. FNV-1a, 31 bits.
int oneSignalNotificationId(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

Map<dynamic, dynamic>? _asMap(Object? value) {
  if (value is Map) return value;
  if (value is! String || value.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(value);
    return decoded is Map ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// FCM carries every data value as a string; OneSignal's `a` is JSON.
String? _asPushString(Object? value) => switch (value) {
  null => null,
  final String text => text,
  num() || bool() => value.toString(),
  _ => jsonEncode(value),
};

/// A chessever.com link the router opens natively: an `/app` route, a news
/// article, a content path, or a `/webview` wrapper of ChessEver's own page.
bool _routableChesseverLink(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.port != 443 ||
      !const {'chessever.com', 'www.chessever.com'}.contains(uri.host)) {
    return false;
  }
  if (isWebViewLink(uri)) {
    final target = webViewLinkTarget(uri);
    return target != null && isExternalWebViewTarget(target);
  }
  if (parseAppDestination(uri.toString()) != null) return true;
  if (NewsLink.parse(uri) != null) return true;
  final path = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  return path.length >= 2 &&
      const {
        'games',
        'broadcast',
        'player',
        'books',
        'databases',
        'folders',
        'collections',
      }.contains(path.first);
}
