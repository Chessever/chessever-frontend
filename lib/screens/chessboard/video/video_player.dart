import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'video_session.dart';
import 'video_stream.dart';

/// Let the surrounding game scroll own vertical drags. Horizontal drags stay
/// in the player (e.g. seeking) rather than switching the PageView's game.
/// Unclaimed taps are forwarded to the WebView by the platform-view gesture
/// arena, so Play/Pause and other native provider controls remain interactive.
const eventVideoGestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
  Factory<EventVideoSeekGestureRecognizer>(EventVideoSeekGestureRecognizer.new),
};

/// Decide the axis before the enclosing game PageView reaches its drag slop.
/// A normal horizontal recognizer can lose that race on native WebViews.
class EventVideoSeekGestureRecognizer extends OneSequenceGestureRecognizer {
  final Map<int, Offset> _starts = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _starts[event.pointer] = event.position;
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    final start = _starts[event.pointer];
    if (start == null) return;
    if (event is PointerMoveEvent) {
      final delta = event.position - start;
      if (delta.distance >= 4) {
        resolvePointer(
          event.pointer,
          delta.dx.abs() > delta.dy.abs()
              ? GestureDisposition.accepted
              : GestureDisposition.rejected,
        );
        _starts.remove(event.pointer);
        stopTrackingPointer(event.pointer);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      resolvePointer(event.pointer, GestureDisposition.rejected);
      _starts.remove(event.pointer);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'event video seek';
}

// WebViewController rejects an empty HTML string, including during cleanup.
const _stoppedVideoHtml =
    '<!doctype html><html><body style="background:#000"></body></html>';

abstract class EventVideoPlayer extends ChangeNotifier {
  bool get failed;
  void synchronize(EventVideoSession session);
  Widget buildView();
  void retry();
}

/// Controller outlives the game page/platform widget. The GlobalKey transfers
/// its sole view between active pages and the expanded viewer in the same frame.
class NativeEventVideoPlayer extends EventVideoPlayer {
  NativeEventVideoPlayer(
    this.embedOrigin, {
    Future<bool> Function(Uri)? openExternal,
  }) : _openExternal = openExternal ?? _launchExternal;
  final Future<bool> Function(Uri) _openExternal;
  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
  final Uri embedOrigin;
  final GlobalKey _viewKey = GlobalKey(debugLabel: 'event_video_native_view');
  WebViewController? _controller;
  Future<void>? _ready;
  EventVideoSession? _session;
  int _revision = -1, _generation = 0, _requestedRevision = -1;
  int _documentRevision = -1;
  bool _failed = false, _disposed = false;

  bool get _acceptsDocumentEvents =>
      !_disposed &&
      _session?.foreground == true &&
      _session?.showVideo == true &&
      _documentRevision == _revision;
  @override
  bool get failed => _failed;

  Future<void> _initialize() async {
    PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    final controller = WebViewController.fromPlatformCreationParams(params);
    _controller = controller;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(Colors.black);
    if (controller.platform is AndroidWebViewController) {
      await (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    await controller.addJavaScriptChannel(
      'ChessVideo',
      onMessageReceived: (message) {
        if (!_acceptsDocumentEvents) return;
        try {
          final data = jsonDecode(message.message);
          if (data is! Map || data['revision'] != _revision) return;
          if (data['type'] == 'playback' && data['playing'] is bool) {
            _session?.reportPlayback(data['playing'] as bool, _revision);
          } else if (data['type'] == 'error') {
            _session?.reportPlayback(false, _revision);
            _setFailed(true);
          }
        } on FormatException {
          /* Ignore unrelated provider messages. */
        }
      },
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) async {
          final uri = Uri.tryParse(request.url);
          final youtubeLink =
              uri != null &&
              uri.scheme == 'https' &&
              uri.userInfo.isEmpty &&
              const {
                'youtube.com',
                'www.youtube.com',
                'm.youtube.com',
                'youtu.be',
              }.contains(uri.host) &&
              (uri.path == '/' ||
                  uri.path.isEmpty ||
                  uri.path == '/watch' ||
                  uri.path.startsWith('/@') ||
                  uri.path.startsWith('/channel/') ||
                  uri.host == 'youtu.be');
          // YouTube's logo opens a watch page, sometimes in a new frame.
          // Keep embed/API navigation inside the player, but hand these links
          // to the YouTube app (or browser) rather than swallowing the tap.
          if (youtubeLink && _acceptsDocumentEvents) {
            try {
              if (await _openExternal(uri)) _session?.stopPlayback();
            } catch (_) {
              // A failed external launch must not break the embedded player.
            }
            return NavigationDecision.prevent;
          }
          // Provider frames keep their own offline/login notices. Links must not
          // replace the trusted wrapper or launch another app without a UI action.
          if (!request.isMainFrame ||
              request.url == 'about:blank' ||
              request.url == embedOrigin.toString() ||
              request.url == '${embedOrigin.toString()}/') {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          // WKWebView reports NSURLErrorCancelled (-999) when an old load is
          // deliberately replaced. It can arrive after the board has returned.
          if (!_acceptsDocumentEvents ||
              error.isForMainFrame != true ||
              error.errorCode == -999) {
            return;
          }
          _session?.reportPlayback(false, _revision);
          _setFailed(true);
        },
      ),
    );
    if (!_disposed) notifyListeners();
  }

  void _setFailed(bool value) {
    if (_disposed || value == _failed) return;
    _failed = value;
    notifyListeners();
  }

  @override
  void synchronize(EventVideoSession session) {
    _session = session;
    if (_revision == session.playerRevision) return;
    _revision = session.playerRevision;
    _documentRevision = -1;
    _requestedRevision = -1;
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    final session = _session;
    if (session == null) return;
    final generation = ++_generation;
    // Defer platform calls until after the current widget build.
    unawaited(
      Future<void>(() async {
        try {
          if (_disposed || generation != _generation) return;
          final selected = session.selected;
          if (!session.showVideo ||
              !session.foreground ||
              selected == null ||
              _requestedRevision != _revision) {
            if (_controller != null) {
              await _controller!.loadHtmlString(_stoppedVideoHtml);
            }
            return;
          }
          await (_ready ??= _initialize());
          if (_disposed || generation != _generation) return;
          _setFailed(false);
          _documentRevision = _revision;
          await _controller!.loadHtmlString(
            videoPlayerHtml(
              selected.source,
              embedOrigin,
              revision: _revision,
              play: session.playRequested,
            ),
            baseUrl: '${embedOrigin.toString()}/',
          );
        } catch (_) {
          if (!_disposed &&
              generation == _generation &&
              session.foreground &&
              session.showVideo &&
              _requestedRevision == _revision) {
            _ready = null;
            _setFailed(true);
          }
        }
      }),
    );
  }

  @override
  Widget buildView() {
    // A selected Twitch stream may only have an "expand" button on a phone.
    // Load it only when a real, sufficiently-sized view requests presentation.
    if (_requestedRevision != _revision) {
      _requestedRevision = _revision;
      _scheduleUpdate();
    }
    return _controller == null
        ? const Center(child: CircularProgressIndicator())
        : WebViewWidget(
          key: _viewKey,
          controller: _controller!,
          gestureRecognizers: eventVideoGestureRecognizers,
        );
  }

  @override
  void retry() {
    final session = _session;
    if (session == null) return;
    session.stopPlayback();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    // WKWebView/Android controller has no dispose API. Blank it explicitly so
    // audio stops even before the final platform view is detached.
    final controller = _controller;
    if (controller != null) {
      unawaited(
        controller.loadHtmlString(_stoppedVideoHtml).catchError((Object _) {}),
      );
    }
    super.dispose();
  }
}

/// Only validated provider IDs enter this document. No backend embed HTML.
String videoPlayerHtml(
  VideoSource source,
  Uri origin, {
  required int revision,
  required bool play,
}) {
  final id = jsonEncode(source.id),
      host = jsonEncode(origin.host),
      parent = jsonEncode(origin.toString());
  final autoplay = play ? 'true' : 'false';
  final provider = switch (source.platform) {
    VideoPlatform.youtube => '''
<script>
function onYouTubeIframeAPIReady() {
  new YT.Player('player', {width:'100%', height:'100%', videoId:$id,
    playerVars:{autoplay:${play ? 1 : 0}, playsinline:1, origin:$parent, mute:0},
    events:{onStateChange:e=>send('playback',{playing:e.data===1}), onError:()=>send('error',{})}});
}
</script><script src="https://www.youtube.com/iframe_api" onerror="send('error',{})"></script>''',
    VideoPlatform.twitch => '''
<script src="https://player.twitch.tv/js/embed/v1.js" onerror="send('error',{})"></script>
<script>
try {
  const p=new Twitch.Player('player',{width:'100%',height:'100%',channel:$id,parent:[$host],autoplay:$autoplay,muted:false});
  p.addEventListener(Twitch.Player.PLAYING,()=>send('playback',{playing:true}));
  p.addEventListener(Twitch.Player.PAUSE,()=>send('playback',{playing:false}));
  p.addEventListener(Twitch.Player.ENDED,()=>send('playback',{playing:false}));
  p.addEventListener(Twitch.Player.OFFLINE,()=>send('playback',{playing:false}));
} catch(e) {send('error',{});}
</script>''',
    // Kick documents an iframe, but no supported playback-state event API.
    // Do not guess that a pointer-down means "playing". Switching away from
    // Kick stays paused unless a future documented adapter can confirm state.
    VideoPlatform.kick => '''
<script>
const frame=document.createElement('iframe');
frame.src='https://player.kick.com/'+encodeURIComponent($id)+'?autoplay=$autoplay&muted=false';
frame.allow='autoplay; fullscreen; picture-in-picture; encrypted-media';
frame.allowFullscreen=true;frame.title='Kick video';
frame.referrerPolicy='strict-origin-when-cross-origin';
document.getElementById('player').replaceWith(frame);
</script>''',
  };
  return '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>html,body,#player,iframe{margin:0;width:100%;height:100%;border:0;background:#000;overflow:hidden;}</style>
</head><body><div id="player"></div><script>
function send(type,data){ChessVideo.postMessage(JSON.stringify({type,revision:$revision,...data}));}
</script>$provider</body></html>''';
}
