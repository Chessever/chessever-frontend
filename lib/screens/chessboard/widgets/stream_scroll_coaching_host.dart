import 'dart:async';
import 'board_feature_teaching_host.dart';
import 'dart:math' as math;
import 'package:chessever2/screens/chessboard/utils/stream_scroll_coaching.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Attached only to the outer board/video scroller, never notation or WebViews.
class StreamScrollCoachingHost extends ConsumerStatefulWidget {
  const StreamScrollCoachingHost({
    super.key,
    required this.gameId,
    required this.active,
    required this.child,
    this.canShow,
  });
  final String gameId;
  final bool active;
  final Widget child;
  final bool Function()? canShow;
  @override
  ConsumerState<StreamScrollCoachingHost> createState() =>
      _StreamScrollCoachingHostState();
}

class _StreamScrollCoachingHostState
    extends ConsumerState<StreamScrollCoachingHost>
    with WidgetsBindingObserver {
  ValueChanged<bool>? _announce;
  late StreamScrollCoachingController _coach;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _announce ??= BoardFeatureTeachingHost.contextualVisibility(context, this);
  }

  @override
  void initState() {
    super.initState();
    _coach = ref.read(streamScrollCoachingProvider(widget.gameId));
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  void _sync() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      ref
          .read(streamScrollCoachingProvider(widget.gameId))
          .setActive(widget.active);
    }
  });
  @override
  void didUpdateWidget(covariant StreamScrollCoachingHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      ref.read(streamScrollCoachingProvider(widget.gameId)).dismiss();
    }
  }

  @override
  void dispose() {
    _announce?.call(false);
    _coach.dismiss(notify: false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coach = ref.watch(streamScrollCoachingProvider(widget.gameId));
    _announce?.call(coach.showing && widget.active);
    return NotificationListener<ScrollNotification>(
      onNotification: (event) {
        if (!widget.active ||
            event.depth != 0 ||
            event.metrics.axisDirection != AxisDirection.down) {
          return false;
        }
        if (event is ScrollStartNotification) {
          coach.startGesture(userDriven: event.dragDetails != null);
        } else if (event is ScrollUpdateNotification &&
            event.dragDetails != null) {
          coach.updateGesture(event.scrollDelta ?? 0);
        } else if (event is ScrollEndNotification) {
          final allowed =
              ModalRoute.of(context)?.isCurrent == true &&
              (widget.canShow?.call() ?? true);
          unawaited(
            coach.endGesture(
              allowed: allowed,
              stillAllowed: () =>
                  mounted &&
                  widget.active &&
                  ModalRoute.of(context)?.isCurrent == true &&
                  (widget.canShow?.call() ?? true),
            ),
          );
        }
        return false;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (coach.showing && widget.active)
            Positioned.fill(
              child: StreamScrollCoachingLesson(
                onOk: coach.acknowledge,
                onDontShowAgain: () => unawaited(coach.disable()),
              ),
            ),
        ],
      ),
    );
  }
}

/// Separate layout regions guarantee the copy never covers the pinch demo.
class StreamScrollCoachingLesson extends StatefulWidget {
  const StreamScrollCoachingLesson({
    super.key,
    required this.onOk,
    required this.onDontShowAgain,
  });
  final VoidCallback onOk, onDontShowAgain;
  @override
  State<StreamScrollCoachingLesson> createState() =>
      _StreamScrollCoachingLessonState();
}

class _StreamScrollCoachingLessonState extends State<StreamScrollCoachingLesson>
    with SingleTickerProviderStateMixin {
  late final _demo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      _demo.stop();
      _demo.value = .5;
    } else if (!_demo.isAnimating) {
      _demo.repeat();
    }
  }

  @override
  void dispose() {
    _demo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: context.colors.surfaceElevated,
                elevation: 0,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Tap '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Icon(
                                Icons.videocam_off_outlined,
                                semanticLabel: 'camera',
                                color: context.colors.textPrimary,
                                size: 24,
                              ),
                            ),
                            const TextSpan(
                              text:
                                  ' to hide the stream, or pinch inward to make the board smaller.',
                            ),
                          ],
                        ),
                        key: const ValueKey('stream_scroll_copy'),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: TextButton(
                              onPressed: widget.onDontShowAgain,
                              style: TextButton.styleFrom(
                                foregroundColor: context.colors.textPrimary,
                                minimumSize: const Size(48, 48),
                              ),
                              child: const Text("Don't show again"),
                            ),
                          ),
                          TextButton(
                            onPressed: widget.onOk,
                            style: TextButton.styleFrom(
                              foregroundColor: context.colors.accentText,
                              minimumSize: const Size(48, 48),
                            ),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: SizedBox(
            key: const ValueKey('stream_scroll_pinch'),
            height: 100,
            child: AnimatedBuilder(
              animation: _demo,
              builder: (context, _) {
                final inset = 48 * Curves.easeInOut.transform(_demo.value);
                return Center(
                  child: Semantics(
                    label: 'Two fingers pinch inward',
                    child: SizedBox(
                      width: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            left: inset,
                            child: Transform.rotate(
                              angle: math.pi / 4,
                              child: Icon(
                                Icons.touch_app,
                                color: context.colors.textPrimary,
                                size: 36,
                                shadows: [
                                  Shadow(
                                    color: Colors.black38,
                                    offset: Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            right: inset,
                            child: Transform.rotate(
                              angle: -math.pi / 4,
                              child: Icon(
                                Icons.touch_app,
                                color: context.colors.textPrimary,
                                size: 36,
                                shadows: [
                                  Shadow(
                                    color: Colors.black38,
                                    offset: Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.arrow_forward,
                                color: context.colors.textPrimary,
                                size: 18,
                                shadows: [
                                  Shadow(
                                    color: Colors.black38,
                                    offset: Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                              Icon(
                                Icons.arrow_back,
                                color: context.colors.textPrimary,
                                size: 18,
                                shadows: [
                                  Shadow(
                                    color: Colors.black38,
                                    offset: Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}
