import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';

/// A deliberate upward pull at the article's end turns one reader page.
/// Only finger travel beyond the bottom counts, never a ballistic fling.
/// The footer is also a regular button for readers who cannot pull.
class NewsPullNext extends StatefulWidget {
  const NewsPullNext({
    super.key,
    required this.onNext,
    required this.builder,
    this.nextIsAd = false,
  });

  final Future<void> Function()? onNext;
  final bool nextIsAd;
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

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NewsPullNext oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onNext == null) _reset();
  }

  void _reset() {
    _originY = null;
    _armed = false;
    if (MediaQuery.disableAnimationsOf(context)) {
      _progress.value = 0;
    } else {
      unawaited(_progress.animateBack(0, curve: Curves.easeOutCubic));
    }
  }

  void _track(double y) {
    final raw = math.max(0.0, _originY! - y);
    final shown = _ceiling * (1 - 1 / (raw * 0.85 / _ceiling + 1));
    final armed = shown >= _trigger;
    if (armed && !_armed) unawaited(HapticFeedbackService.selection());
    _armed = armed;
    _progress.value = (shown / _trigger).clamp(0.0, 1.0);
  }

  bool _onScroll(ScrollNotification notification) {
    if (_busy ||
        widget.onNext == null ||
        _pointer == null ||
        notification.depth != 0 ||
        notification.metrics.axisDirection != AxisDirection.down) {
      return false;
    }
    switch (notification) {
      case OverscrollNotification(:final dragDetails, :final overscroll):
        if (dragDetails != null &&
            overscroll > 0 &&
            notification.metrics.extentAfter <= 0) {
          _originY ??= dragDetails.globalPosition.dy + overscroll;
          _track(dragDetails.globalPosition.dy);
        }
      case ScrollUpdateNotification(:final dragDetails):
        if (dragDetails != null && _originY != null) {
          if (notification.metrics.extentAfter > 0) {
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
      unawaited(_next());
    } else {
      _reset();
    }
  }

  Future<void> _next() async {
    final onNext = widget.onNext;
    if (_busy || onNext == null) return;
    setState(() => _busy = true);
    try {
      await onNext();
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
                builder: (context, _) => Semantics(
                  button: true,
                  label: widget.nextIsAd
                      ? 'Continue to advertisement'
                      : 'Next article',
                  hint: 'Tap or pull up at the end of the article',
                  value: _busy
                      ? 'Loading'
                      : _armed
                      ? 'Release to continue'
                      : null,
                  liveRegion: _busy || _armed,
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
                          child: _busy || _progress.value > 0
                              ? CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.textPrimary,
                                  backgroundColor: colors.skeleton,
                                  value: _busy
                                      ? (MediaQuery.disableAnimationsOf(context)
                                            ? 1
                                            : null)
                                      : _progress.value,
                                )
                              : const Icon(
                                  Icons.arrow_downward_rounded,
                                  size: 20,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            _busy
                                ? 'Opening next $destination…'
                                : _armed
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
                ),
              ),
            ),
          );
    return NotificationListener<ScrollNotification>(
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
  }
}
