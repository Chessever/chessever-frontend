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

  /// Provider-native fullscreen view (Android custom view), or null when the
  /// player is inline. iOS presents provider fullscreen itself, so this stays
  /// null there. Plain Dart state with no-op defaults so fakes stay trivial.
  Widget? get fullscreenView => null;
  void enterFullscreen(Widget view, VoidCallback onHidden) {}
  void exitFullscreen() {}
  void closeFullscreen() {}

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
  int _playNudge = 0;
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
      final android = controller.platform as AndroidWebViewController;
      await android.setMediaPlaybackRequiresUserGesture(false);
      // Android renders a video element's fullscreen request in a custom view
      // the platform denies by default, so YouTube/Twitch/Kick fullscreen
      // silently does nothing without these callbacks. iOS needs no wiring:
      // WKWebView presents provider fullscreen itself.
      await android.setCustomWidgetCallbacks(
        onShowCustomWidget: (view, onHidden) => enterFullscreen(view, onHidden),
        onHideCustomWidget: exitFullscreen,
      );
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
          } else if (data['type'] == 'muted' && data['muted'] is bool) {
            _session?.reportMuted(data['muted'] as bool, _revision);
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
    if (_revision == session.playerRevision) {
      // A same-event game change keeps the document; the page swap may have
      // paused the HTML5 element when the native view reattached, so re-assert
      // playback once without reloading.
      if (_playNudge != session.playNudge) {
        _playNudge = session.playNudge;
        _schedulePlayNudge();
      }
      return;
    }
    _playNudge = session.playNudge;
    // A new revision replaces the document; leaving the platform's custom view
    // up would strand it over the next stream.
    closeFullscreen();
    _revision = session.playerRevision;
    _documentRevision = -1;
    _requestedRevision = -1;
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    _playNudgeTimer?.cancel();
    _playNudgeTimer = null;
    final session = _session;
    if (session == null) return;
    final generation = ++_generation;
    // Defer platform calls until after the current widget build.
    unawaited(
      Future<void>(() async {
        try {
          if (_disposed || generation != _generation) return;
          // Capture a just-flipped mute button before replacing the document,
          // including a switch that happens before the next bridge poll. The
          // helper is undefined once the old document is gone, so a stale
          // player simply reports nothing.
          if (_controller != null) {
            try {
              final value = await _controller!.runJavaScriptReturningResult(
                'window.chessVideoMuted ? window.chessVideoMuted() : null',
              );
              if (_disposed || generation != _generation) return;
              if (value == true || value == 'true') {
                session.reportMuted(true, _revision);
              } else if (value == false || value == 'false') {
                session.reportMuted(false, _revision);
              }
            } catch (_) {
              // Providers without a sound API retain the last known setting.
            }
          }
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
              muted: session.muted,
              nativeFullscreen: defaultTargetPlatform != TargetPlatform.iOS,
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

  Widget? _fullscreenView;
  VoidCallback? _exitFullscreenNative;

  @override
  Widget? get fullscreenView => _fullscreenView;

  /// The provider entered native fullscreen (Android custom view). Pure
  /// overlay state: the document and revision are untouched, so exiting
  /// returns to the exact same player with no reload.
  @override
  void enterFullscreen(Widget view, VoidCallback onHidden) {
    if (_disposed || !_acceptsDocumentEvents) {
      onHidden();
      return;
    }
    // Some embeds pause the HTML5 element while the Android custom view
    // attaches. Remember whether the stream was actually playing so it can be
    // nudged back instead of stopping until the reader taps play again. A
    // stream the reader paused stays paused.
    final wasLive = _session?.playing == true;
    _fullscreenView = view;
    _exitFullscreenNative = onHidden;
    notifyListeners();
    if (wasLive) _scheduleResumeAfterFullscreen();
  }

  Timer? _resumeTimer;

  /// One-shot resume fired after provider fullscreen opens. Only nudges the
  /// document when the fullscreen view is still up and the stream was live
  /// before the transition; providers without a play hook are a no-op.
  void _scheduleResumeAfterFullscreen() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(milliseconds: 400), () {
      _resumeTimer = null;
      if (_disposed || _fullscreenView == null) return;
      final controller = _controller;
      if (controller == null) return;
      unawaited(
        controller
            .runJavaScript('window.chessVideoPlay && window.chessVideoPlay()')
            .catchError((Object _) {
              // Kick has no documented playback API; its frame keeps playing
              // on its own or the reader presses play.
            }),
      );
    });
  }

  void _cancelResumeAfterFullscreen() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }

  Timer? _playNudgeTimer;

  /// One-shot playback re-assert after a same-event game change. The native
  /// view can pause while the page swap reattaches it; this runs the provider
  /// play hook again without touching the document.
  void _schedulePlayNudge() {
    _playNudgeTimer?.cancel();
    _playNudgeTimer = Timer(const Duration(milliseconds: 400), () {
      _playNudgeTimer = null;
      if (_disposed || !_acceptsDocumentEvents) return;
      final controller = _controller;
      if (controller == null) return;
      unawaited(
        controller
            .runJavaScript('window.chessVideoPlay && window.chessVideoPlay()')
            .catchError((Object _) {}),
      );
    });
  }

  @override
  void exitFullscreen() {
    if (_disposed || _fullscreenView == null) return;
    _cancelResumeAfterFullscreen();
    _fullscreenView = null;
    _exitFullscreenNative = null;
    notifyListeners();
  }

  /// App-initiated exit (back button or the overlay's own control): clears the
  /// overlay immediately and asks the platform to hide its custom view, so the
  /// platform's later [exitFullscreen] callback is a no-op.
  @override
  void closeFullscreen() {
    if (_fullscreenView == null && _exitFullscreenNative == null) return;
    _cancelResumeAfterFullscreen();
    final hide = _exitFullscreenNative;
    _exitFullscreenNative = null;
    _fullscreenView = null;
    hide?.call();
    if (!_disposed) notifyListeners();
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
    _cancelResumeAfterFullscreen();
    _playNudgeTimer?.cancel();
    _playNudgeTimer = null;
    // Leaving fullscreen behind would strand the platform custom view after
    // the player is gone.
    _exitFullscreenNative?.call();
    _exitFullscreenNative = null;
    _fullscreenView = null;
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
/// [muted] is the last mute state the provider player reported; it is applied
/// on load so switching streams carries the user's mute choice across.
/// Provider chrome is always enabled: the reader gets the familiar controls
/// (play, mute, quality, fullscreen) without any reload-on-tap machinery.
String videoPlayerHtml(
  VideoSource source,
  Uri origin, {
  required int revision,
  required bool play,
  required bool muted,
  bool nativeFullscreen = true,
}) {
  final id = jsonEncode(source.id),
      host = jsonEncode(origin.host),
      parent = jsonEncode(origin.toString());
  final autoplay = play ? 'true' : 'false';
  final mutedFlag = muted ? 'true' : 'false';
  // The tap that chose the stream is the play gesture. Autoplay params alone
  // can be ignored, so each provider is also started explicitly once ready.
  final youtubeStart = play ? 'try{ytPlayer.playVideo();}catch(e){}' : '';
  final twitchStart = play ? 'try{p.play();}catch(e){}' : '';
  // Fullscreen hook used to nudge a live stream back if the HTML5 element
  // paused while the Android custom view attached.
  final youtubePlayHook =
      play
          ? 'window.chessVideoPlay=()=>{try{ytPlayer.playVideo();}catch(e){}};'
          : '';
  final twitchPlayHook =
      play ? 'window.chessVideoPlay=()=>{try{p.play();}catch(e){}};' : '';
  final provider = switch (source.platform) {
    VideoPlatform.youtube => '''
<script>
function onYouTubeIframeAPIReady() {
  const ytPlayer=new YT.Player('player', {width:'100%', height:'100%', videoId:$id,
    playerVars:{autoplay:${play ? 1 : 0}, playsinline:1, fs:${nativeFullscreen ? 1 : 0}, origin:$parent, mute:${muted ? 1 : 0}, controls:1, modestbranding:1, rel:0, iv_load_policy:3},
    events:{onReady:()=>{try{ytPlayer.${muted ? 'mute' : 'unMute'}();}catch(e){}$youtubeStart$youtubePlayHook watchMuted(()=>ytPlayer.isMuted());},onStateChange:e=>send('playback',{playing:e.data===1}), onError:()=>send('error',{})}});
}
</script><script src="https://www.youtube.com/iframe_api" onerror="send('error',{})"></script>''',
    VideoPlatform.twitch => '''
<script src="https://player.twitch.tv/js/embed/v1.js" onerror="send('error',{})"></script>
<script>
try {
  const p=new Twitch.Player('player',{width:'100%',height:'100%',channel:$id,parent:[$host],autoplay:$autoplay,muted:$mutedFlag,controls:true});
  p.addEventListener(Twitch.Player.PLAYING,()=>send('playback',{playing:true}));
  p.addEventListener(Twitch.Player.PAUSE,()=>send('playback',{playing:false}));
  p.addEventListener(Twitch.Player.ENDED,()=>send('playback',{playing:false}));
  p.addEventListener(Twitch.Player.OFFLINE,()=>send('playback',{playing:false}));
  try{p.setMuted($mutedFlag);}catch(e){}
  $twitchStart$twitchPlayHook
  watchMuted(()=>p.getMuted());
} catch(e) {send('error',{});}
</script>''',
    // Kick documents an iframe, but no supported playback-state event API.
    // Do not guess that a pointer-down means "playing". Switching away from
    // Kick stays paused unless a future documented adapter can confirm state.
    // Mute is likewise unreadable inside the Kick frame, so the last mute state
    // known from another provider carries into its embed URL.
    VideoPlatform.kick => '''
<script>
const frame=document.createElement('iframe');
frame.src='https://player.kick.com/'+encodeURIComponent($id)+'?autoplay=$autoplay&muted=$mutedFlag&controls=true';
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
function watchMuted(read){window.chessVideoMuted=read;let last=null;setInterval(()=>{try{Promise.resolve(read()).then(m=>{if(m===null||m===undefined)return;m=!!m;if(m!==last){last=m;send('muted',{muted:m});}}).catch(()=>{});}catch(e){}},1000);}
window.chessVideoPlay=()=>{};
</script>$provider</body></html>''';
}
