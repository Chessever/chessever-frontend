import 'dart:async';
import 'package:chessever_watch_bridge/chessever_watch_bridge.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import 'core/watch_notification_route.dart';
import 'core/watch_repository.dart';
import 'ui/watch_event_pages.dart';
import 'ui/watch_game_page.dart';
import 'ui/watch_home_page.dart';
import 'ui/watch_widgets.dart';
import 'watch_controller.dart';

class ChessEverWatchApp extends StatefulWidget {
  const ChessEverWatchApp({super.key, this.controller});
  final WatchController? controller;
  @override
  State<ChessEverWatchApp> createState() => _ChessEverWatchAppState();
}

class _ChessEverWatchAppState extends State<ChessEverWatchApp>
    with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  late WatchController _controller;
  ChesseverWatchBridge? _notifications;
  StreamSubscription<Map<String, dynamic>>? _taps;
  Timer? _timer;
  bool _active = true;
  Map<String, dynamic>? _pendingTap;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        WatchController(
          repository: WatchRepository(
            apiKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
          ),
        );
    _controller.addListener(_openPending);
    if (widget.controller == null) unawaited(_controller.initialize());
    WidgetsBinding.instance.addObserver(this);
    WatchAlwaysOn.state.addListener(_displayChanged);
    _displayChanged();
    if (FlutterWatchosPlatform.isWatch) {
      _notifications = ChesseverWatchBridge();
      _taps = _notifications!.taps.listen((payload) {
        _pendingTap = payload;
        _openPending();
      });
      _notifications!.start();
    }
  }

  void _displayChanged() {
    _timer?.cancel();
    if (_active && !WatchAlwaysOn.isActive) {
      _timer = Timer.periodic(const Duration(seconds: 45), (_) {
        if (!_controller.loading &&
            _navigator.currentState?.canPop() == false) {
          unawaited(_controller.refresh());
        }
      });
      _openPending();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _displayChanged();
    if (_active) {
      unawaited(_controller.requestSync());
      unawaited(_controller.refresh());
    }
  }

  void _openPending() {
    if (!mounted ||
        _opening ||
        _pendingTap == null ||
        !_active ||
        WatchAlwaysOn.isActive ||
        !_controller.repository.configured) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_opening && _pendingTap != null) {
        unawaited(_openNotification());
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _openNotification() async {
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    _opening = true;
    final payload = _pendingTap!;
    _pendingTap = null;
    final route = WatchNotificationRoute.fromPayload(payload);
    try {
      final repository = _controller.repository;
      final eventId = route.gameId != null
          ? await repository.eventFor(gameId: route.gameId)
          : route.eventId ??
                await repository.eventFor(
                  tourId: route.tourId,
                  roundId: route.roundId,
                );
      final event = eventId == null
          ? null
          : await repository.currentEvent(eventId);
      if (!mounted) return;
      navigator.popUntil((route) => route.isFirst);
      if (event == null) {
        unawaited(
          navigator.push(
            CupertinoPageRoute<void>(
              builder: (_) => const WatchPage(
                title: 'ChessEver alert',
                children: [
                  WatchNote(
                    'This alert is outside Current events. Open it on iPhone.',
                  ),
                ],
              ),
            ),
          ),
        );
      } else if (route.gameId != null) {
        final game = await repository.game(route.gameId!);
        if (!mounted) return;
        if (game != null) {
          final tours = await repository.tours(event.id);
          if (!mounted) return;
          unawaited(
            navigator.push(
              CupertinoPageRoute<void>(
                builder: (_) => WatchGamePage(
                  controller: _controller,
                  game: game,
                  tour: tours.where((t) => t.id == game.tourId).firstOrNull,
                ),
              ),
            ),
          );
        }
      } else {
        unawaited(
          navigator.push(
            CupertinoPageRoute<void>(
              builder: (_) => watchEventPage(_controller, event),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        unawaited(
          navigator.push(
            CupertinoPageRoute<void>(
              builder: (_) => const WatchPage(
                title: 'ChessEver alert',
                children: [
                  WatchNote(
                    'Could not open the alert. Try from Current events.',
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } finally {
      _opening = false;
      _openPending();
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoApp(
    title: 'ChessEver',
    navigatorKey: _navigator,
    debugShowCheckedModeBanner: false,
    theme: const CupertinoThemeData(
      brightness: Brightness.dark,
      primaryColor: WatchStyle.ink,
      scaffoldBackgroundColor: WatchStyle.background,
      textTheme: CupertinoTextThemeData(textStyle: WatchStyle.body),
    ),
    home: WatchHomePage(controller: _controller),
    builder: (context, child) => WatchAlwaysOnBuilder(
      child: child,
      builder: (context, dimmed, navigator) => Stack(
        children: [
          Offstage(
            offstage: dimmed,
            child: TickerMode(enabled: !dimmed, child: navigator!),
          ),
          if (dimmed)
            const WatchPage(
              title: 'ChessEver',
              root: true,
              children: [WatchNote('Raise your wrist for current events.')],
            ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _timer?.cancel();
    WatchAlwaysOn.state.removeListener(_displayChanged);
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_openPending);
    if (widget.controller == null) _controller.dispose();
    unawaited(_taps?.cancel());
    unawaited(_notifications?.dispose());
    super.dispose();
  }
}
