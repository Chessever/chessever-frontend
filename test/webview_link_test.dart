import 'package:chessever2/services/webview_link.dart';
import 'package:chessever2/services/webview_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('WebView wrappers retain query strings and fragments', () {
    const url = 'https://chessever.com/account?tab=billing&from=push#plans';
    for (final base in [
      'com.chessever.app://webview',
      'com.chessever.app://app/webview',
      'https://chessever.com/webview',
      'https://www.chessever.com/app/webview',
      '/app/webview',
    ]) {
      expect(
        webViewLinkTarget(Uri.parse('$base?url=${Uri.encodeComponent(url)}')),
        Uri.parse(url),
      );
    }
  });

  test('invalid targets and foreign wrappers are rejected', () {
    for (final url in [
      'javascript:alert(1)',
      'data:text/html,hello',
      'file:///secret',
      'https://user:password@chessever.com',
      'https://',
      '/account',
      'https://example.com/\nsecret',
    ]) {
      expect(webViewUrl(url), isNull, reason: url);
    }
    for (final wrapper in [
      'https://evil.example/webview?url=https://chessever.com',
      'https://chessever.com:444/webview?url=https://chessever.com',
      'com.chessever.app://webview?url=https://a.com&url=https://b.com',
      'com.chessever.app://webview?url=javascript:alert(1)',
    ]) {
      expect(webViewLinkTarget(Uri.parse(wrapper)), isNull);
    }
  });

  test('session handoff is restricted to exact approved HTTPS origins', () {
    for (final host in [
      'chessever.com',
      'www.chessever.com',
      'broadcast.chessever.com',
    ]) {
      expect(
        canShareWebViewSession(Uri.parse('https://$host/account')),
        isTrue,
      );
    }
    for (final url in [
      'http://chessever.com',
      'https://chessever.com:444',
      'https://chessever.com.evil.example',
      'https://evilchessever.com',
      'https://untrusted.chessever.com',
      'https://chessever.com@evil.example',
    ]) {
      expect(canShareWebViewSession(Uri.parse(url)), isFalse, reason: url);
      expect(
        () => webViewSessionScript(Uri.parse(url), null),
        throwsArgumentError,
      );
    }
  });

  test(
    'handoff includes web session fields and excludes provider credentials',
    () {
      final session = Session(
        accessToken: 'mobile-access',
        refreshToken: 'mobile-refresh',
        tokenType: 'bearer',
        providerToken: 'private-google-token',
        providerRefreshToken: 'private-google-refresh',
        user: const User(
          id: 'user-1',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '',
        ),
      );
      final script = webViewSessionScript(
        Uri.parse('https://chessever.com/account'),
        session,
      );
      expect(
        script,
        contains('window.location.origin !== "https://chessever.com"'),
      );
      expect(script, contains('mobile-access'));
      expect(script, contains('mobile-refresh'));
      expect(script, isNot(contains('private-google')));
      expect(
        script.indexOf('window.location.origin'),
        lessThan(script.indexOf('localStorage.setItem')),
      );
      expect(
        webViewSessionScript(Uri.parse('https://chessever.com'), null),
        contains('const value = null;'),
      );
    },
  );
}
