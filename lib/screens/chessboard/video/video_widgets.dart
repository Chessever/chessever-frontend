import 'dart:async';
import 'dart:math' as math;
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
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
    required super.child,
  }) : super(notifier: session);
  final EventVideoPlayer? player;
  EventVideoSession get session => notifier!;
  static EventVideoScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EventVideoScope>();
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
  });
  final String gameId, tourId, roundId;
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
          saveLanguage: (language) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('ce-video-language.v1', language);
          },
        );
    _player =
        widget.player ??
        (config == null ? null : NativeEventVideoPlayer(config.embedOrigin));
    session.addListener(_synchronize);
    if (widget.session != null || config == null) {
      _ready = true;
      _open();
    } else {
      unawaited(_loadLanguage());
    }
  }

  Future<void> _loadLanguage() async {
    try {
      session.rememberedLanguage = (await SharedPreferences.getInstance())
          .getString('ce-video-language.v1');
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
  @override
  void didUpdateWidget(covariant EventVideoHost oldWidget) {
    super.didUpdateWidget(oldWidget);
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
  void didChangeAppLifecycleState(AppLifecycleState state) => session
      .setForeground(_routeVisible && state == AppLifecycleState.resumed);
  @override
  void didChangeMetrics() {
    // Rotation can replace an inline Twitch view with the expand action.
    // Stop the now-invisible player instead of leaving its audio running.
    if (!mounted ||
        session.expanded ||
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
    _player?.dispose();
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EventVideoScope(
    session: session,
    player: _player,
    child: ListenableBuilder(
      listenable: session,
      builder:
          (context, _) => Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (session.expanded && session.showVideo)
                const Positioned.fill(child: _ExpandedEventVideo()),
            ],
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
      height: 56,
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
                          style: const TextStyle(fontSize: 10),
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

class EventVideoEngineSlot extends StatelessWidget {
  const EventVideoEngineSlot({super.key, required this.engine});
  final Widget engine;
  @override
  Widget build(BuildContext context) {
    final session = EventVideoScope.maybeOf(context)?.session;
    final showFlags =
        session != null && session.showVideo && session.flagsVisible;
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        Offstage(offstage: showFlags, child: engine),
        if (showFlags) const EventVideoFlags(),
      ],
    );
  }
}

class EventVideoSurface extends StatelessWidget {
  const EventVideoSurface({super.key, this.expanded = false});
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
        final height = math.max(
          twitch ? 300.0 : 200.0,
          constraints.maxWidth * 9 / 16,
        );
        // Never mount a second native view behind the expanded one.
        if (session.expanded && !expanded) {
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
                onPressed: () => session.setExpanded(true),
                icon: const Icon(Icons.open_in_full),
                label: const Text('Watch Twitch in landscape'),
              ),
            ),
          );
        }
        final player = scope.player;
        return SizedBox(
          key: const ValueKey('event_video_surface'),
          height: height,
          child: ColoredBox(
            color: Colors.black,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => session.revealFlags(),
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
                                // Fullscreen affordance sits outside the provider's own controls.
                              ],
                            ),
                      ),
            ),
          ),
        );
      },
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
                            icon: const Icon(Icons.close, color: Colors.white),
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
                    if (session.flagsVisible) const EventVideoFlags(),
                    const Expanded(
                      child: SingleChildScrollView(
                        child: EventVideoSurface(expanded: true),
                      ),
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
/// and player scrollable, with a bounded, independently usable notation panel.
class EventVideoGameLayout extends StatelessWidget {
  const EventVideoGameLayout({
    super.key,
    required this.board,
    required this.engine,
    required this.analysis,
    this.sideBySide = false,
    this.maxWidth,
  });
  final Widget board, engine, analysis;
  final bool sideBySide;
  final double? maxWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      Widget lower() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EventVideoEngineSlot(engine: engine),
          const EventVideoSurface(),
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
  EventVideoSession? session,
) => [
  if (session?.hasVideo == true)
    const PopupMenuItem(
      value: 'flip_board',
      child: Row(
        children: [
          Icon(Icons.swap_vert),
          SizedBox(width: 8),
          Text('Swap board'),
        ],
      ),
    ),
];
