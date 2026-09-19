import 'dart:async';
import 'dart:math' as math;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'video_player.dart';
import 'video_repository.dart';
import 'video_session.dart';
import 'video_stream.dart';

class EventVideoScope extends InheritedNotifier<EventVideoSession> {
  const EventVideoScope({
    super.key,
    required EventVideoSession session,
    required this.player,
    this.onVideoInteraction,
    required super.child,
  }) : super(notifier: session);
  final EventVideoPlayer? player;
  final VoidCallback? onVideoInteraction;
  EventVideoSession get session => notifier!;

  /// Rebuilds the caller on every session change (flags timers, metadata
  /// polls, foreground flips). Only the video's own small widgets use this;
  /// the board reads [EventVideoLayoutScope] instead.
  static EventVideoScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EventVideoScope>();

  /// The session for callbacks, without subscribing the caller to it.
  static EventVideoSession? sessionOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EventVideoScope>()?.session;
}

/// The only session facts the board layout reacts to.
///
/// Game pages carry the board, notation and explorer, and three of them are
/// alive at once. Depending on the session itself rebuilt all three on every
/// metadata poll, flags timer and route change, even with video hidden. This
/// snapshot compares by value, so those events rebuild nothing on the board,
/// and an event without streams (or with video hidden) never changes it.
@immutable
class EventVideoLayout {
  const EventVideoLayout({
    required this.hasVideo,
    required this.visible,
    required this.gameId,
    required this.tourId,
  });

  factory EventVideoLayout.of(EventVideoSession session) {
    final hasVideo = session.hasVideo;
    return EventVideoLayout(
      hasVideo: hasVideo,
      visible: hasVideo && session.visible,
      // Irrelevant facts are blanked so they cannot trigger a rebuild.
      gameId: hasVideo ? session.gameId : '',
      tourId: session.showVideo ? session.tourId : '',
    );
  }

  final bool hasVideo, visible;
  final String gameId, tourId;

  bool get showVideo => hasVideo && visible;
  bool isActive(String id) => hasVideo && gameId == id;

  /// Whether pages of [tourId] use the watch layout.
  bool watches(String tourId) => showVideo && this.tourId == tourId;

  @override
  bool operator ==(Object other) =>
      other is EventVideoLayout &&
      other.hasVideo == hasVideo &&
      other.visible == visible &&
      other.gameId == gameId &&
      other.tourId == tourId;

  @override
  int get hashCode => Object.hash(hasVideo, visible, gameId, tourId);
}

class EventVideoLayoutScope extends InheritedWidget {
  const EventVideoLayoutScope({
    super.key,
    required this.layout,
    required super.child,
  });
  final EventVideoLayout layout;

  static EventVideoLayout? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<EventVideoLayoutScope>()
          ?.layout;

  /// For callbacks: reads the snapshot without subscribing the caller.
  static EventVideoLayout? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EventVideoLayoutScope>()?.layout;

  @override
  bool updateShouldNotify(EventVideoLayoutScope oldWidget) =>
      layout != oldWidget.layout;
}

class EventVideoHost extends StatefulWidget {
  const EventVideoHost({
    super.key,
    required this.gameId,
    required this.tourId,
    required this.roundId,
    required this.child,
    this.session,
    this.player,
    this.pageObserver,
    this.preferredCountry,
    this.onVideoInteraction,
  });
  final String gameId, tourId, roundId;
  final String? preferredCountry;
  final VoidCallback? onVideoInteraction;
  final Widget child;

  /// Injectable ownership boundary for tests; otherwise uses the app flavor.
  final EventVideoSession? session;
  final EventVideoPlayer? player;
  final RouteObserver<PageRoute<dynamic>>? pageObserver;
  @override
  State<EventVideoHost> createState() => EventVideoHostState();
}

class EventVideoHostState extends State<EventVideoHost>
    with WidgetsBindingObserver, RouteAware {
  late final EventVideoSession session;
  EventVideoPlayer? _player;
  bool _ready = false, _routeVisible = true;
  PageRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seed the metrics baseline, otherwise the first real rotation would look
    // like a metrics event with no previous size and be ignored.
    _lastMetricsSize ??= View.of(context).physicalSize;
    final route = ModalRoute.of(context);
    if (route == _route) return;
    widget.pageObserver?.unsubscribe(this);
    _route = route is PageRoute<dynamic> ? route : null;
    if (_route != null) widget.pageObserver?.subscribe(this, _route!);
  }

  // Popup menus and sheets leave the video visible and must not clear it.
  @override
  void didPushNext() => setRouteVisible(false);

  @override
  void didPopNext() => setRouteVisible(true);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final config = EventVideoConfiguration.fromEnvironment();
    session =
        widget.session ??
        EventVideoSession(
          repository: config == null ? null : HttpEventVideoRepository(config),
          saveVisibility: (visible) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('ce-video-visible.v1', visible);
          },
          saveCountry: (country) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('ce-video-country.v1', country);
          },
          saveLanguage: (language) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('ce-video-language.v1', language);
          },
        );
    _player =
        widget.player ??
        (config == null ? null : NativeEventVideoPlayer(config.embedOrigin));
    session.addListener(_synchronize);
    _player?.addListener(_checkFullscreenExit);
    session.setPreferredCountry(widget.preferredCountry);
    if (widget.session != null || config == null) {
      _ready = true;
      _open();
    } else {
      unawaited(_loadLanguage());
    }
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      session.savedCountry = prefs.getString('ce-video-country.v1');
      session.visible = prefs.getBool('ce-video-visible.v1') ?? true;
      session.rememberedLanguage = prefs.getString('ce-video-language.v1');
    } catch (_) {
      /* Preferences are optional. */
    }
    if (!mounted) return;
    _ready = true;
    _open();
  }

  void _open() => session.openGame(
    gameId: widget.gameId,
    tourId: widget.tourId,
    roundId: widget.roundId,
  );
  void _synchronize() => _player?.synchronize(session);

  bool _wasFullscreen = false;

  /// Last surface size seen by [didChangeMetrics], so inset-only churn can be
  /// told apart from a real resize or rotation.
  Size? _lastMetricsSize;

  void _checkFullscreenExit() {
    final isFullscreen = _player?.fullscreenView != null;
    final exited = _wasFullscreen && !isFullscreen;
    _wasFullscreen = isFullscreen;
    // Leaving provider fullscreen onto a narrow inline Twitch view must stop
    // the now-invisible player, mirroring the rotation guard.
    if (exited) _maybeStopForNarrowTwitch();
  }

  /// Back-press layering: a provider fullscreen overlay consumes the press
  /// before the expanded viewer, the game switcher, or the route itself.
  /// Returns true when an open fullscreen was asked to close.
  bool closeFullscreenIfOpen() {
    if (_player?.fullscreenView == null) return false;
    _player!.closeFullscreen();
    return true;
  }

  @override
  void didUpdateWidget(covariant EventVideoHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    session.setPreferredCountry(widget.preferredCountry);
    if (oldWidget.pageObserver != widget.pageObserver) {
      oldWidget.pageObserver?.unsubscribe(this);
      if (_route != null) widget.pageObserver?.subscribe(this, _route!);
    }
    if (_ready) _open();
  }

  void setRouteVisible(bool value) {
    _routeVisible = value;
    session.setForeground(
      value &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      session.setForeground(
        _routeVisible && state == AppLifecycleState.resumed,
        // App background/return continues a stream that was live; covering the
        // board with another route still returns paused.
        resumeAfterBackground: state == AppLifecycleState.resumed,
      );
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    // Only a real resize or rotation can turn the inline Twitch view into the
    // expand action. Inset-only churn (system bars, keyboard, the fullscreen
    // transition) must never stop playback; it used to fire this guard before
    // the custom-view callback landed and pause the stream on fullscreen.
    final physicalSize = View.of(context).physicalSize;
    final sizeChanged =
        _lastMetricsSize != null && _lastMetricsSize != physicalSize;
    _lastMetricsSize = physicalSize;
    if (!sizeChanged) return;
    _maybeStopForNarrowTwitch();
  }

  /// Rotation can replace an inline Twitch view with the expand action. Stop
  /// the now-invisible player instead of leaving its audio running.
  /// Fullscreen (native or expanded viewer) owns its own geometry.
  void _maybeStopForNarrowTwitch() {
    if (!mounted ||
        session.expanded ||
        _player?.fullscreenView != null ||
        session.selected?.source.platform != VideoPlatform.twitch) {
      return;
    }
    final view = View.of(context);
    final width =
        (view.physicalSize.width -
            view.viewPadding.left -
            view.viewPadding.right) /
        view.devicePixelRatio;
    if (width < 400 && session.showVideo) session.stopPlayback();
  }

  @override
  void dispose() {
    widget.pageObserver?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(_synchronize);
    _player?.removeListener(_checkFullscreenExit);
    _player?.dispose();
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EventVideoScope(
    session: session,
    player: _player,
    onVideoInteraction: widget.onVideoInteraction,
    child: ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        Stack frame(Widget? fullscreen) => Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (session.expanded && session.showVideo)
              const Positioned.fill(child: _ExpandedEventVideo()),
            if (fullscreen != null) Positioned.fill(child: fullscreen),
          ],
        );
        final player = _player;
        return EventVideoLayoutScope(
          layout: EventVideoLayout.of(session),
          child:
              player == null
                  ? frame(null)
                  : ListenableBuilder(
                    listenable: player,
                    builder:
                        (context, _) => frame(
                          player.fullscreenView == null
                              ? null
                              : _FullscreenVideoOverlay(player: player),
                        ),
                  ),
        );
      },
    ),
  );
}

/// Provider-native fullscreen (Android custom view) above the whole route.
/// Back exits fullscreen first; the route's own back handling must consult
/// [EventVideoHostState.closeFullscreenIfOpen] before popping.
class _FullscreenVideoOverlay extends StatelessWidget {
  const _FullscreenVideoOverlay({required this.player});
  final EventVideoPlayer player;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) player.closeFullscreen();
    },
    child: LayoutBuilder(
      builder:
          (context, constraints) => RotatedBox(
            key: const ValueKey('native_video_landscape'),
            quarterTurns: constraints.maxHeight > constraints.maxWidth ? 1 : 0,
            child: Material(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  player.fullscreenView ?? const SizedBox.shrink(),
                  // A Flutter-side exit: the provider's own chrome may be hidden and
                  // back is not obvious, so fullscreen always has a visible way out.
                  Positioned(
                    top: 8,
                    right: 8,
                    child: SafeArea(
                      child: IconButton(
                        key: const ValueKey('video_exit_fullscreen'),
                        tooltip: 'Exit fullscreen',
                        onPressed: player.closeFullscreen,
                        icon: const Icon(
                          Icons.fullscreen_exit,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    ),
  );
}

class EventVideoFlags extends StatelessWidget {
  const EventVideoFlags({super.key});
  @override
  Widget build(BuildContext context) {
    final session = EventVideoScope.maybeOf(context)!.session;
    return SizedBox(
      key: const ValueKey('event_video_flags'),
      height: EventVideoFlagSlot.heightFor(context),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification) session.setScrolling(true);
          if (n is ScrollEndNotification) session.setScrolling(false);
          return false;
        },
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: session.streams.length,
          separatorBuilder: (_, __) => const SizedBox(width: 4),
          itemBuilder: (context, index) {
            final stream = session.streams[index];
            final selected = session.selected?.id == stream.id;
            final label =
                '${stream.displayName} · ${stream.source.providerName}';
            return Semantics(
              selected: selected,
              button: true,
              label: '${stream.languageLabel}: $label',
              child: Tooltip(
                message: label,
                child: InkWell(
                  key: ValueKey('video_stream_${stream.id}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => session.select(stream.id),
                  child: Container(
                    width: 112,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color:
                          selected
                              ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: .14)
                              : null,
                      border: Border.all(
                        color:
                            selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (stream.flagCode != null)
                          CountryFlag.fromCountryCode(
                            stream.flagCode!,
                            theme: const ImageTheme(width: 28, height: 20),
                          )
                        else
                          const Icon(Icons.language, size: 20),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class EventVideoFlagSlot extends StatelessWidget {
  const EventVideoFlagSlot({super.key, this.active = true});

  final bool active;
  // Hold the same height in both states, allowing room for large system text.
  static double heightFor(BuildContext context) =>
      math.max(56, 32 + MediaQuery.textScalerOf(context).scale(10) * 1.5);

  @override
  Widget build(BuildContext context) {
    // Adjacent pages reserve the same space without subscribing to the picker.
    final height = heightFor(context);
    if (!active) return SizedBox(height: height);
    final session = EventVideoScope.maybeOf(context)?.session;
    if (session == null || !session.showVideo) return const SizedBox.shrink();
    final stream = session.selected!;
    final duration =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220);
    final toggleLabel =
        session.flagsVisible
            ? 'Minimize stream selector'
            : 'Show stream selector';
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        key: const ValueKey('event_video_selector'),
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // Both children stay mounted, preserving the horizontal scroll
              // position. Only this toolbar fades; the native player is never
              // wrapped in an animation or moved by the three-second timer.
              child: AnimatedCrossFade(
                duration: duration,
                firstCurve: Curves.easeInOut,
                secondCurve: Curves.easeInOut,
                crossFadeState:
                    session.flagsVisible
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                firstChild: SizedBox(
                  height: height,
                  child: InkWell(
                    onTap: session.revealFlags,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          if (stream.flagCode != null)
                            CountryFlag.fromCountryCode(
                              stream.flagCode!,
                              theme: const ImageTheme(width: 28, height: 20),
                            )
                          else
                            const Icon(Icons.language, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${stream.displayName} · ${stream.source.providerName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                secondChild: const EventVideoFlags(),
              ),
            ),
            IconButton(
              tooltip: toggleLabel,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              onPressed:
                  session.flagsVisible
                      ? session.minimizeFlags
                      : session.revealFlags,
              icon: AnimatedRotation(
                turns: session.flagsVisible ? .5 : 0,
                duration: duration,
                curve: Curves.easeInOut,
                child: const Icon(Icons.expand_more, size: 20),
              ),
            ),
            IconButton(
              key: const ValueKey('video_close_stream'),
              tooltip: 'Turn off the stream',
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              onPressed: session.toggle,
              icon: const Icon(Icons.close, size: 18),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class EventVideoSurface extends StatelessWidget {
  const EventVideoSurface({
    super.key,
    this.expanded = false,
    this.active = true,
  });
  final bool active;
  final bool expanded;
  @override
  Widget build(BuildContext context) {
    final scope = EventVideoScope.maybeOf(context)!;
    final session = scope.session;
    if (!session.showVideo) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final twitch =
            session.selected!.source.platform == VideoPlatform.twitch;
        final height =
            expanded && constraints.hasBoundedHeight
                ? constraints.maxHeight
                : math.max(
                  twitch ? 300.0 : 200.0,
                  constraints.maxWidth * 9 / 16,
                );
        // Never mount a second native view behind the expanded one.
        if (!active || (session.expanded && !expanded)) {
          return SizedBox(
            height: twitch && constraints.maxWidth < 400 ? 96 : height,
          );
        }
        if (twitch && constraints.maxWidth < 400) {
          return SizedBox(
            height: 96,
            child: Center(
              child: FilledButton.icon(
                key: const ValueKey('video_expand_twitch'),
                onPressed: () {
                  scope.onVideoInteraction?.call();
                  session.setExpanded(true);
                },
                icon: const Icon(Icons.open_in_full),
                label: const Text('Watch Twitch in landscape'),
              ),
            ),
          );
        }
        return SizedBox(
          key: const ValueKey('event_video_surface'),
          height: height,
          child: _EventVideoPlayerBox(scope: scope, expanded: expanded),
        );
      },
    );
  }
}

/// The live player box shared by the inline surface and the expanded viewer.
class _EventVideoPlayerBox extends StatefulWidget {
  const _EventVideoPlayerBox({required this.scope, required this.expanded});
  final bool expanded;
  final EventVideoScope scope;
  @override
  State<_EventVideoPlayerBox> createState() => _EventVideoPlayerBoxState();
}

class _EventVideoPlayerBoxState extends State<_EventVideoPlayerBox> {
  /// Observe taps to reveal the fullscreen button without consuming player
  /// controls or treating seek gestures as taps.
  Offset? _pointerDown;

  static const double _tapSlop = 8;
  Timer? _fullscreenTimer;
  bool _fullscreenVisible = true;

  @override
  void initState() {
    super.initState();
    _scheduleFullscreenDismissal();
  }

  void _scheduleFullscreenDismissal() {
    _fullscreenTimer?.cancel();
    _fullscreenTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _fullscreenVisible = false);
    });
  }

  @override
  void dispose() {
    _fullscreenTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final player = scope.player;
    return ColoredBox(
      color: Colors.black,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _pointerDown = event.position;
          scope.onVideoInteraction?.call();
        },
        onPointerUp: (event) {
          final down = _pointerDown;
          _pointerDown = null;
          if (down == null || (event.position - down).distance > _tapSlop) {
            return;
          }
          scope.session.revealFlags();
          setState(() => _fullscreenVisible = true);
          _scheduleFullscreenDismissal();
        },
        onPointerCancel: (_) => _pointerDown = null,
        child:
            player == null
                ? const Center(
                  child: Text(
                    'Video is not configured',
                    style: TextStyle(color: Colors.white),
                  ),
                )
                : ListenableBuilder(
                  listenable: player,
                  builder:
                      (context, _) => Stack(
                        fit: StackFit.expand,
                        children: [
                          player.buildView(),
                          if (defaultTargetPlatform == TargetPlatform.iOS &&
                              !widget.expanded &&
                              _fullscreenVisible)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: IconButton.filledTonal(
                                tooltip: 'Fullscreen video',
                                onPressed:
                                    () => scope.session.setExpanded(true),
                                icon: const Icon(Icons.fullscreen),
                              ),
                            ),
                          if (player.failed)
                            ColoredBox(
                              color: Colors.black,
                              child: Center(
                                child: TextButton.icon(
                                  onPressed: player.retry,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text(
                                    'Video unavailable · Retry',
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                ),
      ),
    );
  }
}

class _ExpandedEventVideo extends StatelessWidget {
  const _ExpandedEventVideo();
  @override
  Widget build(BuildContext context) {
    final session = EventVideoScope.maybeOf(context)!.session;
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: LayoutBuilder(
          builder:
              (context, constraints) => RotatedBox(
                quarterTurns:
                    constraints.maxHeight > constraints.maxWidth ? 1 : 0,
                child: Column(
                  children: [
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          IconButton(
                            key: const ValueKey('video_close_expanded'),
                            tooltip: 'Return to game',
                            onPressed: () => session.setExpanded(false),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              session.selected?.label ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const EventVideoFlagSlot(),
                    Expanded(
                      child:
                          session.selected?.source.platform ==
                                  VideoPlatform.twitch
                              ? const SingleChildScrollView(
                                child: EventVideoSurface(expanded: true),
                              )
                              : const EventVideoSurface(expanded: true),
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }
}

/// Video makes the old pinned phone header too tall. Keep the complete board
/// and player scrollable, with the stream first and the reader's own engine
/// lines under it, followed by the notation/explorer panel at a bounded height.
class EventVideoGameLayout extends StatelessWidget {
  const EventVideoGameLayout({
    super.key,
    required this.board,
    required this.engine,
    required this.analysis,
    this.sideBySide = false,
    this.active = true,
    this.maxWidth,
  });
  final Widget board, engine, analysis;
  final bool sideBySide, active;
  final double? maxWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      Widget lower() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EventVideoFlagSlot(active: active),
          EventVideoSurface(active: active),
          engine,
          // The notation/explorer panel keeps a bounded, independently
          // usable height under the engine lines on phones and tablets.
          SizedBox(
            height: math.max(260, constraints.maxHeight * .55),
            child: analysis,
          ),
        ],
      );
      if (sideBySide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: SingleChildScrollView(child: board)),
            Expanded(child: SingleChildScrollView(child: lower())),
          ],
        );
      }
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
          child: SingleChildScrollView(
            key: const ValueKey('video_game_scroll'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [board, lower()],
            ),
          ),
        ),
      );
    },
  );
}

/// Shared by the phone popup and the tablet-safe popup.
List<PopupMenuEntry<String>> eventVideoBoardMenuItems(
  BuildContext context,
  EventVideoSession? session,
) => [
  if (session?.hasVideo == true)
    PopupMenuItem(
      value: 'flip_board',
      child: Row(
        children: [
          // Same circular refresh mark as the bottom-bar flip control.
          SvgWidget(
            SvgAsset.refresh,
            height: 20,
            width: 20,
            colorFilter: ColorFilter.mode(
              context.colors.textPrimary,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 8),
          const Text('Flip board'),
        ],
      ),
    ),
  if (session?.hasVideo == true)
    PopupMenuItem(
      value: session!.visible ? 'disable_video' : 'enable_video',
      onTap: session.toggle,
      child: Row(
        children: [
          Icon(
            session.visible
                ? Icons.videocam_off_outlined
                : Icons.videocam_outlined,
            size: 20,
            color: context.colors.textPrimary,
          ),
          const SizedBox(width: 8),
          Text(session.visible ? 'Disable Video' : 'Enable Video'),
        ],
      ),
    ),
];
