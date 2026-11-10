import 'package:chessever2/screens/webview/app_webview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _Platform extends WebViewPlatform {
  late _Controller controller;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _Controller(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Navigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _View(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  final requests = <LoadRequestParams>[];
  final scripts = <String>[];
  late _Navigation navigation;
  Object scriptResult = true;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate delegate,
  ) async {
    navigation = delegate as _Navigation;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    requests.add(params);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String script) async {
    scripts.add(script);
    return scriptResult;
  }

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
  }

  @override
  Future<bool> canGoBack() async => false;
}

class _Navigation extends PlatformNavigationDelegate {
  _Navigation(super.params) : super.implementation();
  late PageEventCallback finished;
  late NavigationRequestCallback navigate;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    navigate = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const Text('Web document');
}

void main() {
  late _Platform platform;
  late int sessionReads;
  setUp(() {
    platform = _Platform();
    WebViewPlatform.instance = platform;
    sessionReads = 0;
  });

  Future<void> open(
    WidgetTester tester,
    String url, {
    bool guest = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          webViewSessionProvider.overrideWithValue(() async {
            sessionReads++;
            if (guest) return null;
            return Session(
              accessToken: 'access-secret',
              refreshToken: 'refresh-secret',
              tokenType: 'bearer',
              user: const User(
                id: 'mobile-user',
                appMetadata: {},
                userMetadata: {},
                aud: 'authenticated',
                createdAt: '',
              ),
            );
          }),
        ],
        child: MaterialApp(home: AppWebViewScreen(url: Uri.parse(url))),
      ),
    );
    await tester.pump();
  }

  testWidgets('trusted page receives the session before its app loads', (
    tester,
  ) async {
    await open(tester, 'https://chessever.com/account?tab=billing#plans');
    final controller = platform.controller;
    expect(
      controller.requests.single.uri.toString(),
      'https://chessever.com/favicon.ico',
    );
    expect(find.text('Web document'), findsNothing);
    controller.navigation.finished('https://chessever.com/favicon.ico');
    await tester.pump();
    expect(sessionReads, 1);
    expect(controller.scripts.first, contains('access-secret'));
    expect(
      controller.scripts.last,
      contains(
        'window.location.replace("https://chessever.com/account?tab=billing#plans")',
      ),
    );
    expect(
      controller.requests.single.headers,
      isEmpty,
      reason: 'no credentials in HTTP requests',
    );
    controller.navigation.finished(
      'https://chessever.com/account?tab=billing#plans',
    );
    await tester.pump();
    expect(sessionReads, 1);
    expect(find.text('Web document'), findsOneWidget);
  });

  testWidgets('external page receives no session, including after redirect', (
    tester,
  ) async {
    await open(tester, 'https://example.com/article');
    final controller = platform.controller;
    expect(controller.requests.single.uri.host, 'example.com');
    controller.navigation.finished('https://another.example/article');
    await tester.pump();
    expect(sessionReads, 0);
    expect(controller.scripts, isEmpty);
    expect(find.text('Web document'), findsOneWidget);
    expect(
      await controller.navigation.navigate(
        const NavigationRequest(url: 'javascript:alert(1)', isMainFrame: true),
      ),
      NavigationDecision.prevent,
    );
  });

  testWidgets('auth bootstrap refuses a redirect to an external origin', (
    tester,
  ) async {
    await open(tester, 'https://chessever.com/account');
    final controller = platform.controller;
    expect(
      await controller.navigation.navigate(
        const NavigationRequest(url: 'https://evil.example', isMainFrame: true),
      ),
      NavigationDecision.prevent,
    );
    await tester.pump();
    expect(sessionReads, 0);
    expect(controller.scripts, isEmpty);
    expect(find.text("Couldn't open this page."), findsOneWidget);
  });

  testWidgets(
    'origin race fails closed without loading the authenticated page',
    (tester) async {
      await open(tester, 'https://chessever.com/account');
      final controller = platform.controller..scriptResult = false;
      controller.navigation.finished('https://chessever.com/favicon.ico');
      await tester.pump();
      expect(controller.scripts, hasLength(1));
      expect(controller.scripts.single, isNot(contains('location.replace')));
      expect(find.text("Couldn't open this page."), findsOneWidget);
    },
  );

  testWidgets('guest handoff removes a previous browser session', (
    tester,
  ) async {
    await open(tester, 'https://chessever.com/account', guest: true);
    final controller = platform.controller;
    controller.navigation.finished('https://chessever.com/favicon.ico');
    await tester.pump();
    expect(controller.scripts.first, contains('const value = null;'));
    expect(controller.scripts.first, contains('localStorage.removeItem(key)'));
    expect(controller.scripts.first, isNot(contains('access-secret')));
  });

  testWidgets('external navigation into ChessEver bootstraps before loading', (
    tester,
  ) async {
    await open(tester, 'https://example.com');
    final controller = platform.controller;
    controller.navigation.finished('https://example.com');
    await tester.pump();
    expect(
      await controller.navigation.navigate(
        const NavigationRequest(
          url: 'https://chessever.com/account',
          isMainFrame: true,
        ),
      ),
      NavigationDecision.prevent,
    );
    await tester.pump();
    expect(
      controller.requests.last.uri.toString(),
      'https://chessever.com/favicon.ico',
    );
    expect(sessionReads, 0);
    controller.navigation.finished('https://chessever.com/favicon.ico');
    await tester.pump();
    expect(sessionReads, 1);
    expect(controller.scripts.last, contains('https://chessever.com/account'));
  });
}
