import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// chessever.com, as a page on the web rather than a route in the app.
bool isOwnWebHost(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    const {
      'chessever.com',
      'www.chessever.com',
    }.contains(uri.host.toLowerCase());

typedef OwnWebPageLauncher = Future<bool> Function(Uri uri, LaunchMode mode);

Future<bool> _launch(Uri uri, LaunchMode mode) => launchUrl(uri, mode: mode);

/// What [openOwnWebPage] launches through. Tests replace it.
@visibleForTesting
OwnWebPageLauncher ownWebPageLauncher = _launch;

/// How an own chessever.com page opens.
///
/// Android: in a browser tab over the app (Custom Tabs). A plain VIEW intent
/// for an https chessever.com URL resolves to ChessEver itself, whose
/// verified App Link filters claimed every path up to 39.2.x, and the app
/// has no route for these pages, so "Manage on chessever.com" and the legal
/// links used to open the app on itself and do nothing. Custom Tabs keep
/// Chrome's cookies (the /account sign-in) and, unlike a WebView, are
/// accepted by Stripe and Google sign-in.
///
/// iOS: Safari, unchanged. The associated domains never claim these pages.
LaunchMode ownWebPageLaunchMode() =>
    defaultTargetPlatform == TargetPlatform.android
    ? LaunchMode.inAppBrowserView
    : LaunchMode.externalApplication;

/// Opens an own web page (account, privacy, terms, desktop download) the
/// way [ownWebPageLaunchMode] describes. [mode] overrides it.
Future<bool> openOwnWebPage(Uri uri, {LaunchMode? mode}) async {
  try {
    return await ownWebPageLauncher(uri, mode ?? ownWebPageLaunchMode());
  } catch (error) {
    debugPrint('[OwnWebPage] could not open ${uri.path}: ${error.runtimeType}');
    return false;
  }
}

/// Opens a third-party web page in the system browser.
Future<bool> openExternalWebPage(Uri uri) =>
    openOwnWebPage(uri, mode: LaunchMode.externalApplication);
