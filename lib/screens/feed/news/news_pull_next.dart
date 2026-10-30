import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';

/// Deliberate pulls beyond an article's edges turn one reader page.
/// Only finger travel beyond the edge counts, never a ballistic fling.
/// The footer is also a regular button for readers who cannot pull.
class NewsPullNext extends StatefulWidget {
  const NewsPullNext({
    super.key,
    required this.onNext,
    required this.builder,
    this.nextIsAd = false,
    this.onPrevious,
    this.previousIsAd = false,
  });

  final Future<void> Function()? onNext;
  final bool nextIsAd;
  final Future<void> Function()? onPrevious;
  final bool previousIsAd;
  final Widget Function(BuildContext context, Widget footer) builder;

  @override
  State<NewsPullNext> createState() => _NewsPullNextState();
}

class _NewsPullNextState extends State<NewsPullNext>
    with SingleTickerProviderStateMixin {
  static const double _trigger = 56;
  static const double _ceiling = 100;
  late final _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  double? _originY;
  int? _pointer;
  bool _busy = false;
  bool _armed = false;
  bool _previous = false;
  bool _reduceMotion = false;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(NewsPullNext oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy &&
        (_previous ? widget.onPrevious == null : widget.onNext == null)) {
      _reset();
    }
  }

  void _reset() {
    _originY = null;
    _armed = false;
    if (_reduceMotion) {
      _progress.value = 0;
    } else {
      unawaited(_progress.animateBack(0, curve: Curves.easeOutCubic));
    }
  }

  void _track(double y) {
    final raw = math.max(0.0, _previous ? y - _originY! : _originY! - y);
    final shown = _ceiling * (1 - 1 / (raw * 0.85 / _ceiling + 1));
    final armed = shown >= _trigger;
    if (armed && !_armed) unawaited(HapticFeedbackService.selection());
    _armed = armed;
    _progress.value = (shown / _trigger).clamp(0.0, 1.0);
  }

  bool _onScroll(ScrollNotification notification) {
    if (_busy ||
        (widget.onNext == null && widget.onPrevious == null) ||
        _pointer == null ||
        notification.depth != 0 ||
        notification.metrics.axisDirection != AxisDirection.down) {
      return false;
    }
    switch (notification) {
      case OverscrollNotification(:final dragDetails, :final overscroll):
        if (dragDetails == null) return false;
        final previous =
            overscroll < 0 &&
            notification.metrics.extentBefore <= 0 &&
            widget.onPrevious != null;
        final next =
            overscroll > 0 &&
            notification.metrics.extentAfter <= 0 &&
            widget.onNext != null;
        if (previous || next) {
          if (_originY == null || _previous != previous) {
            _previous = previous;
            _originY = dragDetails.globalPosition.dy + overscroll;
          }
          _track(dragDetails.globalPosition.dy);
        }
      case ScrollUpdateNotification(:final dragDetails):
        if (dragDetails != null && _originY != null) {
          if ((_previous
                  ? notification.metrics.extentBefore
                  : notification.metrics.extentAfter) >
              0) {
            _reset();
          } else {
            _track(dragDetails.globalPosition.dy);
          }
        }
      default:
        break;
    }
    return false;
  }

  void _release() {
    _pointer = null;
    final advance = _armed;
    _originY = null;
    if (advance) {
      unawaited(_navigate(previous: _previous));
    } else {
      _reset();
    }
  }

  Future<void> _next() => _navigate();

  Future<void> _navigate({bool previous = false}) async {
    final action = previous ? widget.onPrevious : widget.onNext;
    if (_busy || action == null) return;
    setState(() {
      _previous = previous;
      _busy = true;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final destination = widget.nextIsAd ? 'ad' : 'article';
    final footer = widget.onNext == null
        ? const SizedBox.shrink()
        : Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Center(
              child: AnimatedBuilder(
                animation: _progress,
                builder: (context, _) {
                  final nextBusy = _busy && !_previous;
                  final nextArmed = _armed && !_previous;
                  final nextProgress = _previous ? 0.0 : _progress.value;
                  return Semantics(
                    button: true,
                    label: widget.nextIsAd
                        ? 'Continue to advertisement'
                        : 'Next article',
                    hint: 'Tap or pull up at the end of the article',
                    value: nextBusy
                        ? 'Loading'
                        : nextArmed
                        ? 'Release to continue'
                        : null,
                    liveRegion: nextBusy || nextArmed,
                    excludeSemantics: true,
                    onTap: _busy ? null : _next,
                    child: TextButton(
                      key: const ValueKey('news_next'),
                      onPressed: _busy ? null : _next,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textPrimary,
                        disabledForegroundColor: colors.textPrimary,
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 20,
                            child: nextBusy || nextProgress > 0
                                ? CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.textPrimary,
                                    backgroundColor: colors.skeleton,
                                    value: nextBusy
                                        ? (MediaQuery.disableAnimationsOf(
                                                context,
                                              )
                                              ? 1
                                              : null)
                                        : nextProgress,
                                  )
                                : const Icon(
                                    Icons.arrow_downward_rounded,
                                    size: 20,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              nextBusy
                                  ? 'Opening next $destination…'
                                  : nextArmed
                                  ? 'Release for next $destination'
                                  : 'Pull up for next $destination',
                              textAlign: TextAlign.center,
                              style: AppTypography.textSmMedium.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
    final reader = NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Listener(
        onPointerDown: (event) => _pointer ??= event.pointer,
        onPointerUp: (event) {
          if (event.pointer == _pointer) _release();
        },
        onPointerCancel: (event) {
          if (event.pointer != _pointer) return;
          _pointer = null;
          _reset();
        },
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: widget.builder(context, footer),
        ),
      ),
    );
    return Stack(
      children: [
        reader,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 56,
          left: 20,
          right: 20,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _progress,
              builder: (context, _) {
                if (!_previous || (!_busy && _progress.value == 0)) {
                  return const SizedBox.shrink();
                }
                final destination = widget.previousIsAd ? 'ad' : 'article';
                return Center(
                  child: Semantics(
                    liveRegion: _armed || _busy,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        _busy
                            ? 'Opening previous $destination…'
                            : _armed
                            ? 'Release for previous $destination'
                            : 'Pull down for previous $destination',
                        textAlign: TextAlign.center,
                        style: AppTypography.textSmMedium.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
