import 'package:chessever2/utils/own_web_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

/// Own chessever.com pages (account, privacy, terms, desktop) open in a
/// browser tab over the app on Android. A plain VIEW intent resolved to
/// ChessEver itself (its App Links claimed every path) and nothing opened.
void main() {
  late List<(Uri, LaunchMode)> launched;
  late OwnWebPageLauncher previous;

  setUp(() {
    launched = [];
    previous = ownWebPageLauncher;
    ownWebPageLauncher = (uri, mode) async {
      launched.add((uri, mode));
      return true;
    };
  });

  tearDown(() {
    ownWebPageLauncher = previous;
    debugDefaultTargetPlatformOverride = null;
  });

  for (final page in [
    'https://chessever.com/account',
    'https://chessever.com/privacy-policy',
    'https://chessever.com/terms-of-use',
    'https://chessever.com/desktop',
  ]) {
    test('Android opens $page in a browser tab over the app', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await openOwnWebPage(Uri.parse(page)), isTrue);
      expect(launched, [(Uri.parse(page), LaunchMode.inAppBrowserView)]);
    });

    test('iOS keeps Safari for $page', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await openOwnWebPage(Uri.parse(page));
      expect(launched, [(Uri.parse(page), LaunchMode.externalApplication)]);
    });
  }

  test('a third-party page always goes to the system browser', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await openExternalWebPage(Uri.parse('https://x.com/chesseverapp'));
    expect(launched.single.$2, LaunchMode.externalApplication);
  });

  test('a launcher failure is reported, not thrown', () async {
    ownWebPageLauncher = (_, _) async => throw Exception('no browser');
    expect(
      await openOwnWebPage(Uri.parse('https://chessever.com/account')),
      isFalse,
    );
  });

  test('isOwnWebHost names chessever.com and www only', () {
    expect(isOwnWebHost(Uri.parse('https://chessever.com/account')), isTrue);
    expect(isOwnWebHost(Uri.parse('https://WWW.chessever.com/a')), isTrue);
    expect(isOwnWebHost(Uri.parse('https://get.chessever.com/x')), isFalse);
    expect(isOwnWebHost(Uri.parse('com.chessever.app://games/x')), isFalse);
  });
}
