import 'dart:async';

import 'package:chessever2/screens/chessboard/utils/board_feature_teaching_tracker.dart';
import 'package:chessever2/screens/chessboard/widgets/board_feature_teaching_host.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Route-local provenance, installed only after the ranking's access gates.
/// It cannot leak into another board opened from a different source.
class DiscoveryLikesTeachingScope extends InheritedWidget {
  const DiscoveryLikesTeachingScope({super.key, required super.child});

  static bool contains(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DiscoveryLikesTeachingScope>() !=
      null;

  @override
  bool updateShouldNotify(DiscoveryLikesTeachingScope oldWidget) => false;
}

/// No scrim or modal barrier: only the capsule intercepts input. The lesson
/// never receives a like callback and cannot save or toggle the actual game.
class DiscoveryLikesTeaching extends ConsumerStatefulWidget {
  const DiscoveryLikesTeaching({
    super.key,
    required this.child,
    required this.isEligible,
  });
  final Widget child;
  final bool Function() isEligible;

  @override
  ConsumerState<DiscoveryLikesTeaching> createState() =>
      _DiscoveryLikesTeachingState();
}

class _DiscoveryLikesTeachingState extends ConsumerState<DiscoveryLikesTeaching>
    with WidgetsBindingObserver {
  Timer? _watch;
  Timer? _dismiss;
  ValueChanged<bool>? _announce;
  bool _visible = false;
  bool _checking = false;
  bool _finished = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    // Let the board's asynchronous Swipe/Pinch preference checks settle first.
    _watch = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_check()),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _announce ??= BoardFeatureTeachingHost.contextualVisibility(context, this);
  }

  bool get _ready =>
      mounted &&
      _foreground &&
      ModalRoute.of(context)?.isCurrent == true &&
      MediaQuery.viewInsetsOf(context).bottom == 0 &&
      widget.isEligible() &&
      BoardFeatureTeachingHost.allowsContextual(context, owner: this);

  Future<void> _check() async {
    if (_visible && !_ready) {
      _close();
      return;
    }
    if (_finished || _checking || !_ready) return;
    _checking = true;
    try {
      await ref.read(boardFeatureTeachingTrackerProvider).tryShowDiscoveryLikes(
        () {
          if (!_ready) return false;
          _finished = true;
          _announce?.call(true);
          setState(() => _visible = true);
          if (!MediaQuery.accessibleNavigationOf(context)) {
            _dismiss = Timer(const Duration(seconds: 8), _close);
          }
          return true;
        },
      );
    } finally {
      _checking = false;
    }
  }

  void _close() {
    _dismiss?.cancel();
    _watch?.cancel();
    _announce?.call(false);
    if (mounted && _visible) setState(() => _visible = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && _visible) _close();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watch?.cancel();
    _dismiss?.cancel();
    _announce?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      if (_visible)
        Positioned(
          left: 12,
          right: 12,
          bottom: 72 + MediaQuery.viewPaddingOf(context).bottom,
          child: Material(
            color: context.colors.surfaceElevated,
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: Text('Double-tap to like')),
                        IconButton(
                          tooltip: 'Dismiss',
                          onPressed: _close,
                          icon: const Icon(Icons.close),
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 80,
                      child: DoubleTapHeartTeachingDemo(),
                    ),
                    const Text(
                      'Double-tap the same square on the board. Find your liked games in My Likes.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// Reused from the original LikeTutorialOverlay (before 0605d9b7): two finger
/// presses, followed by a blooming/rising heart. This is demonstration only,
/// not HeartBurst/LikeFlight and not a synthetic gesture on the real board.
class DoubleTapHeartTeachingDemo extends StatefulWidget {
  const DoubleTapHeartTeachingDemo({super.key});
  @override
  State<DoubleTapHeartTeachingDemo> createState() =>
      _DoubleTapHeartTeachingDemoState();
}

class _DoubleTapHeartTeachingDemoState extends State<DoubleTapHeartTeachingDemo>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _animation.value = 0.5;
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          final progress = _animation.value;
          double tapDip(double center) {
            final d = (progress - center).abs();
            return d > 0.08 ? 0 : 1 - d / 0.08;
          }

          final dip = (tapDip(0.12) + tapDip(0.30)).clamp(0.0, 1.0);
          final heartT = ((progress - 0.32) / 0.42).clamp(0.0, 1.0);
          final heartScale =
              (heartT < 0.4
                      ? heartT / 0.4 * 1.15
                      : 1.15 - (heartT - 0.4) / 0.6 * 0.15)
                  .clamp(0.0, 1.3);
          final heartOpacity = progress > 0.32 && progress < 0.82
              ? (heartT < 0.2
                    ? heartT / 0.2
                    : (1 - (heartT - 0.2) / 0.8).clamp(0.0, 1.0))
              : 0.0;
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Transform.translate(
                offset: Offset(0, -16 - heartT * 28),
                child: Opacity(
                  opacity: heartOpacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: heartScale,
                    child: Icon(
                      Icons.favorite_rounded,
                      color: context.colors.danger,
                      size: 30,
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: 1 - dip * 0.18,
                child: Icon(
                  Icons.touch_app_rounded,
                  size: 44,
                  color: context.colors.iconPrimary,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
