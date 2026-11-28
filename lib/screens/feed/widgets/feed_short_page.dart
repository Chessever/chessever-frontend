import 'dart:async';

import 'package:chessever2/screens/feed/models/feed_short.dart';
import 'package:chessever2/screens/feed/widgets/feed_short_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A Short's page: its cover where the video will play, and over it the
/// player that holds this Short ([FeedShortPlayers]), let through once its
/// picture moves.
///
/// The page owns no web view. The Feed's players outlive it, so a Short is
/// cued before its page is built and is still there, where it stopped, when
/// the viewer comes back up.
class FeedShortPage extends StatefulWidget {
  const FeedShortPage({
    super.key,
    required this.short,
    required this.players,
    required this.onOpened,
  });

  final FeedShort short;
  final FeedShortPlayers players;

  /// The Short has played in view for [watchedAfter]: once per page.
  final VoidCallback onOpened;

  /// How long a Short plays in view before it counts as watched.
  static const Duration watchedAfter = Duration(seconds: 4);

  @override
  State<FeedShortPage> createState() => _FeedShortPageState();
}

class _FeedShortPageState extends State<FeedShortPage> {
  /// The web view is let through over this long once the picture moves.
  static const Duration _fadeIn = Duration(milliseconds: 160);

  /// A web view waiting under its cover is still drawn, only unseen: one
  /// that is not drawn at all is taken off the screen, and a player off the
  /// screen does not start.
  static const double _unseen = 0.01;

  bool _reported = false;
  Timer? _watch;

  @override
  void initState() {
    super.initState();
    widget.players.addListener(_onPlayers);
    _syncWatch();
  }

  @override
  void didUpdateWidget(covariant FeedShortPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.players != widget.players) {
      oldWidget.players.removeListener(_onPlayers);
      widget.players.addListener(_onPlayers);
    }
    if (oldWidget.short.id != widget.short.id) {
      _watch?.cancel();
      _watch = null;
    }
    _syncWatch();
  }

  @override
  void dispose() {
    widget.players.removeListener(_onPlayers);
    _watch?.cancel();
    super.dispose();
  }

  void _onPlayers() {
    if (!mounted) return;
    // The players are told the Feed is no longer seen the moment a route
    // lands on it, which can be while this tree is building.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onPlayers();
      });
      return;
    }
    _syncWatch();
    setState(() {});
  }

  /// Whether this Short is the one in view and its picture is moving.
  bool get _watching {
    final player = widget.players.playerFor(widget.short.id);
    return player != null && player.active && player.playing;
  }

  /// Counts the Short as watched once it has played in view long enough.
  /// A stop, or the page left, starts the count over.
  void _syncWatch() {
    if (_reported || !_watching) {
      _watch?.cancel();
      _watch = null;
      return;
    }
    _watch ??= Timer(FeedShortPage.watchedAfter, () {
      _watch = null;
      if (!mounted || _reported || !_watching) return;
      _reported = true;
      widget.onOpened();
    });
  }

  @override
  Widget build(BuildContext context) {
    final players = widget.players;
    final short = widget.short;
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final player = players.playerFor(short.id);
          if (!players.supported ||
              players.cannotPlay(short.id) ||
              (player?.down ?? false) ||
              constraints.maxHeight < 200 ||
              constraints.maxWidth < 200) {
            return const _ShortUnavailable();
          }
          final view = player?.view;
          final active = player?.active ?? false;
          final showing = player?.showing ?? false;
          return Stack(
            fit: StackFit.expand,
            children: [
              FeedShortCover(
                image: players.coverOf(short.id),
                fallback: players.fallbackCoverOf(short.id),
              ),
              if (view != null)
                // Only the Short in view takes a touch, and only once its
                // player is seen: a tap on the cover must not reach a play
                // button nobody can see.
                IgnorePointer(
                  ignoring: !active || !showing,
                  child: AnimatedOpacity(
                    opacity: showing ? 1 : _unseen,
                    duration: _fadeIn,
                    curve: Curves.easeOut,
                    child: view,
                  ),
                ),
              if (active && !showing) const _ShortWaiting(),
            ],
          );
        },
      ),
    );
  }
}

/// A Short's cover, upright (9:16) and as large as the page allows: where
/// its video plays, so the first frame takes the cover's place without a
/// jump.
class FeedShortCover extends StatelessWidget {
  const FeedShortCover({
    super.key,
    required this.image,
    required this.fallback,
  });

  final ImageProvider image;

  /// Drawn when [image] cannot be loaded.
  final ImageProvider fallback;

  /// A cover that was read ahead is there with its page; one that arrives
  /// late comes up over a moment instead of cutting in.
  static Widget _arrive(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Image(
          image: image,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          frameBuilder: _arrive,
          errorBuilder: (context, _, _) => Image(
            image: fallback,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            frameBuilder: _arrive,
            errorBuilder: (context, _, _) => const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// The Short in view has not started: after a beat, a quiet spinner over
/// its cover. A Short that starts at once never shows it.
class _ShortWaiting extends StatefulWidget {
  const _ShortWaiting();

  @override
  State<_ShortWaiting> createState() => _ShortWaitingState();
}

class _ShortWaitingState extends State<_ShortWaiting> {
  static const Duration _after = Duration(milliseconds: 900);

  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_after, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox.shrink();
    return const IgnorePointer(
      child: Center(
        child: SizedBox.square(
          dimension: 26,
          child: CircularProgressIndicator(
            key: ValueKey('feed_short_waiting'),
            strokeWidth: 2.4,
            strokeCap: StrokeCap.round,
            color: Colors.white,
            // A dark track under the white arc: it reads on a bright cover
            // as well as on a dark one.
            backgroundColor: Color(0x66000000),
            semanticsLabel: 'Loading Short',
          ),
        ),
      ),
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
