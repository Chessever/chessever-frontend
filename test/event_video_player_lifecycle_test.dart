import 'package:chessever2/screens/chessboard/video/video_player.dart';
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'event_video_test.dart' show FakeVideoRepository, fixtureVideos;

class _WebViewPlatform extends WebViewPlatform {
  final controllers = <_Controller>[];
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _Controller(params);
    controllers.add(controller);
    return controller;
  }

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
  final documents = <String>[];
  _Navigation? navigation;
  JavaScriptChannelParams? channel;
  bool cancelOnBlank = false;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate delegate,
  ) async {
    navigation = delegate as _Navigation;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    documents.add(html);
    if (!html.contains('ChessVideo') && cancelOnBlank) emitError(-999);
  }

  void emitError(int code, {bool mainFrame = true}) =>
      navigation?.onError?.call(
        WebResourceError(
          errorCode: code,
          description: 'Fixture navigation error',
          isForMainFrame: mainFrame,
        ),
      );
}

class _Navigation extends PlatformNavigationDelegate {
  _Navigation(super.params) : super.implementation();
  WebResourceErrorCallback? onError;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    onError = callback;
  }
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Colors.black,
    child: Text('Native player fixture'),
  );
}

class _Harness {
  final observer = RouteObserver<PageRoute<dynamic>>();
  final navigator = GlobalKey<NavigatorState>();
  final key = GlobalKey<EventVideoHostState>();
  final session = EventVideoSession(
    repository: FakeVideoRepository(fixtureVideos()),
  );
  final player = NativeEventVideoPlayer(
    Uri.parse('https://embed.test.example.com'),
  );
  Widget get widget => MaterialApp(
    navigatorKey: navigator,
    navigatorObservers: [observer],
    home: EventVideoHost(
      pageObserver: observer,
      key: key,
      gameId: 'game',
      tourId: 'tour',
      roundId: 'round',
      session: session,
      player: player,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            PopupMenuButton<String>(
              itemBuilder:
                  (_) => const [
                    PopupMenuItem(value: 'swap', child: Text('Flip board')),
                  ],
            ),
          ],
        ),
        body: const SingleChildScrollView(child: EventVideoSurface()),
      ),
    ),
  );
}

// The adapter defers native loads to the event queue after a widget build.
// A settled frame can still leave that zero-delay task waiting to execute.
Future<void> _flushPlayer(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  late _WebViewPlatform platform;
  setUp(() {
    platform = _WebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  testWidgets('menu preserves playback but a profile page stops it', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.widget);
    await _flushPlayer(tester);
    final controller = platform.controllers.single;
    final revision = h.session.playerRevision;
    final loads = controller.documents.length;
    h.session.reportPlayback(true, revision);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await _flushPlayer(tester);
    expect(find.text('Flip board'), findsOneWidget);
    expect(h.session.playing, isTrue);
    expect(h.session.foreground, isTrue);
    expect(controller.documents.length, loads);
    h.navigator.currentState!.pop();
    await _flushPlayer(tester);
    expect(h.session.playing, isTrue);
    expect(h.session.playerRevision, revision);
    expect(controller.documents.length, loads);

    h.navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Profile')),
      ),
    );
    await _flushPlayer(tester);
    expect(h.session.playing, isFalse);
    expect(controller.documents.last, isNot(contains('ChessVideo')));
    h.navigator.currentState!.pop();
    await _flushPlayer(tester);
    expect(h.session.foreground, isTrue);
    expect(h.session.playing, isFalse);
    expect(controller.documents.last, contains('autoplay:0'));
    expect(h.player.failed, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('profile return reloads the cleared native document paused', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.widget);
    await _flushPlayer(tester);
    final controller = platform.controllers.single;
    expect(controller.documents.last, contains('youtube.com/iframe_api'));
    h.session.reportPlayback(true, h.session.playerRevision);
    final selected = h.session.selected!.id;
    for (var visit = 0; visit < 2; visit++) {
      h.key.currentState!.setRouteVisible(false);
      await _flushPlayer(tester);
      expect(controller.documents.last, isNotEmpty);
      expect(controller.documents.last, isNot(contains('ChessVideo')));
      h.key.currentState!.setRouteVisible(true);
      await _flushPlayer(tester);
      expect(controller.documents.last, contains('youtube.com/iframe_api'));
      expect(controller.documents.last, contains('autoplay:0'));
      expect(h.session.selected!.id, selected);
      expect(h.session.playing, isFalse);
      expect(h.player.failed, isFalse);
      expect(platform.controllers, hasLength(1));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('intentional cancellation never presents the retry overlay', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.widget);
    await _flushPlayer(tester);
    final controller = platform.controllers.single..cancelOnBlank = true;
    h.key.currentState!.setRouteVisible(false);
    await _flushPlayer(tester);
    expect(h.player.failed, isFalse);
    // An obsolete failure while the board is covered must not poison return.
    controller.emitError(-1003);
    expect(h.player.failed, isFalse);
    h.key.currentState!.setRouteVisible(true);
    await _flushPlayer(tester);
    // WKWebView may deliver the canceled load's error after the new load starts.
    controller.emitError(-999);
    await tester.pump();
    expect(h.player.failed, isFalse);
    expect(find.text('Video unavailable · Retry'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'real current-document failure shows Retry and retry reloads paused',
    (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.widget);
      await _flushPlayer(tester);
      final controller = platform.controllers.single;
      controller.emitError(-1003, mainFrame: false);
      expect(h.player.failed, isFalse);
      controller.emitError(-1003);
      await tester.pump();
      expect(h.player.failed, isTrue);
      final loadCount = controller.documents.length;
      await tester.tap(find.text('Video unavailable · Retry'));
      await _flushPlayer(tester);
      expect(controller.documents.length, greaterThan(loadCount));
      expect(controller.documents.last, contains('autoplay:0'));
      expect(h.player.failed, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('a hidden video stays hidden through a profile visit', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.widget);
    await _flushPlayer(tester);
    final controller = platform.controllers.single;
    h.session.toggle();
    await _flushPlayer(tester);
    h.key.currentState!.setRouteVisible(false);
    await _flushPlayer(tester);
    h.key.currentState!.setRouteVisible(true);
    await _flushPlayer(tester);
    expect(h.session.showVideo, isFalse);
    expect(controller.documents.last, isNot(contains('ChessVideo')));
    expect(h.player.failed, isFalse);
    h.session.toggle();
    await _flushPlayer(tester);
    expect(controller.documents.last, contains('autoplay:0'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(controller.documents.last, isNotEmpty);
    expect(controller.documents.last, isNot(contains('ChessVideo')));
    expect(tester.takeException(), isNull);
  });
}
