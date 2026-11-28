import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/screens/chessboard/video/video_player.dart'
    show eventVideoGestureRecognizers;
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// The Shorts worth a player around page [index] of [pages], the most
/// needed first: the page itself, the one after it, the one before it, then
/// those further on and one further back.
///
/// A Short far ahead is listed so its player is warm before its page is
/// even built; one just left is listed so going back up finds it as it was.
List<String> feedShortsNear(List<FeedEntry> pages, int index) {
  const steps = [0, 1, -1, 2, 3, 4, -2];
  final ids = <String>[];
  for (final step in steps) {
    final at = index + step;
    if (at < 0 || at >= pages.length) continue;
    if (pages[at] case FeedShortEntry(:final short)) {
      if (!ids.contains(short.id)) ids.add(short.id);
    }
  }
  return ids;
}

/// A Short's own upright cover (1080 by 1920), decoded no larger than a
/// phone shows it. The same provider is warmed ahead and drawn, so the
/// cover is there the moment its page is.
ImageProvider feedShortCover(String id) => ResizeImage(
  CachedNetworkImageProvider('https://i.ytimg.com/vi/$id/oar2.jpg'),
  width: 720,
);

/// The cover every YouTube video has, the Short upright in its middle: what
/// stands in when the upright one is missing.
ImageProvider feedShortFallbackCover(String id) =>
    CachedNetworkImageProvider('https://i.ytimg.com/vi/$id/hqdefault.jpg');

/// The page a Feed player lives in: one YouTube player that takes one Short
/// after another, so the next Short starts in a player that is already up
/// instead of a new web view, a new page and a new player each time.
///
/// `window.chessShort(id, on, sound)` says what it should be doing: hold
/// Short [id] (null: nothing), playing or not, with sound or without. The
/// same order again changes nothing: a Short the viewer paused stays
/// paused. It answers on the `ChessShort` channel:
///
/// * `ready`: the page is up and takes orders;
/// * `playing` / `idle`: the Short's picture is moving, or stopped;
/// * `sound`: whether it plays with sound (refused sound, or the viewer's
///   own mute button);
/// * `stalled`: it could not be started; `error`: this Short cannot play;
///   `offline`: YouTube's player could not be loaded.
///
/// It keeps a Short playing by itself: a play that is not taken is asked
/// again, and one refused with sound plays muted, then asks for its sound
/// back once the picture moves. A Short that ends starts over.
String feedShortPlayerHtml(Uri origin) =>
    _playerPage.replaceFirst('__SITE__', jsonEncode(origin.toString()));

const _playerPage = '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>html,body,#player,iframe{margin:0;width:100%;height:100%;border:0;background:#000;overflow:hidden;}</style>
</head><body><div id="player"></div><script>
var site=__SITE__;
var player=null,api=false,ready=false;
var want=null,held=null,active=false,sound=true;
var quiet=false,asked=false,tries=0,turn=0,watch=0,ear=0,settle=0,heard=null;
function send(type,data){try{ChessShort.postMessage(JSON.stringify(Object.assign({type:type,id:held},data||{})));}catch(e){}}
function state(){try{return player.getPlayerState();}catch(e){return -1;}}
function muted(){try{return !!player.isMuted();}catch(e){return false;}}
function voice(on){settle=Date.now()+1500;heard=null;try{if(on){player.unMute();}else{player.mute();}}catch(e){}}
function later(ms,fn){var t=turn;return setTimeout(function(){if(t===turn)fn();},ms);}
function rest(){active=false;turn++;clearTimeout(watch);clearTimeout(ear);try{if(ready)player.pauseVideo();}catch(e){}}
function play(){
  clearTimeout(watch);
  if(!active||!ready||!held)return;
  if(state()===1){playing();return;}
  tries++;
  voice(sound&&!quiet);
  try{player.playVideo();}catch(e){}
  watch=later(tries===1?1500:900,check);
}
function check(){
  var s=state();
  if(s===1)return;
  if(s===3){watch=later(900,check);return;}
  if(sound&&!quiet){quiet=true;play();return;}
  if(tries<7){play();return;}
  send('stalled');
}
function playing(){
  clearTimeout(watch);
  send('playing');
  if(sound&&!quiet&&muted())quiet=true;
  if(!sound||!quiet||asked)return;
  asked=true;
  ear=later(600,function(){voice(true);ear=later(800,function(){hear(0);});});
}
function hear(n){
  var s=state();
  if(s===3&&n<4){ear=later(600,function(){hear(n+1);});return;}
  if(s===1&&!muted()){quiet=false;send('sound',{on:true});return;}
  voice(false);
  try{player.playVideo();}catch(e){}
  send('sound',{on:false});
}
function onState(e){
  var s=e.data;
  if(s===1){
    if(!active){try{player.pauseVideo();}catch(x){}return;}
    playing();
    return;
  }
  send('idle',{state:s});
  if(s===0&&active){try{player.seekTo(0,true);player.playVideo();}catch(x){}}
}
function onBlocked(){if(active&&sound&&!quiet){quiet=true;play();}}
function onReady(){ready=true;apply();}
function onError(e){send('error',{code:e.data});}
function apply(){
  if(!api)return;
  if(!player){
    if(!want)return;
    held=want;
    try{
      player=new YT.Player('player',{width:'100%',height:'100%',videoId:want,
        playerVars:{autoplay:0,playsinline:1,fs:0,controls:1,rel:0,origin:site,hl:'en',cc_lang_pref:'en'},
        events:{onReady:onReady,onStateChange:onState,onError:onError,onAutoplayBlocked:onBlocked}});
    }catch(e){player=null;held=null;send('offline');}
    return;
  }
  if(!ready)return;
  if(!want){
    if(held){held=null;try{player.stopVideo();}catch(e){}}
    return;
  }
  if(held!==want){
    held=want;
    try{
      if(active){voice(sound&&!quiet);player.loadVideoById(want);}
      else{player.cueVideoById(want);}
    }catch(e){}
    if(active){tries=1;clearTimeout(watch);watch=later(1500,check);}
    return;
  }
  if(active)play();
}
window.chessShort=function(id,on,snd){
  id=id||null;on=!!(id&&on);sound=!!snd;
  if(id===want&&on===active)return;
  if(active)rest();
  want=id;
  if(on){active=true;turn++;quiet=false;asked=false;tries=0;}
  apply();
};
setInterval(function(){
  if(!active||!ready||state()!==1||Date.now()<settle)return;
  var m=muted();
  if(heard===null){heard=m;return;}
  if(m===heard)return;
  heard=m;
  if(!m)quiet=false;
  send('sound',{on:!m});
},1000);
window.onYouTubeIframeAPIReady=function(){api=true;send('ready');apply();};
</script><script src="https://www.youtube.com/iframe_api" onerror="send('offline')"></script></body></html>''';

/// The web view a Feed player draws in. Its own type so the players can be
/// driven in a test, where no platform view exists.
abstract class FeedShortSurface {
  /// Loads [html] as the page at [baseUrl], making the web view on the
  /// first call.
  Future<void> load(String html, {required String baseUrl});

  /// Runs [script] in the page; nothing before the web view exists.
  Future<void> run(String script);

  /// The web view, once it exists.
  Widget? get view;

  void dispose();
}

/// Makes a [FeedShortSurface] for a page served from [origin]. [onMessage]
/// hears what the page posts; [onLost] a page that died under it.
typedef FeedShortSurfaceBuilder =
    FeedShortSurface Function({
      required Uri origin,
      required ValueChanged<String> onMessage,
      required VoidCallback onLost,
    });

class _WebShortSurface implements FeedShortSurface {
  _WebShortSurface({
    required this.origin,
    required this.onMessage,
    required this.onLost,
  });

  final Uri origin;
  final ValueChanged<String> onMessage;
  final VoidCallback onLost;

  /// One platform view for the web view, moved rather than made again when
  /// the player goes from one Short's page to another's.
  final GlobalKey _viewKey = GlobalKey(debugLabel: 'feed_short_view');
  WebViewController? _controller;
  Future<WebViewController>? _opening;
  bool _disposed = false;

  Future<WebViewController> _open() async {
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
      'ChessShort',
      onMessageReceived: (message) {
        if (!_disposed) onMessage(message.message);
      },
    );
    final home = origin.replace(path: '/').toString();
    await controller.setNavigationDelegate(
      NavigationDelegate(
        // The player's own frames load; nothing replaces the page.
        onNavigationRequest: (request) =>
            !request.isMainFrame ||
                request.url == home ||
                request.url == origin.toString() ||
                request.url == 'about:blank'
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onWebResourceError: (error) {
          // WKWebView reports a deliberately replaced load as -999.
          if (_disposed ||
              error.isForMainFrame != true ||
              error.errorCode == -999) {
            return;
          }
          onLost();
        },
      ),
    );
    return _controller = controller;
  }

  @override
  Future<void> load(String html, {required String baseUrl}) async {
    final WebViewController controller;
    try {
      controller = await (_opening ??= _open());
    } catch (_) {
      _opening = null;
      rethrow;
    }
    if (_disposed) return;
    await controller.loadHtmlString(html, baseUrl: baseUrl);
  }

  @override
  Future<void> run(String script) async {
    final controller = _controller;
    if (controller == null || _disposed) return;
    await controller.runJavaScript(script);
  }

  @override
  Widget? get view {
    final controller = _controller;
    if (controller == null) return null;
    return WebViewWidget(
      key: _viewKey,
      controller: controller,
      // The vertical Feed swipe keeps ownership of vertical drags.
      gestureRecognizers: eventVideoGestureRecognizers,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    // The controller has no dispose of its own: blank the page so its sound
    // stops now, not when the platform view is let go.
    final controller = _controller;
    if (controller != null) {
      unawaited(
        controller
            .loadHtmlString('<!doctype html><html></html>')
            .catchError((Object _) {}),
      );
    }
  }
}

FeedShortSurface _webSurface({
  required Uri origin,
  required ValueChanged<String> onMessage,
  required VoidCallback onLost,
}) => _WebShortSurface(origin: origin, onMessage: onMessage, onLost: onLost);

/// One of the Feed's warm players: a web view with YouTube's player in it,
/// holding one Short at a time ([FeedShortPlayers] decides which).
class FeedShortPlayer {
  FeedShortPlayer._(this._owner, Uri origin) : _origin = origin {
    _surface = _owner._surfaces(
      origin: origin,
      onMessage: _heard,
      onLost: _lost,
    );
  }

  final FeedShortPlayers _owner;
  final Uri _origin;
  late final FeedShortSurface _surface;

  /// A page that died is loaded again this many times before the player
  /// counts as [down].
  static const int _maxReloads = 2;

  /// A Short that has not started by now is shown as its player stands, so
  /// YouTube's own play button and notices are within reach.
  static const Duration _showAnyway = Duration(seconds: 6);

  /// How long a Short left behind keeps its picture: the page is still on
  /// its way out of view. After it, its cover stands in again.
  static const Duration _coverAfter = Duration(milliseconds: 700);

  String? _shortId;
  bool _active = false;
  bool _asked = false;
  bool _ready = false;
  bool _showing = false;
  bool _playing = false;
  bool _down = false;
  bool _disposed = false;
  int _reloads = 0;

  /// The order the page was last given.
  String? _order;
  Timer? _reload;
  Timer? _reveal;
  Timer? _cover;

  /// The Short it holds; null while it waits for one.
  String? get shortId => _shortId;

  /// Its Short is the page in view: it should be playing.
  bool get active => _active;

  /// The Short's own picture is on: it has started (or could not, and its
  /// player is shown as it stands). Until then its cover is drawn.
  bool get showing => _showing;

  /// The picture is moving now.
  bool get playing => _playing;

  /// Its page could not be loaded, for now.
  bool get down => _down;

  /// The web view, once it exists.
  Widget? get view => _surface.view;

  void _hold(String? id) {
    if (_shortId == id) return;
    _shortId = id;
    _playing = false;
    _showing = false;
    _reveal?.cancel();
    _cover?.cancel();
    if (id == null) _active = false;
  }

  void _setActive(bool value) {
    final active = value && _shortId != null;
    if (_active == active) return;
    _active = active;
    _reveal?.cancel();
    _cover?.cancel();
    if (active) {
      _reveal = Timer(_showAnyway, () {
        if (_disposed || !_active || _showing) return;
        _showing = true;
        _owner._changed();
      });
    } else {
      _playing = false;
      if (_showing) {
        _cover = Timer(_coverAfter, () {
          if (_disposed || _active || !_showing) return;
          _showing = false;
          _owner._changed();
        });
      }
    }
  }

  /// Tells the page what it should be doing now.
  void _sync() {
    if (_disposed) return;
    if (_down) {
      // A new Short, or the viewer back on this one, is another try.
      if (_shortId == null) return;
      _down = false;
      _reloads = 0;
      _asked = false;
    }
    if (!_asked) {
      if (_shortId == null) return;
      _asked = true;
      unawaited(_load());
      return;
    }
    if (!_ready) return;
    final order =
        'window.chessShort&&window.chessShort('
        '${jsonEncode(_shortId)},$_active,${!_owner.startMuted})';
    // The page has this order already (one loaded anew has none: [_load]
    // forgets it). Said again it could start a Short the viewer paused.
    if (order == _order) return;
    _order = order;
    unawaited(_surface.run(order).catchError((Object _) {}));
  }

  Future<void> _load() async {
    _ready = false;
    _order = null;
    try {
      await _surface.load(
        feedShortPlayerHtml(_origin),
        baseUrl: _origin.replace(path: '/').toString(),
      );
      // Its web view exists now: the page that holds its Short draws it.
      if (!_disposed) _owner._changed();
    } catch (_) {
      _lost();
    }
  }

  /// The page died (its process was ended) or never came up (no network).
  void _lost() {
    if (_disposed) return;
    _ready = false;
    _order = null;
    _playing = false;
    _showing = false;
    _reload?.cancel();
    if (_reloads >= _maxReloads) {
      _down = true;
    } else {
      _reloads++;
      _reload = Timer(Duration(seconds: 2 * _reloads), () {
        if (!_disposed) unawaited(_load());
      });
    }
    _owner._changed();
  }

  void _heard(String message) {
    if (_disposed) return;
    final Object? data;
    try {
      data = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (data is! Map) return;
    final id = data['id'];
    switch (data['type']) {
      case 'ready':
        _ready = true;
        _sync();
      case 'offline':
        _lost();
      case 'playing' when id == _shortId && _active:
        _reloads = 0;
        _reveal?.cancel();
        _cover?.cancel();
        if (_playing && _showing) return;
        _playing = true;
        _showing = true;
        _owner._changed();
      case 'idle' when id == _shortId:
        if (!_playing) return;
        _playing = false;
        _owner._changed();
      case 'stalled' when id == _shortId && _active:
        _reveal?.cancel();
        if (_showing) return;
        _showing = true;
        _owner._changed();
      case 'sound':
        final on = data['on'];
        if (on is bool) _owner.startMuted = !on;
      case 'error' when id is String:
        _owner._cannotPlay(id);
    }
  }

  void _dispose() {
    _disposed = true;
    _reload?.cancel();
    _reveal?.cancel();
    _cover?.cancel();
    _surface.dispose();
  }
}

/// The Feed's Shorts players: a few warm web views shared by every Short,
/// held by the Feed screen for as long as it stands.
///
/// A web view with YouTube's player in it takes seconds to come up, so one
/// made as its page arrives shows black first and is gone again when the
/// page is left. Here the players outlive the pages:
///
/// * the Short in view, the next one and the last one each hold a player
///   ([hold]), so the next is already cued and going back up finds the last
///   where it stopped;
/// * a player is made once and takes one Short after another: a Short far
///   down the Feed starts in a player that is already up;
/// * one idle player stays warm through a run of boards and news.
///
/// Only the Short in view plays, and only while the Feed is [seen].
class FeedShortPlayers extends ChangeNotifier {
  FeedShortPlayers({
    required this.origin,
    FeedShortSurfaceBuilder? surfaces,
    bool? supported,
    ImageProvider Function(String id)? cover,
    ImageProvider Function(String id)? fallbackCover,
    this.capacity = 3,
  }) : _surfaces = surfaces ?? _webSurface,
       _supported =
           supported ??
           (!kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.iOS ||
                   defaultTargetPlatform == TargetPlatform.android)),
       coverOf = cover ?? feedShortCover,
       fallbackCoverOf = fallbackCover ?? feedShortFallbackCover;

  /// The site the players' page is served as: YouTube plays only for a page
  /// it can name. Null where none is configured; no Short plays then.
  final Uri? origin;
  final FeedShortSurfaceBuilder _surfaces;
  final bool _supported;

  /// A Short's cover and the one that stands in for it.
  final ImageProvider Function(String id) coverOf;
  final ImageProvider Function(String id) fallbackCoverOf;

  /// How many web views are kept at most: the Short in view and one each
  /// way.
  final int capacity;

  /// The next Short starts without sound: sound was refused here, or the
  /// viewer muted a Short themselves. Their unmuting one turns it back.
  bool startMuted = false;

  final List<FeedShortPlayer> _players = [];
  final Set<String> _cannotPlayIds = {};
  List<String> _wanted = const [];
  String? _current;
  bool _seen = true;
  bool _disposed = false;

  /// Whether a Short can play inline here at all.
  bool get supported => _supported && origin != null;

  /// The player holding Short [id], when one does.
  FeedShortPlayer? playerFor(String id) {
    for (final player in _players) {
      if (player._shortId == id) return player;
    }
    return null;
  }

  /// YouTube would not play Short [id] here (removed, or not embeddable).
  bool cannotPlay(String id) => _cannotPlayIds.contains(id);

  /// Holds players for [shorts], the most needed first ([feedShortsNear]),
  /// as many as [capacity] allows. [current] is the Short in view, when the
  /// page in view is one: it alone plays.
  void hold(List<String> shorts, {String? current}) {
    _wanted = List.of(shorts);
    _current = current;
    _apply();
  }

  /// Whether the Feed is seen: its route on top, the app in front. A Short
  /// stops the moment it is not.
  set seen(bool value) {
    if (_seen == value) return;
    _seen = value;
    _apply();
  }

  /// The system is short of memory: every player but the one playing goes.
  /// The pages left without one show their cover until they are reached.
  void trim() {
    if (_disposed) return;
    final kept = _players.where((player) => player._active).toList();
    if (kept.length == _players.length) return;
    for (final player in _players) {
      if (!kept.contains(player)) player._dispose();
    }
    _players
      ..clear()
      ..addAll(kept);
    notifyListeners();
  }

  void _apply() {
    final origin = this.origin;
    if (_disposed || origin == null || !_supported) return;
    final current = _current;
    final keep = <String>[
      if (current != null && !_cannotPlayIds.contains(current)) current,
    ];
    for (final id in _wanted) {
      if (keep.length >= capacity) break;
      if (!_cannotPlayIds.contains(id) && !keep.contains(id)) keep.add(id);
    }
    for (final player in _players) {
      final held = player._shortId;
      if (held != null && !keep.contains(held)) player._hold(null);
    }
    for (final id in keep) {
      if (playerFor(id) != null) continue;
      FeedShortPlayer? free;
      for (final player in _players) {
        if (player._shortId != null) continue;
        // A player whose page is up is the quickest start.
        if (free == null || (player._ready && !free._ready)) free = player;
      }
      if (free == null && _players.length < capacity) {
        free = FeedShortPlayer._(this, origin);
        _players.add(free);
      }
      free?._hold(id);
    }
    // One idle player stays warm for the next Short; the rest are let go.
    final idle = [
      for (final player in _players)
        if (player._shortId == null) player,
    ]..sort((a, b) => (b._ready ? 1 : 0) - (a._ready ? 1 : 0));
    for (final player in idle.skip(1)) {
      _players.remove(player);
      player._dispose();
    }
    for (final player in _players) {
      player
        .._setActive(_seen && current != null && player._shortId == current)
        .._sync();
    }
    notifyListeners();
  }

  void _cannotPlay(String id) {
    if (_disposed || !_cannotPlayIds.add(id)) return;
    _apply();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final player in _players) {
      player._dispose();
    }
    _players.clear();
    super.dispose();
  }
}
