import 'dart:async';

import 'package:chessever2/screens/chessboard/video/video_player.dart';
import 'package:chessever2/screens/chessboard/video/video_repository.dart';
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_stream.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

typedef StoryShortClock = ({
  Duration duration,
  Duration position,
  bool buffering,
  bool ended,
});

/// Mounted only for the current slide. MP4 uses the platform texture, and
/// YouTube reuses the provider's inline player and embed rules.
class StoryShortPlayer extends StatefulWidget {
  const StoryShortPlayer({
    super.key,
    required this.url,
    required this.playing,
    required this.poster,
    required this.onClock,
  });

  final Uri url;
  final ValueListenable<bool> playing;
  final Widget poster;
  final ValueChanged<StoryShortClock?> onClock;

  @override
  State<StoryShortPlayer> createState() => _StoryShortPlayerState();
}

class _StoryShortPlayerState extends State<StoryShortPlayer> {
  VideoPlayerController? _native;
  NativeEventVideoPlayer? _youtube;
  EventVideoSession? _session;
  Timer? _startup;
  bool _ready = false;
  bool _failed = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    widget.playing.addListener(_play);
    _startup = Timer(const Duration(seconds: 12), _fail);
    if (widget.url.path.toLowerCase().endsWith('.mp4')) {
      unawaited(_openNative());
    } else {
      _openYoutube();
    }
  }

  Future<void> _openNative() async {
    final player = VideoPlayerController.networkUrl(widget.url);
    _native = player;
    try {
      await player.initialize();
      if (!mounted || _failed) return;
      await player.setVolume(0);
      if (!mounted || _failed) return;
      player.addListener(_nativeClock);
      _nativeClock();
      _play();
    } catch (_) {
      if (mounted) _fail();
    }
  }

  void _openYoutube() {
    final origin = EventVideoConfiguration.fromEnvironment()?.embedOrigin;
    if (origin == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fail();
      });
      return;
    }
    try {
      final url = widget.url.replace(
        queryParameters: {
          ...widget.url.queryParameters,
          'mute': '1',
          'loop': '0',
        },
      );
      final session = EventVideoSession(repository: null);
      final player = NativeEventVideoPlayer(
        origin,
        onInlineTiming: (seconds, duration, buffering, ended) {
          if (!duration.isFinite || !seconds.isFinite || duration <= 0) return;
          _report((
            duration: Duration(milliseconds: (duration * 1000).round()),
            position: Duration(milliseconds: (seconds * 1000).round()),
            buffering: buffering,
            ended: ended,
          ));
        },
      );
      _youtube = player;
      _session = session;
      player.addListener(_youtubeChanged);
      session.setAnalysisStreams([
        EventVideoStream(
          id: 'story-short',
          label: 'Short video',
          source: VideoSource.parse(url.toString()),
          analysis: true,
        ),
      ]);
      player.setInlinePlayback(widget.playing.value);
      player.synchronize(session);
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fail();
      });
    }
  }

  void _youtubeChanged() {
    if (!mounted) return;
    if (_youtube?.failed == true) {
      _fail();
    } else {
      setState(() {});
    }
  }

  void _nativeClock() {
    final value = _native?.value;
    if (value == null) return;
    if (value.hasError) {
      _fail();
    } else if (value.isInitialized && value.duration > Duration.zero) {
      _report((
        duration: value.duration,
        position: value.position,
        buffering: value.isBuffering,
        ended: value.isCompleted,
      ));
    }
  }

  void _report(StoryShortClock value) {
    if (!mounted || _failed) return;
    if (!_ready) {
      _startup?.cancel();
      setState(() => _ready = true);
    }
    widget.onClock(value);
  }

  void _fail() {
    if (!mounted || _failed) return;
    _startup?.cancel();
    setState(() => _failed = true);
    _play();
    widget.onClock(null);
  }

  void _play() {
    final play = widget.playing.value && !_failed;
    _youtube?.setInlinePlayback(play);
    final player = _native;
    if (player == null ||
        !player.value.isInitialized ||
        player.value.isCompleted) {
      return;
    }
    unawaited(
      (play ? player.play() : player.pause()).catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _startup?.cancel();
    widget.playing.removeListener(_play);
    final native = _native;
    native?.removeListener(_nativeClock);
    if (native != null) unawaited(native.dispose());
    _youtube?.removeListener(_youtubeChanged);
    _youtube?.dispose();
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final native = _native;
    final youtube = _youtube;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.poster,
        if (!_failed && youtube != null)
          Opacity(opacity: _ready ? 1 : 0, child: youtube.buildView()),
        if (!_failed && _ready && native != null) ...[
          RepaintBoundary(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox.fromSize(
                size: native.value.size,
                child: VideoPlayer(native),
              ),
            ),
          ),
          PositionedDirectional(
            bottom: 10,
            end: 10,
            child: IconButton.filledTonal(
              tooltip: _muted ? 'Unmute video' : 'Mute video',
              onPressed: () {
                setState(() => _muted = !_muted);
                unawaited(
                  native.setVolume(_muted ? 0 : 1).catchError((Object _) {}),
                );
              },
              icon: Icon(
                _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              ),
            ),
          ),
        ],
        if (_failed)
          const Center(
            child: Text(
              'Video unavailable',
              style: TextStyle(color: Colors.white),
            ),
          ),
      ],
    );
  }
}
