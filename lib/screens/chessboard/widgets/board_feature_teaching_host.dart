import 'dart:async';
import 'dart:math' as math;
import 'package:chessever2/screens/chessboard/widgets/discovery_likes_teaching.dart';

import 'package:chessever2/screens/chessboard/utils/board_feature_teaching_tracker.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One host per board route, never per preloaded game or notation page.
class BoardFeatureTeachingHost extends ConsumerStatefulWidget {
  const BoardFeatureTeachingHost({
    super.key,
    required this.child,
    required this.isEligibleVisit,
    required this.eligibleFeatures,
    this.elapsed,
    this.canShowContextual,
  });

  final bool Function()? canShowContextual;
  static bool allowsContextual(BuildContext context, {Object? owner}) {
    final host = context
        .findAncestorStateOfType<_BoardFeatureTeachingHostState>();
    return host == null ||
        (host._dialog == null &&
            host._contextualOwners.every((item) => identical(item, owner)) &&
            (host.widget.canShowContextual?.call() ?? true));
  }

  static ValueChanged<bool> contextualVisibility(
    BuildContext context,
    Object owner,
  ) {
    final host = context
        .findAncestorStateOfType<_BoardFeatureTeachingHostState>();
    return (visible) {
      if (host?.mounted != true) return;
      if (visible) {
        host!._contextualOwners.add(owner);
      } else {
        host!._contextualOwners.remove(owner);
      }
    };
  }

  final Widget child;
  final bool Function() isEligibleVisit;
  final Set<BoardTeachingFeature> Function() eligibleFeatures;

  /// Deterministic engagement clock for widget tests.
  final Duration Function()? elapsed;

  @override
  ConsumerState<BoardFeatureTeachingHost> createState() =>
      _BoardFeatureTeachingHostState();
}

class _BoardFeatureTeachingHostState
    extends ConsumerState<BoardFeatureTeachingHost>
    with WidgetsBindingObserver {
  static const engagementDelay = Duration(seconds: 30);
  static const idleDelay = Duration(seconds: 5);
  final _elapsed = Stopwatch()..start();
  Duration get _time => widget.elapsed?.call() ?? _elapsed.elapsed;
  Duration _lastInteraction = Duration.zero;
  final _pointers = <int>{};
  int _interactions = 0;
  int _visit = 0;
  bool _checking = false;
  final _contextualOwners = <Object>{};
  bool _foreground = true;
  bool _routeCurrent = true;
  Timer? _checkTimer;
  Timer? _dismissTimer;
  DialogRoute<void>? _dialog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_check());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  bool get _routeIsReady =>
      mounted &&
      _foreground &&
      ModalRoute.of(context)?.isCurrent == true &&
      MediaQuery.viewInsetsOf(context).bottom == 0 &&
      widget.isEligibleVisit();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent == true;
    if (current != _routeCurrent) _lastInteraction = _time;
    _routeCurrent = current;
    if (_foreground && current) {
      _elapsed.start();
    } else {
      _elapsed.stop();
    }
  }

  bool get _canShow =>
      _routeIsReady &&
      _dialog == null &&
      _contextualOwners.isEmpty &&
      _pointers.isEmpty &&
      _interactions >= 3 &&
      _time >= engagementDelay &&
      _time - _lastInteraction >= idleDelay;

  Future<void> _check() async {
    if (_checking || !_routeIsReady) return;
    _checking = true;
    try {
      final tracker = ref.read(boardFeatureTeachingTrackerProvider);
      if (_visit == 0) _visit = await tracker.beginVisit();
      if (!_canShow || _visit == 0) return;
      await tracker.tryShow(
        visit: _visit,
        eligible: widget.eligibleFeatures(),
        show: (feature) {
          if (!_canShow || !widget.eligibleFeatures().contains(feature)) {
            return false;
          }
          _show(feature);
          return true;
        },
      );
    } finally {
      _checking = false;
    }
  }

  void _show(BoardTeachingFeature feature) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final tracker = ref.read(boardFeatureTeachingTrackerProvider);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => BoardFeatureTeachingDialog(
        feature: feature,
        onDismiss: _close,
        onDontShowAgain: () {
          unawaited(tracker.disable(feature));
          _close();
        },
      ),
    );
    _dialog = route;
    unawaited(
      navigator.push(route).whenComplete(() {
        _dismissTimer?.cancel();
        if (identical(_dialog, route)) _dialog = null;
        _lastInteraction = _time;
      }),
    );
    if (!MediaQuery.accessibleNavigationOf(context)) {
      _dismissTimer = Timer(const Duration(seconds: 15), _close);
    }
  }

  void _close() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    final route = _dialog;
    _dialog = null;
    if (route == null || !route.isActive) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive && route.navigator?.mounted == true) {
          route.navigator?.removeRoute(route);
        }
      });
      return;
    }
    if (route.isCurrent) {
      route.navigator?.pop();
    } else {
      // Never pop a newer route or leave a teaching attached to a dead board.
      route.navigator?.removeRoute(route);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _routeCurrent) {
      _elapsed.start();
    } else {
      _elapsed.stop();
    }
    _lastInteraction = _time;
    _pointers.clear();
    if (!_foreground) _close();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkTimer?.cancel();
    _close();
    _elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      _pointers.add(event.pointer);
      _lastInteraction = _time;
    },
    onPointerMove: (_) => _lastInteraction = _time,
    onPointerUp: (event) {
      _pointers.remove(event.pointer);
      _interactions++;
      _lastInteraction = _time;
    },
    onPointerCancel: (event) {
      _pointers.remove(event.pointer);
      _lastInteraction = _time;
    },
    child: NotificationListener<ScrollNotification>(
      onNotification: (_) {
        // Include ballistic scrolling after the pointer has been lifted.
        _lastInteraction = _time;
        return false;
      },
      child: DiscoveryLikesTeachingScope.contains(context)
          ? DiscoveryLikesTeaching(
              isEligible: () =>
                  _routeIsReady &&
                  _dialog == null &&
                  (widget.canShowContextual?.call() ?? true),
              child: widget.child,
            )
          : widget.child,
    ),
  );
}

/// Native dialog primitives provide focus, semantics, wrapping and scrolling.
/// Copy is visible from the first frame; only the instructional glyph moves.
class BoardFeatureTeachingDialog extends StatefulWidget {
  const BoardFeatureTeachingDialog({
    super.key,
    required this.feature,
    required this.onDismiss,
    required this.onDontShowAgain,
  });

  final BoardTeachingFeature feature;
  final VoidCallback onDismiss;
  final VoidCallback onDontShowAgain;

  @override
  State<BoardFeatureTeachingDialog> createState() =>
      _BoardFeatureTeachingDialogState();
}

class _BoardFeatureTeachingDialogState extends State<BoardFeatureTeachingDialog>
    with SingleTickerProviderStateMixin {
  late final _demo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _demo.stop();
      _demo.value = 0.5;
    } else if (!_demo.isAnimating && _demo.value == 0) {
      _demo.repeat(count: 2);
    }
  }

  @override
  void dispose() {
    _demo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final like = widget.feature == BoardTeachingFeature.like;
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      scrollable: true,
      title: Text(
        like ? 'Keep a game you like' : 'Swipe the notation',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: 56,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _demo,
                builder: (_, __) {
                  final phase = _demo.value;
                  final pulse = phase < 0.4
                      ? 1 - 0.15 * math.sin(phase * 5 * math.pi).abs()
                      : 1.0;
                  return Center(
                    child: Transform.translate(
                      offset: Offset(
                        like ? 0 : 36 - 72 * Curves.easeInOut.transform(phase),
                        0,
                      ),
                      child: Transform.scale(
                        scale: like ? pulse : 1,
                        child: Icon(
                          like ? Icons.favorite_border : Icons.swipe,
                          size: 32,
                          color: colors.iconPrimary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            like
                ? 'Double-tap the same square on the board to like this game. Find it later in My Likes.'
                : 'Swipe left on the moves to open the Opening Explorer for this position. Swipe right to return to the notation.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colors.textPrimary,
              height: 1.45,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: colors.textPrimary,
            minimumSize: const Size(48, 48),
          ),
          onPressed: widget.onDontShowAgain,
          child: const Text("Don't show again"),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: colors.accentText,
            minimumSize: const Size(48, 48),
          ),
          onPressed: widget.onDismiss,
          child: const Text('Got it'),
        ),
      ],
    );
  }
}
