import 'dart:async';
import 'dart:convert';

import 'package:chessever2/screens/chessboard/video/video_player.dart';
import 'package:chessever2/screens/chessboard/video/video_repository.dart';
import 'package:chessever2/screens/chessboard/video/video_stream.dart';
import 'package:chessever2/screens/feed/models/feed_short.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class FeedShortPage extends StatefulWidget {
  const FeedShortPage({
    super.key,
    required this.short,
    required this.active,
    required this.onOpened,
  });

  final FeedShort short;
  final bool active;
  final VoidCallback onOpened;

  @override
  State<FeedShortPage> createState() => _FeedShortPageState();
}

class _FeedShortPageState extends State<FeedShortPage> {
  bool _reported = false;

  void _reportOpened() {
    if (!mounted || _reported) return;
    _reported = true;
    widget.onOpened();
  }

  @override
  Widget build(BuildContext context) {
    final short = widget.short;
    final origin = EventVideoConfiguration.fromEnvironment()?.embedOrigin;
    final inlineSupported =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!widget.active) return const SizedBox.expand();
          if (!inlineSupported ||
              origin == null ||
              constraints.maxHeight < 200 ||
              constraints.maxWidth < 200) {
            return const _ShortUnavailable();
          }
          return SizedBox.expand(
            child: _InlineFeedShort(
              key: ValueKey(short.id),
              short: short,
              origin: origin,
              onWatched: _reportOpened,
            ),
          );
        },
      ),
    );
  }
}

class _InlineFeedShort extends StatefulWidget {
  const _InlineFeedShort({
    super.key,
    required this.short,
    required this.origin,
    required this.onWatched,
  });

  final FeedShort short;
  final Uri origin;
  final VoidCallback onWatched;

  @override
  State<_InlineFeedShort> createState() => _InlineFeedShortState();
}

class _InlineFeedShortState extends State<_InlineFeedShort> {
  WebViewController? _player;
  Timer? _watchTimer;
  bool _watched = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final params = WebViewPlatform.instance is WebKitWebViewPlatform
          ? WebKitWebViewControllerCreationParams(
              allowsInlineMediaPlayback: true,
              mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
            )
          : const PlatformWebViewControllerCreationParams();
      final controller = WebViewController.fromPlatformCreationParams(params);
      if (controller.platform case final AndroidWebViewController android) {
        await android.setMediaPlaybackRequiresUserGesture(false);
      }
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.black);
      await controller.addJavaScriptChannel(
        'ChessVideo',
        onMessageReceived: _onPlayerMessage,
      );
      final baseUrl = widget.origin.replace(path: '/').toString();
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              !request.isMainFrame ||
                  request.url == baseUrl ||
                  request.url == widget.origin.toString() ||
                  request.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && error.errorCode != -999) {
              _fail();
            }
          },
        ),
      );
      if (!mounted) return;
      setState(() => _player = controller);
      await controller.loadHtmlString(
        videoPlayerHtml(
          VideoSource(
            VideoPlatform.youtube,
            widget.short.id,
            widget.short.watchUrl,
          ),
          widget.origin,
          revision: 0,
          play: true,
          muted: true,
          nativeFullscreen: false,
          showCaptionsByDefault: false,
        ),
        baseUrl: baseUrl,
      );
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    _watchTimer?.cancel();
    if (mounted && !_failed) setState(() => _failed = true);
  }

  void _onPlayerMessage(JavaScriptMessage message) {
    if (!mounted || _failed) return;
    try {
      final data = jsonDecode(message.message);
      if (data is! Map) return;
      if (data['type'] == 'error') {
        _fail();
      } else if (data['type'] == 'playback' && !_watched) {
        if (data['playing'] == true) {
          _watchTimer ??= Timer(const Duration(seconds: 4), () {
            if (!mounted) return;
            _watched = true;
            widget.onWatched();
          });
        } else {
          _watchTimer?.cancel();
          _watchTimer = null;
        }
      }
    } on FormatException {
      // Ignore unrelated WebView messages.
    }
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    final player = _player;
    if (player != null) {
      unawaited(
        player
            .loadHtmlString('<!doctype html><html></html>')
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const _ShortUnavailable();
    final player = _player;
    if (player == null) return const Center(child: CircularProgressIndicator());
    return WebViewWidget(
      controller: player,
      // The vertical Feed swipe keeps ownership of vertical drags.
      gestureRecognizers: eventVideoGestureRecognizers,
    );
  }
}

class _ShortUnavailable extends StatelessWidget {
  const _ShortUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.videocam_off_outlined,
        color: Colors.white70,
        semanticLabel: 'Short unavailable',
      ),
    );
  }
}
