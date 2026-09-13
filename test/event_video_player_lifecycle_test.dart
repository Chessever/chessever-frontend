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
  Object muteSnapshot = 'null';
  @override
  Future<Object> runJavaScriptReturningResult(String script) async =>
      muteSnapshot;
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
  NavigationRequestCallback? onNavigation;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    onNavigation = callback;
  }

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
  _Harness({Future<bool> Function(Uri)? openExternal})
    : player = NativeEventVideoPlayer(
        Uri.parse('https://embed.test.example.com'),
        openExternal: openExternal,
      );
  final observer = RouteObserver<PageRoute<dynamic>>();
  final navigator = GlobalKey<NavigatorState>();
  final key = GlobalKey<EventVideoHostState>();
  final session = EventVideoSession(
    repository: FakeVideoRepository(fixtureVideos()),
  );
  final NativeEventVideoPlayer player;
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

  testWidgets(
    'Android fullscreen overlays the board without pausing playback',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final h = _Harness();
      await tester.pumpWidget(h.widget);
      await _flushPlayer(tester);
      final controller = platform.controllers.single;
      final loads = controller.documents.length;
      final revision = h.session.playerRevision;
      h.session.reportPlayback(true, revision);
      var closed = 0;
      h.player.showFullscreen(
        const Text('Fullscreen native video'),
        () => closed++,
      );
      await tester.pump();
      expect(find.text('Fullscreen native video'), findsOneWidget);
      expect(
        tester.getSize(find.text('Fullscreen native video')),
        const Size(800, 400),
      );
      expect(
        tester
            .widget<RotatedBox>(
              find.byKey(const ValueKey('native_video_landscape')),
            )
            .quarterTurns,
        1,
      );
      await tester.binding.setSurfaceSize(const Size(800, 400));
      await tester.pump();
      expect(
        tester
            .widget<RotatedBox>(
              find.byKey(const ValueKey('native_video_landscape')),
            )
            .quarterTurns,
        0,
      );
      expect(
        tester.getSize(find.text('Fullscreen native video')),
        const Size(800, 400),
      );
      expect(h.session.foreground, isTrue);
      expect(h.session.playing, isTrue);
      expect(h.session.playerRevision, revision);
      expect(controller.documents.length, loads);
      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tester.pump();
      expect(closed, 1);
      expect(h.session.playing, isTrue);
      h.player.showFullscreen(
        const Text('Fullscreen native video'),
        () => closed++,
      );
      expect(h.key.currentState!.exitFullscreen(), isTrue);
      expect(closed, 2);
      h.player.showFullscreen(
        const Text('Fullscreen native video'),
        () => closed++,
      );
      h.session.setForeground(false);
      await _flushPlayer(tester);
      expect(h.player.fullscreenView, isNull);
      expect(closed, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'switch captures native mute state and applies it to the next video',
    (tester) async {
      final h = _Harness();
      await tester.pumpWidget(h.widget);
      await _flushPlayer(tester);
      final controller = platform.controllers.single;
      controller.muteSnapshot = true;
      h.session.reportPlayback(true, h.session.playerRevision);
      h.session.select('english-second');
      await _flushPlayer(tester);
      expect(h.session.muted, isTrue);
      expect(controller.documents.last, contains('mute:1'));
      expect(controller.documents.last, contains('autoplay:1'));
      controller.muteSnapshot = false;
      h.session.select('english-main');
      await _flushPlayer(tester);
      expect(h.session.muted, isFalse);
      expect(controller.documents.last, contains('mute:0'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'YouTube watch links open externally without replacing the player',
    (tester) async {
      final opened = <Uri>[];
      final h = _Harness(
        openExternal: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      await tester.pumpWidget(h.widget);
      await _flushPlayer(tester);
      final navigation = platform.controllers.single.navigation!.onNavigation!;
      expect(
        await navigation(
          const NavigationRequest(
            url: 'https://www.youtube.com/embed/abcdefghijk',
            isMainFrame: false,
          ),
        ),
        NavigationDecision.navigate,
      );
      expect(opened, isEmpty);
      h.session.reportPlayback(true, h.session.playerRevision);
      expect(
        await navigation(
          const NavigationRequest(
            url: 'https://www.youtube.com/watch?v=abcdefghijk',
            isMainFrame: false,
          ),
        ),
        NavigationDecision.prevent,
      );
      expect(opened.single.host, 'www.youtube.com');
      expect(h.session.playing, isFalse);
      expect(h.player.failed, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      await _flushPlayer(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

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
